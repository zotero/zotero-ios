//
//  LoginCompleteWsResponse.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 22/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LoginCompleteWsResponse: Decodable {
    private enum Keys: String, CodingKey {
        case topic
        case userId = "userID"
        case username
        case apiKey
    }

    let topic: String
    let userId: Int
    let username: String
    let apiKey: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        topic = try container.decode(String.self, forKey: .topic)
        userId = try container.decode(Int.self, forKey: .userId)
        username = try container.decode(String.self, forKey: .username)
        apiKey = try container.decode(String.self, forKey: .apiKey)
    }
}
