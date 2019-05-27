//
//  ItemResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

enum ItemResponseError: Error {
    case notArray
    case missingKey(String)
    case unknownType(String)
    case unknownField(String)
    case missingFieldsForType(String)
}

struct ItemResponse {
    let rawType: String
    let key: String
    let library: LibraryResponse
    let parentKey: String?
    let collectionKeys: Set<String>
    let links: LinksResponse?
    let creatorSummary: String?
    let parsedDate: String?
    let isTrash: Bool
    let version: Int
    let dateModified: Date
    let dateAdded: Date
    let fields: [String: String]
    let tags: [TagResponse]
    let creators: [CreatorResponse]
    let relations: [String: String]

    private static var notFieldKeys: Set<String> = {
        return ["creators", "itemType", "version", "key", "tags", "deleted",
                "collections", "relations", "dateAdded", "dateModified", "parentItem"]
    }()

    init(response: [String: Any], schemaController: SchemaController) throws {
        let data: [String: Any] = try ItemResponse.parse(key: "data", from: response)
        let rawType: String = try ItemResponse.parse(key: "itemType", from: data)

        if !schemaController.itemTypes.contains(rawType) {
            throw ItemResponseError.unknownType(rawType)
        }

        let excludedKeys = ItemResponse.notFieldKeys
        var fields: [String: String] = [:]

        if let schemaFields = schemaController.fields(for: rawType) {
            for object in data {
                guard !excludedKeys.contains(object.key) else { continue }
                // Note is not a field on backend but we consider it as one, since it can be returned with fields
                // together with other data
                if object.key != FieldKeys.note && !schemaFields.contains(where: { $0.field == object.key }) {
                    throw ItemResponseError.unknownField(object.key)
                }
                fields[object.key] = object.value as? String
            }
        } else {
            throw ItemResponseError.missingFieldsForType(rawType)
        }

        self.rawType = rawType
        self.key = try ItemResponse.parse(key: "key", from: response)
        self.version = try ItemResponse.parse(key: "version", from: response)
        let collections = data["collections"] as? [String]
        self.collectionKeys = collections.flatMap(Set.init) ?? []
        self.parentKey = data["parentItem"] as? String
        self.dateAdded = (data["dateAdded"] as? String).flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.dateModified = (data["dateModified"] as? String).flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()

        let meta = response["meta"] as? [String: Any]
        self.creatorSummary = meta?["creatorSummary"] as? String
        self.parsedDate = meta?["parsedDate"] as? String

        let deleted = data["deleted"] as? Int
        self.isTrash = deleted == 1

        let decoder = JSONDecoder()
        let libraryDictionary: [String: Any] = try ItemResponse.parse(key: "library", from: response)
        let libraryData = try JSONSerialization.data(withJSONObject: libraryDictionary)
        self.library = try decoder.decode(LibraryResponse.self, from: libraryData)
        let linksDictionary = response["links"] as? [String: Any]
        let linksData = try linksDictionary.flatMap { try JSONSerialization.data(withJSONObject: $0) }
        self.links = try linksData.flatMap { try decoder.decode(LinksResponse.self, from: $0) }
        let tagsDictionaries = (data["tags"] as? [[String: Any]]) ?? []
        let tagsData = try tagsDictionaries.map({ try JSONSerialization.data(withJSONObject: $0) })
        self.tags = try tagsData.map({ try decoder.decode(TagResponse.self, from: $0) })
        let creatorsDictionary = (data["creators"] as? [[String: Any]]) ?? []
        let creatorsData = try creatorsDictionary.map({ try JSONSerialization.data(withJSONObject: $0) })
        self.creators = try creatorsData.map({ try decoder.decode(CreatorResponse.self, from: $0) })
        self.relations = (data["relations"] as? [String: String]) ?? [:]
        self.fields = fields
    }

    static func decode(response: Any, schemaController: SchemaController) throws -> ([ItemResponse], [Error]) {
        guard let array = response as? [[String: Any]] else {
            throw ZoteroApiError.jsonDecoding(ItemResponseError.notArray)
        }

        var items: [ItemResponse] = []
        var errors: [Error] = []
        array.forEach { data in
            do {
                let item = try ItemResponse(response: data, schemaController: schemaController)
                items.append(item)
            } catch let error {
                errors.append(error)
            }
        }
        return (items, errors)
    }

    private static func parse<T>(key: String, from data: [String: Any]) throws -> T {
        guard let parsed = data[key] as? T else {
            throw ZoteroApiError.jsonDecoding(ItemResponseError.missingKey(key))
        }
        return parsed
    }
}

struct TagResponse: Decodable {
    let tag: String
}

struct CreatorResponse: Decodable {
    let creatorType: String
    let firstName: String?
    let lastName: String?
    let name: String?
}

struct RelationResponse: Decodable {

}
