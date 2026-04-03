//
//  LoginWsResponse.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 03/04/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LoginWsResponse: Decodable {
    enum Kind {
        case complete(topic: String, userId: Int, username: String, apiKey: String)
        case cancelled(topic: String)

        var topic: String {
            switch self {
            case .complete(let topic, _, _, _), .cancelled(let topic):
                return topic
            }
        }
    }

    private enum Keys: String, CodingKey {
        case event
        case topic
        case userId = "userID"
        case username
        case apiKey
    }

    let kind: Kind

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let eventString = try container.decode(String.self, forKey: .event)
        guard let event = WsResponse.Event(rawValue: eventString) else {
            throw WsResponse.Error.unknownEvent(eventString)
        }
        let topic = try container.decode(String.self, forKey: .topic)

        switch event {
        case .loginComplete:
            let userId = try container.decode(Int.self, forKey: .userId)
            let username = try container.decode(String.self, forKey: .username)
            let apiKey = try container.decode(String.self, forKey: .apiKey)
            kind = .complete(topic: topic, userId: userId, username: username, apiKey: apiKey)

        case .loginCancelled:
            kind = .cancelled(topic: topic)

        default:
            throw WsResponse.Error.unknownEvent(event.rawValue)
        }
    }
}
