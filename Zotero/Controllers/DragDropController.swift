//
//  DragDropController.swift
//  Zotero
//
//  Created by Michal Rentka on 01/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

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
            let uuid = UUID()
            itemProvider.registerDataRepresentation(for: .html, visibility: .all) { completion in
                DispatchQueue.main.async {
                    citationController.startSession(
                        for: Set(arrayLiteral: key),
                        libraryId: libraryId,
                        styleId: Defaults.shared.quickCopyStyleId,
                        localeId: Defaults.shared.quickCopyLocaleId
                    )
                    .do(onSuccess: { [weak self] session in
                        self?.citationSessions[uuid] = session
                    })
                    .flatMap({ session -> Single<String> in
                        return citationController.bibliography(for: session, format: .html)
                    })
                    .subscribe { [weak self] html in
                        completion(html.data(using: .utf8), nil)
                        guard let self, let session = citationSessions.removeValue(forKey: uuid) else { return }
                        citationController.endSession(session)
                    } onFailure: { [weak self] error in
                        completion(nil, error)
                        guard let self, let session = citationSessions.removeValue(forKey: uuid) else { return }
                        citationController.endSession(session)
                    }
                    .disposed(by: disposeBag)
                }
                return nil
            }
        }

        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = item
        return dragItem
    }
}
