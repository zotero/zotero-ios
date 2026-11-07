//
//  SubscribeWsMessage.swift
//  Zotero
//
//  Created by Michal Rentka on 01.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SubscribeWsMessage: Encodable {
    enum Subscription: Encodable {
        case apiKey(String)
        case topics([String])

        private enum CodingKeys: String, CodingKey {
            case apiKey
            case topics
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .apiKey(let apiKey):
                try container.encode(apiKey, forKey: .apiKey)

            case .topics(let topics):
                try container.encode(topics, forKey: .topics)
            }
        }
    }

    let action: String
    let subscriptions: [Subscription]

    init(subscription: Subscription) {
        action = "createSubscriptions"
        subscriptions = [subscription]
    }

    init(apiKey: String) {
        self.init(subscription: .apiKey(apiKey))
    }

    init(topic: String) {
        self.init(subscription: .topics([topic]))
    }
}
