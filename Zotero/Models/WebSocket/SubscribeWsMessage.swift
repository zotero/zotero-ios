//
//  SubscribeWsMessage.swift
//  Zotero
//
//  Created by Michal Rentka on 01.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SubscribeWsMessage: Encodable {
    let action: String
    let subscriptions: [[String: String]]

    init(apiKey: String) {
        self.action = "createSubscriptions"
        self.subscriptions = [["apiKey": apiKey]]
    }
}
