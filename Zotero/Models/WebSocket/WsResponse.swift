//
//  WsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 01.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct WsResponse {
    enum Event {
        case connected, subscriptionCreated, subscriptionDeleted
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
        let event = try WsResponse.event(from: eventStr)
        self.init(event: event)
    }

    private static func event(from string: String) throws -> Event {
        switch string {
        case "connected": return .connected
        case "subscriptionsCreated": return .subscriptionCreated
        case "subscriptionsDeleted": return .subscriptionDeleted
        default: throw WsResponse.Error.unknownEvent(string)
        }
    }
}
