//
//  AutoEmptyTrashController.swift
//  Zotero
//
//  Created by Michal Rentka on 09.10.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import CocoaLumberjackSwift

final class AutoEmptyTrashController {
    private unowned let dbStorage: DbStorage
    private let queue: DispatchQueue

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        queue = DispatchQueue(label: "org.zotero.AutoEmptyTrashController.queue", qos: .utility)
    }

    func autoEmptyIfNeeded() {
        if Defaults.shared.trashAutoEmptyThreshold == 0 {
            DDLogInfo("AutoEmptyTrashController: auto emptying disabled")
            return
        }

        // Auto empty trash once a day
        guard Date.now.timeIntervalSince(Defaults.shared.trashLastAutoEmptyDate) >= 86400 else { return }

        DDLogInfo("AutoEmptyTrashController: perform auto empty")
        Defaults.shared.trashLastAutoEmptyDate = .now

        queue.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            guard let self else { return }
            do {
                try dbStorage.perform(request: AutoEmptyTrashDbRequest(libraryId: .custom(.myLibrary)), on: queue)
            } catch let error {
                DDLogError("AutoEmptyTrashController: can't empty trash - \(error)")
            }
        }
    }
}
