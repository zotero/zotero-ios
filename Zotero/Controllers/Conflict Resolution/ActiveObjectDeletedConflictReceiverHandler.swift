//
//  ActiveObjectDeletedConflictHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 16.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ActiveObjectDeletedConflictReceiverHandler: ConflictReceiverAlertHandler {
    let receiverAction: ConflictReceiverAlertAction
    let completion: () -> Void

    init(collections: [String], items: [String], libraryId: LibraryIdentifier, completion: @escaping ([String], [String], [String], [String]) -> Void) {
        var toDeleteCollections: [String] = collections
        var toRestoreCollections: [String] = []
        var toDeleteItems: [String] = items
        var toRestoreItems: [String] = []

        self.receiverAction = { receiver, completion in
            if let key = receiver.shows(object: .collection, libraryId: libraryId), toDeleteCollections.contains(key) {
                // If receiver shows a collection, ask whether it can be deleted
                receiver.canDeleteObject { delete in
                    // If deletion was not allowed, move the key to restore array
                    if !delete {
                        toRestoreCollections.append(key)
                        if let idx = toDeleteCollections.firstIndex(of: key) {
                            toDeleteCollections.remove(at: idx)
                        }
                    }
                    completion()
                }
            } else if let key = receiver.shows(object: .item, libraryId: libraryId), toDeleteItems.contains(key) {
                // If receiver shows an item, ask whether it can be deleted
                receiver.canDeleteObject { delete in
                    // If deletion was not allowed, move the key to restore array
                    if !delete {
                        toRestoreItems.append(key)
                        if let idx = toDeleteItems.firstIndex(of: key) {
                            toDeleteItems.remove(at: idx)
                        }
                    }
                    completion()
                }
            } else {
                completion()
            }
        }

        self.completion = {
            completion(toDeleteCollections, toRestoreCollections, toDeleteItems, toRestoreItems)
        }
    }
}
