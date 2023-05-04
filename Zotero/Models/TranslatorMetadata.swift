//
//  TranslatorMetadata.swift
//  Zotero
//
//  Created by Michal Rentka on 23/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct TranslatorMetadatas {
    let metadatas: [TranslatorMetadata]
    let errors: [Error]
}

fileprivate struct EmptyDecodable: Decodable {}

extension TranslatorMetadatas: Decodable {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        var metadatas: [TranslatorMetadata] = []
        var errors: [Error] = []

        while !container.isAtEnd {
            do {
                let metadata = try container.decode(TranslatorMetadata.self)
                metadatas.append(metadata)
            } catch let error {
                _ = try container.decode(EmptyDecodable.self)
                errors.append(error)
            }
        }

        self.init(metadatas: metadatas, errors: errors)
    }
}

struct TranslatorMetadata {
    enum Error: Swift.Error {
        case incorrectDateFormat
    }

    let id: String
    let lastUpdated: Date
    let filename: String

    init(id: String, filename: String, rawLastUpdated: String) throws {
        guard let lastUpdated = Formatter.sqlFormat.date(from: rawLastUpdated) else {
            DDLogError("TranslatorMetadata: translator \(id) has incorrect date format - \"\(rawLastUpdated)\"")
            throw Error.incorrectDateFormat
        }

        self.id = id
        self.lastUpdated = lastUpdated
        self.filename = filename
    }
}

extension TranslatorMetadata: Decodable {
    private enum Keys: String, CodingKey {
        case id, lastUpdated, fileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let id = try container.decode(String.self, forKey: .id)
        let rawLastUpdated = try container.decode(String.self, forKey: .lastUpdated)
        let filename = try container.decode(String.self, forKey: .fileName)
        try self.init(id: id, filename: filename, rawLastUpdated: rawLastUpdated)
    }
}
