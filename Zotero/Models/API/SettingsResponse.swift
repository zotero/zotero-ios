//
//  SettingsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct SettingsResponse {
    let tagColors: TagColorsResponse?
    let pageIndices: PageIndicesResponse

    init(response: Any) throws {
        guard let json = response as? [String: Any] else {
            DDLogError("SettingsResponse: response not dictionary - \(response)")
            throw Parsing.Error.notDictionary
        }
        self.tagColors = try (json["tagColors"] as? [String: Any]).flatMap({ $0.isEmpty ? nil : $0 }).flatMap({ try TagColorsResponse(response: $0) })
        self.pageIndices = try PageIndicesResponse(response: json)
    }
}

struct PageIndicesResponse {
    let indices: [PageIndexResponse]

    init(response: [String: Any]) throws {
        self.indices = try response.compactMap({ try PageIndexResponse(key: $0.key, data: $0.value) })
    }
}

struct PageIndexResponse {
    let key: String
    let value: String
    let version: Int
    let libraryId: LibraryIdentifier

    init?(key: String, data: Any) throws {
        guard key.contains("lastPageIndex") else { return nil }
        guard let dictionary = data as? [String: Any] else {
            DDLogError("PageIndexResponse: response not dictionary for key \(key) - \(data)")
            throw Parsing.Error.notDictionary
        }

        let (key, libraryId) = try PageIndexResponse.parse(key: key)

        self.key = key
        self.value = try Self.parseValue(from: dictionary)
        self.version = try Parsing.parse(key: "version", from: dictionary, caller: Self.self)
        self.libraryId = libraryId
    }

    private static func parseValue(from dictionary: [String: Any]) throws -> String {
        // Value can be Int, Double or String, so we convert all values to String which can be stored in database
        if let value = dictionary["value"] as? Int {
            return "\(value)"
        } else if let value = dictionary["value"] as? Double {
            return "\(Decimal(value).rounded(to: 3))"
        } else if let value = dictionary["value"] as? String {
            return value
        }
        throw Parsing.Error.missingKey("value")
    }

    static func parse(key: String) throws -> (String, LibraryIdentifier) {
        let parts = key.split(separator: "_")
        guard parts.count == 3 else {
            DDLogError("PageIndexResponse: key is invalid format - \(key)")
            throw Parsing.Error.incompatibleValue(key)
        }

        let libraryPart = parts[1]
        let libraryId: LibraryIdentifier

        switch libraryPart[libraryPart.startIndex] {
        case "u":
            libraryId = .custom(.myLibrary)
        case "g":
            guard let groupId = Int(libraryPart[libraryPart.index(libraryPart.startIndex, offsetBy: 1)..<libraryPart.endIndex]) else {
                throw Parsing.Error.incompatibleValue("groupId=\(libraryPart)")
            }
            libraryId = .group(groupId)

        default:
            DDLogError("PageIndexResponse: key is invalid format - \(key)")
            throw Parsing.Error.incompatibleValue("libraryPart=\(libraryPart)")
        }

        return (String(parts[2]), libraryId)
    }
}

struct TagColorsResponse {
    let value: [TagColorResponse]

    init(response: [String: Any]) throws {
        let responses: [[String: Any]] = try Parsing.parse(key: "value", from: response, caller: Self.self)
        self.value = try responses.map({ try TagColorResponse(response: $0) })
    }
}

struct TagColorResponse {
    let name: String
    let color: String

    init(response: [String: Any]) throws {
        self.name = try Parsing.parse(key: "name", from: response, caller: Self.self)
        self.color = try Parsing.parse(key: "color", from: response, caller: Self.self)
    }
}
