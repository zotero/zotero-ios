//
//  WsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 01.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WsResponse {
    enum Event: String {
        case connected = "connected"
        case subscriptionCreated = "subscriptionsCreated"
        case subscriptionDeleted = "subscriptionsDeleted"
        case topicAdded = "topicAdded"
        case topicRemoved = "topicRemoved"
        case topicUpdated = "topicUpdated"
    }

    enum Error: Swift.Error {
        case unknownEvent(String)
    }

    let event: Event
}

extension WsResponse: Decodable {
    enum Keys: String, CodingKey {
        case event = "event"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let eventStr = try container.decode(String.self, forKey: .event)

        guard let event = Event(rawValue: eventStr) else {
            throw WsResponse.Error.unknownEvent(eventStr)
        }

        self.init(event: event)
    }
}
