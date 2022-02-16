//
//  LoginResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LoginResponse {
    let key: String
    let userId: Int
    let name: String
    let displayName: String
}

extension LoginResponse: Decodable {
    private enum Keys: String, CodingKey {
        case key
        case userId = "userID"
        case name = "username"
        case displayName = "displayName"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let key = try container.decode(String.self, forKey: .key)
        let userId = try container.decode(Int.self, forKey: .userId)
        let name = try container.decode(String.self, forKey: .name)
        let displayName = try container.decode(String.self, forKey: .displayName)
        self.init(key: key, userId: userId, name: name, displayName: displayName)
    }
}
