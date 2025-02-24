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

    init(json: Any, keys: [String?]) throws {
        guard let dictionary = json as? [String: Any] else {
            throw Parsing.Error.notDictionary
        }

        self.successful = (dictionary["success"] as? [String: String]) ?? [:]
        self.successfulJsonObjects = (dictionary["successful"] as? [String: [String: Any]]) ?? [:]
        self.unchanged = (dictionary["unchanged"] as? [String: String]) ?? [:]
        let failed = (dictionary["failed"] as? [String: [String: Any]]) ?? [:]
        self.failed = failed.map({ key, value in
            let key = Int(key).flatMap({ idx -> String? in
                guard idx < keys.count else { return nil }
                return keys[idx]
            })
            return FailedUpdateResponse(data: value, key: key)
        })
     }
}

struct FailedUpdateResponse {
    let key: String?
    let code: Int
    let message: String

    init(data: [String: Any], key: String?) {
        self.key = key ?? (data["key"] as? String)
        self.code = (data["code"] as? Int) ?? 0
        self.message = (data["message"] as? String) ?? ""
    }
}
