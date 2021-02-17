//
//  ConflictAlertQueueHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 17.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

/// Alert creation action called for each object.
typealias ConflictAlertQueueAction = (Int, (@escaping () -> Void)) -> UIAlertController

/// Handler that processes data for given queue.
protocol ConflictAlertQueueHandler {
    /// Number of alerts that need to be showed.
    var count: Int { get }
    /// Action called for each object to create appropriate alert.
    var alertAction: ConflictAlertQueueAction { get }
    /// Completion block called after all alerts were presented.
    var completion: () -> Void { get }
}
