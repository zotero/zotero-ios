//
//  Translator.swift
//  Zotero
//
//  Created by Michal Rentka on 26/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct Translator {
    let metadata: [String: Any]
    let code: String

    init(metadata: [String: Any], code: String) {
        self.metadata = metadata
        self.code = code
    }

    init(metadata: [String: String], code: String) {
        var updatedMetadata: [String: Any] = [:]
        for (key, value) in metadata {
            switch key {
            case "id":
                updatedMetadata["translatorID"] = Translator.value(from: value)
                
            case "type":
                updatedMetadata["translatorType"] = Translator.value(from: value)

            default:
                updatedMetadata[key] = Translator.value(from: value)
            }
        }
        self.metadata = updatedMetadata
        self.code = code
    }

    func withMetadata(key: String, value: String) -> Translator {
        var metadata = self.metadata
        switch key {
        case "id":
            metadata["translatorID"] = Translator.value(from: value)

        case "type":
            metadata["translatorType"] = Translator.value(from: value)

        default:
            metadata[key] = Translator.value(from: value)
        }
        return Translator(metadata: metadata, code: self.code)
    }

    func withCode(_ code: String) -> Translator {
        return Translator(metadata: self.metadata, code: code)
    }

    private static func value(from string: String) -> Any {
        if let intValue = Int(string) {
            return intValue
        }

        let lowercased = string.lowercased()
        if lowercased == "true" {
            return true
        }
        if lowercased == "false" {
            return false
        }

        if string.first == "{", let data = string.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }

        return string
    }
}
