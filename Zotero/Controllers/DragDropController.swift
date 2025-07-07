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

final class DragDropController {
    func dragItem(from item: RItem, citationController: CitationController?, disposeBag: DisposeBag) -> UIDragItem {
        let itemProvider = NSItemProvider()
        if let citationController {
            registerDataRepresentation(for: itemProvider, contentType: .html, item: item, citationController: citationController, format: .html, disposeBag: disposeBag)
            registerDataRepresentation(for: itemProvider, contentType: .plainText, item: item, citationController: citationController, format: .text, disposeBag: disposeBag)
        }
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = item
        return dragItem

        func registerDataRepresentation(
            for itemProvider: NSItemProvider,
            contentType: UTType,
            item: RItem,
            citationController: CitationController,
            format: CitationController.Format,
            disposeBag: DisposeBag
        ) {
            let key = item.key
            let libraryId = item.libraryIdentifier
            itemProvider.registerDataRepresentation(for: contentType, visibility: .all) { completion in
                let progress = Progress(totalUnitCount: 2)
                DispatchQueue.main.async {
                    var session: CitationController.Session?
                    citationController.startSession(
                        for: Set(arrayLiteral: key),
                        libraryId: libraryId,
                        styleId: Defaults.shared.quickCopyStyleId,
                        localeId: Defaults.shared.quickCopyLocaleId
                    )
                    .flatMap({ startedSession -> Single<String> in
                        session = startedSession
                        progress.completedUnitCount = 1
                        return citationController.bibliography(for: startedSession, format: format)
                    })
                    .subscribe { bibliography in
                        progress.completedUnitCount = 2
                        completion(bibliography.data(using: .utf8), nil)
                        if let session {
                            citationController.endSession(session)
                        }
                    } onFailure: { error in
                        progress.completedUnitCount = 2
                        completion(nil, error)
                        if let session {
                            citationController.endSession(session)
                        }
                    }
                    .disposed(by: disposeBag)
                }
                return progress
            }
        }
    }
}
