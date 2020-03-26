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

    func withMetadata(key: String, value: String) -> Translator {
        var metadata = self.metadata
        metadata[key] = value
        return Translator(metadata: metadata, code: self.code)
    }

    func withCode(_ code: String) -> Translator {
        return Translator(metadata: self.metadata, code: code)
    }
}
