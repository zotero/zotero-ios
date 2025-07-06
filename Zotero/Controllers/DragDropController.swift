//
//  DragDropController.swift
//  Zotero
//
//  Created by Michal Rentka on 01/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

@preconcurrency
import RxSwift

struct DragSessionItemsLocalContext {
    let libraryIdentifier: LibraryIdentifier
    let keys: Set<String>

    func createNewContext(with item: RItem) -> Self? {
        guard libraryIdentifier == item.libraryIdentifier, !keys.contains(item.key) else { return nil }
        return Self(libraryIdentifier: libraryIdentifier, keys: keys.union([item.key]))
    }
}

@preconcurrency
final class DragDropController {
    private var citationSessions: [UUID: CitationController.Session] = [:]

    func dragItem(from item: RItem, citationController: CitationController?, disposeBag: DisposeBag) -> UIDragItem {
        let itemProvider = NSItemProvider()
        let key = item.key
        let libraryId = item.libraryIdentifier
        if let citationController {
            registerDataRepresentation(for: itemProvider, contentType: .html, citationController: citationController, format: .html)
            registerDataRepresentation(for: itemProvider, contentType: .plainText, citationController: citationController, format: .text)
        }

        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = item
        return dragItem

        func registerDataRepresentation(for itemProvider: NSItemProvider, contentType: UTType, citationController: CitationController, format: CitationController.Format) {
            let uuid = UUID()
            itemProvider.registerDataRepresentation(for: contentType, visibility: .all) { completion in
                let progress = Progress(totalUnitCount: 2)
                DispatchQueue.main.async {
                    citationController.startSession(
                        for: Set(arrayLiteral: key),
                        libraryId: libraryId,
                        styleId: Defaults.shared.quickCopyStyleId,
                        localeId: Defaults.shared.quickCopyLocaleId
                    )
                    .do(onSuccess: { [weak self] session in
                        self?.citationSessions[uuid] = session
                        progress.completedUnitCount = 1
                    })
                    .flatMap({ session -> Single<String> in
                        return citationController.bibliography(for: session, format: format)
                    })
                    .subscribe { [weak self] bibliography in
                        progress.completedUnitCount = 2
                        completion(bibliography.data(using: .utf8), nil)
                        guard let self, let session = citationSessions.removeValue(forKey: uuid) else { return }
                        citationController.endSession(session)
                    } onFailure: { [weak self] error in
                        progress.completedUnitCount = 2
                        completion(nil, error)
                        guard let self, let session = citationSessions.removeValue(forKey: uuid) else { return }
                        citationController.endSession(session)
                    }
                    .disposed(by: disposeBag)
                }
                return progress
            }
        }
    }
}
