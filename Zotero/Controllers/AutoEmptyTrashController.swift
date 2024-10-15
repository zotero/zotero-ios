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

        let daysSinceLastEmpty = Int(Date.now.timeIntervalSince(Defaults.shared.trashLastAutoEmptyDate) / 86400)
        DDLogInfo("AutoEmptyTrashController: days since last auto empty - \(daysSinceLastEmpty) (\(Defaults.shared.trashLastAutoEmptyDate.timeIntervalSince1970))")
        guard daysSinceLastEmpty >= Defaults.shared.trashAutoEmptyThreshold else { return }

        queue.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            guard let self else { return }
            do {
                try dbStorage.perform(request: EmptyTrashDbRequest(libraryId: .custom(.myLibrary)), on: queue)
                Defaults.shared.trashLastAutoEmptyDate = .now
            } catch let error {
                DDLogError("AutoEmptyTrashController: can't empty trash - \(error)")
            }
        }
    }
}
