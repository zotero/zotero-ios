//
//  ChangedItemsDeletedAlertQueueHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 17.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct ChangedItemsDeletedAlertQueueHandler: ConflictAlertQueueHandler {
    let count: Int
    let alertAction: ConflictAlertQueueAction
    let completion: () -> Void

    init(items: [(String, String)], completion: @escaping ([String], [String]) -> Void) {
        self.count = items.count

        var toDelete: [String] = []
        var toRestore: [String] = []

        self.alertAction = { index, completion in
            let (key, title) = items[index]
            let controller = UIAlertController(title: L10n.warning, message: L10n.Sync.ConflictResolution.changedItemDeleted(title), preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: L10n.restore, style: .default, handler: { _ in
                toRestore.append(key)
                completion()
            }))
            controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { _ in
                toDelete.append(key)
                completion()
            }))
            return controller
        }

        self.completion = {
            completion(toDelete, toRestore)
        }
    }
}
