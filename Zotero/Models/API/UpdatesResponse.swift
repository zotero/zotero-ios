//
//  UpdatesResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct UpdatesResponse {
    let successful: [String]
    let successfulJsonObjects: [Any]
    let unchanged: [String]
    let failed: [FailedUpdateResponse]

    init(json: Any) throws {
        guard let dictionary = json as? [String: Any] else {
            throw Parsing.Error.notDictionary
        }

        let successful = (dictionary["success"] as? [String: Any]) ?? [:]
        self.successful = Array(successful.keys)
        let successfulJsons = (dictionary["successful"] as? [String: Any]) ?? [:]
        self.successfulJsonObjects = Array(successfulJsons.values)
        let unchanged = (dictionary["unchanged"] as? [String: Any]) ?? [:]
        self.unchanged = Array(unchanged.keys)
        let failed = (dictionary["failed"] as? [String: [String: Any]]) ?? [:]
        self.failed = failed.values.map(FailedUpdateResponse.init)
     }
}

struct FailedUpdateResponse {
    let key: String?
    let code: Int
    let message: String

    init(data: [String: Any]) {
        if let key = data["key"] as? String {
            self.key = key
            self.code = (data["code"] as? Int) ?? 0
            self.message = (data["message"] as? String) ?? ""
        } else {
            self.key = nil
            self.code = -1
            self.message = "missing key"
        }
    }
}
