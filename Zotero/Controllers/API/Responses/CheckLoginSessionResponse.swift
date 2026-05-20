//
//  CheckLoginSessionResponse.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 21/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CheckLoginSessionResponse: Decodable {
    enum Status: Decodable {
        case pending
        case completed(apiKey: String, userId: Int, username: String)
        case cancelled

        private enum CodingKeys: String, CodingKey {
            case status
            case apiKey
            case userId = "userID"
            case username
        }

        private enum RawStatus: String, Decodable {
            case pending
            case completed
            case cancelled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            switch try container.decode(RawStatus.self, forKey: .status) {
            case .pending:
                self = .pending

            case .completed:
                self = .completed(
                    apiKey: try container.decode(String.self, forKey: .apiKey),
                    userId: try container.decode(Int.self, forKey: .userId),
                    username: try container.decode(String.self, forKey: .username)
                )

            case .cancelled:
                self = .cancelled
            }
        }
    }

    let status: Status

    init(from decoder: Decoder) throws {
        status = try Status(from: decoder)
    }
}
