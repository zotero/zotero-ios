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
    let userId: Int64
    let name: String
}

extension LoginResponse: Decodable {
    private enum Keys: String, CodingKey {
        case key = "key"
        case userId = "userID"
        case name = "username"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let key = try container.decode(String.self, forKey: .key)
        let userId = try container.decode(Int64.self, forKey: .userId)
        let name = try container.decode(String.self, forKey: .name)
        self.init(key: key, userId: userId, name: name)
    }
}
