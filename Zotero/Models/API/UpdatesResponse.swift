//
//  UpdatesResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct UpdatesResponse {
    let successful: [String: String]
    let successfulJsonObjects: [String: [String: Any]]
    let unchanged: [String: String]
    let failed: [FailedUpdateResponse]

    init(json: Any) throws {
        guard let dictionary = json as? [String: Any] else {
            throw Parsing.Error.notDictionary
        }

        self.successful = (dictionary["success"] as? [String: String]) ?? [:]
        self.successfulJsonObjects = (dictionary["successful"] as? [String: [String: Any]]) ?? [:]
        self.unchanged = (dictionary["unchanged"] as? [String: String]) ?? [:]
        let failed = (dictionary["failed"] as? [String: [String: Any]]) ?? [:]
        self.failed = failed.values.map(FailedUpdateResponse.init)
     }
}

struct FailedUpdateResponse {
    let key: String?
    let code: Int
    let message: String

    init(data: [String: Any]) {
        self.key = data["key"] as? String
        self.code = (data["code"] as? Int) ?? 0
        self.message = (data["message"] as? String) ?? ""
    }
}
