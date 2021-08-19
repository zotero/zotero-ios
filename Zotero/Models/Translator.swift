//
//  Translator.swift
//  Zotero
//
//  Created by Michal Rentka on 26/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct Translator {
    let metadata: [String: String]
    let code: String

    init(metadata: [String: String], code: String) {
        var updatedMetadata = metadata
        if let id = metadata["id"] {
            updatedMetadata["translatorID"] = id
            updatedMetadata["id"] = nil
        }
        self.metadata = updatedMetadata
        self.code = code
    }

    func withMetadata(key: String, value: String) -> Translator {
        var metadata = self.metadata
        if key == "id" {
            metadata["translatorID"] = value
        } else {
            metadata[key] = value
        }
        return Translator(metadata: metadata, code: self.code)
    }

    func withCode(_ code: String) -> Translator {
        return Translator(metadata: self.metadata, code: code)
    }
}
