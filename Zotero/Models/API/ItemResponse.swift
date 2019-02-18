//
//  ItemResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import DictionaryDecoder

enum ItemResponseError: Error {
    case notArray
    case missingKey(String)
    case unknownType(String)
}

struct ItemResponse {
    enum ItemType: String {
        case artwork
        case attachment
        case audioRecording
        case book
        case bookSection
        case bill
        case blogPost
        case `case`
        case computerProgram
        case conferencePaper
        case dictionaryEntry
        case document
        case email
        case encyclopediaArticle
        case film
        case forumPost
        case hearing
        case instantMessage
        case interview
        case journalArticle
        case letter
        case magazineArticle
        case map
        case manuscript
        case note
        case newspaperArticle
        case patent
        case podcast
        case presentation
        case radioBroadcast
        case report
        case statute
        case thesis
        case tvBroadcast
        case videoRecording
        case webpage
    }

    let type: ItemType
    let key: String
    let library: LibraryResponse
    let parentKey: String?
    let collectionKeys: Set<String>
    let links: LinksResponse
    let isTrash: Bool
    let version: Int
    let fields: [String: String]
    private static var notFieldKeys: Set<String> = {
        return ["creators", "itemType", "version", "key", "tags",
                "collections", "relations", "dateAdded", "dateModified"]
    }()

    init(response: [String: Any]) throws {
        let data: [String: Any] = try ItemResponse.parse(key: "data", from: response)
        let rawType: String = try ItemResponse.parse(key: "itemType", from: data)
        guard let type = ItemType(rawValue: rawType) else {
            throw ZoteroApiError.jsonDecoding(ItemResponseError.unknownType(rawType))
        }

        self.type = type
        self.key = try ItemResponse.parse(key: "key", from: response)
        self.version = try ItemResponse.parse(key: "version", from: response)
        let collections = data["collections"] as? [String]
        self.collectionKeys = collections.flatMap(Set.init) ?? []
        self.parentKey = data["parentItem"] as? String

        let deleted = data["deleted"] as? Int
        self.isTrash = deleted == 1

        let libraryData: [String: Any] = try ItemResponse.parse(key: "library", from: response)
        print("--- STUFF ---")
        print(libraryData)
        self.library = try DictionaryDecoder().decode(LibraryResponse.self, from: libraryData)
        let linksData: [String: Any] = try ItemResponse.parse(key: "links", from: response)
        NSLog("LINKS: \(linksData)")
        self.links = try DictionaryDecoder().decode(LinksResponse.self, from: linksData)

        let excludedKeys = ItemResponse.notFieldKeys
        var fields: [String: String] = [:]
        data.forEach { data in
            if !excludedKeys.contains(data.key) {
                fields[data.key] = data.value as? String
            }
        }
        self.fields = fields
    }

    static func decode(response: Any) throws -> [ItemResponse] {
        guard let array = response as? [[String: Any]] else {
            throw ZoteroApiError.jsonDecoding(ItemResponseError.notArray)
        }
        return try array.map({ try ItemResponse(response: $0) })
    }

    private static func parse<T>(key: String, from data: [String: Any]) throws -> T {
        guard let parsed = data[key] as? T else {
            throw ZoteroApiError.jsonDecoding(ItemResponseError.missingKey(key))
        }
        return parsed
    }
}

//extension ItemResponse: Decodable {
//    private enum Keys: String, CodingKey {
//        case key, version, library, links, data
//    }
//
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: ItemResponse.Keys.self)
//        let key = try container.decode(String.self, forKey: .key)
//        let library = try container.decode(LibraryResponse.self, forKey: .library)
//        let links = try container.decode(LinksResponse.self, forKey: .links)
//        let data = try container.decode(ItemResponse.Data.self, forKey: .data)
//        let version = try container.decode(Int.self, forKey: .version)
//        self.init(key: key, library: library, links: links, data: data, version: version)
//    }
//}
//
//extension ItemResponse.Data: Decodable {
//    private enum Keys: String, CodingKey {
//        case itemType, parentItem, collections, deleted, title,
//             caseName, subject, nameOfAct, note
//    }
//
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: ItemResponse.Data.Keys.self)
//        let rawType = try container.decode(String.self, forKey: .itemType)
//
//
//        guard let type = ItemResponse.Data.DataType(rawValue: rawType) else {
//            throw ZoteroApiError.unknownItemType(rawType)
//        }
//
//        let parentItem = try container.decodeIfPresent(String.self, forKey: .parentItem)
//        let collections = try container.decodeIfPresent([String].self, forKey: .collections)
//        let deleted = try container.decodeIfPresent(Int.self, forKey: .deleted)
//        let title = try container.decodeIfPresent(String.self, forKey: .title)
//        let caseName = try container.decodeIfPresent(String.self, forKey: .caseName)
//        let subject = try container.decodeIfPresent(String.self, forKey: .subject)
//        let nameOfAct = try container.decodeIfPresent(String.self, forKey: .nameOfAct)
//        let note = try container.decodeIfPresent(String.self, forKey: .note)
//
//        self.init(type: type, title: title, caseName: caseName, subject: subject, nameOfAct: nameOfAct, note: note,
//                  parentItem: parentItem, collections: collections.map(Set.init), isTrash: (deleted == 1))
//    }
//}
