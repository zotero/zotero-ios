//
//  ConflictCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 09.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol ConflictReceiver {
    func resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void)
}

protocol SyncRequestReceiver {
    func askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void)
    func askToCreateZoteroDirectory(url: String, create: @escaping () -> Void, cancel: @escaping () -> Void)
}

typealias ConflictCoordinator = ConflictReceiver & SyncRequestReceiver
