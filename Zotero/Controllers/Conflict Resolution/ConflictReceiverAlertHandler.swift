//
//  ConflictReceiverAlertHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 16.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Action that is performed on conflict receiver.
typealias ConflictReceiverAlertAction = (ConflictViewControllerReceiver, @escaping () -> Void) -> Void

/// Handler which processes data for given conflict.
protocol ConflictReceiverAlertHandler {
    /// Action called for each loaded receiver.
    var receiverAction: ConflictReceiverAlertAction { get }
    /// Completion block called after all receivers were called.
    var completion: () -> Void { get }
}
