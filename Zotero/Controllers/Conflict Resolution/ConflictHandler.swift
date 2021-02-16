//
//  ConflictHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 16.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol ConflictHandler {
    var receiverAction: ConflictQueueAction { get }
    var completion: () -> Void { get }
}
