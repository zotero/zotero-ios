//
//  ItemResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct ItemResponse {
    enum Error: Swift.Error {
        case notArray
        case missingTranslatorAttachment
        case missingKey(String)
        case unknownType(String)
        case unknownField(String)
        case missingFieldsForType(String)
    }

    let rawType: String
    let key: String
    let library: LibraryResponse
    let parentKey: String?
    let collectionKeys: Set<String>
    let links: LinksResponse?
    let parsedDate: String?
    let isTrash: Bool
    let version: Int
    let dateModified: Date
    let dateAdded: Date
    let fields: [String: String]
    let tags: [TagResponse]
    let creators: [CreatorResponse]
    let relations: [String: String]
    let inPublications: Bool
    let createdBy: UserResponse?
    let lastModifiedBy: UserResponse?

    private static var notFieldKeys: Set<String> = {
        return ["creators", "itemType", "version", "key", "tags", "deleted",
                "collections", "relations", "dateAdded", "dateModified", "parentItem", "inPublications"]
    }()

    init(rawType: String, key: String, library: LibraryResponse, parentKey: String?, collectionKeys: Set<String>, links: LinksResponse?,
         parsedDate: String?, isTrash: Bool, version: Int, dateModified: Date, dateAdded: Date, fields: [String: String], tags: [TagResponse],
         creators: [CreatorResponse], relations: [String: String], createdBy: UserResponse?, lastModifiedBy: UserResponse?) {
        self.rawType = rawType
        self.key = key
        self.library = library
        self.parentKey = parentKey
        self.collectionKeys = collectionKeys
        self.links = links
        self.parsedDate = parsedDate
        self.isTrash = isTrash
        self.version = version
        self.dateModified = dateModified
        self.dateAdded = dateAdded
        self.fields = fields
        self.tags = tags
        self.creators = creators
        self.relations = relations
        self.inPublications = false
        self.createdBy = createdBy
        self.lastModifiedBy = lastModifiedBy
    }

    init(response: [String: Any], schemaController: SchemaController) throws {
        if response["data"] != nil {
            try self.init(apiResponse: response, schemaController: schemaController)
        } else {
            try self.init(translatorResponse: response, schemaController: schemaController)
        }
    }

    private init(apiResponse: [String: Any], schemaController: SchemaController) throws {
        let data: [String: Any] = try ItemResponse.parse(key: "data", from: apiResponse)
        let rawType: String = try ItemResponse.parse(key: "itemType", from: data)

        if !schemaController.itemTypes.contains(rawType) {
            throw Error.unknownType(rawType)
        }

        let decoder = JSONDecoder()
        let libraryDictionary: [String: Any] = try ItemResponse.parse(key: "library", from: apiResponse)
        let libraryData = try JSONSerialization.data(withJSONObject: libraryDictionary)
        let linksDictionary = apiResponse["links"] as? [String: Any]
        let linksData = try linksDictionary.flatMap { try JSONSerialization.data(withJSONObject: $0) }
        let tagsDictionaries = (data["tags"] as? [[String: Any]]) ?? []
        let tagsData = try tagsDictionaries.map({ try JSONSerialization.data(withJSONObject: $0) })
        let creatorsDictionary = (data["creators"] as? [[String: Any]]) ?? []
        let creatorsData = try creatorsDictionary.map({ try JSONSerialization.data(withJSONObject: $0) })
        let meta = apiResponse["meta"] as? [String: Any]
        let createdByData = try (meta?["createdByUser"] as? [String: Any]).map({ try JSONSerialization.data(withJSONObject: $0) })
        let lastModifiedByData = try (meta?["lastModifiedByUser"] as? [String: Any]).map({ try JSONSerialization.data(withJSONObject: $0) })

        self.rawType = rawType
        self.key = try ItemResponse.parse(key: "key", from: apiResponse)
        self.version = try ItemResponse.parse(key: "version", from: apiResponse)
        self.collectionKeys = (data["collections"] as? [String]).flatMap(Set.init) ?? []
        self.parentKey = data["parentItem"] as? String
        self.dateAdded = (data["dateAdded"] as? String).flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.dateModified = (data["dateModified"] as? String).flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.parsedDate = meta?["parsedDate"] as? String
        self.isTrash = (data["deleted"] as? Int) == 1
        self.library = try decoder.decode(LibraryResponse.self, from: libraryData)
        self.links = try linksData.flatMap { try decoder.decode(LinksResponse.self, from: $0) }
        self.tags = try tagsData.map({ try decoder.decode(TagResponse.self, from: $0) })
        self.creators = try creatorsData.map({ try decoder.decode(CreatorResponse.self, from: $0) })
        self.relations = (data["relations"] as? [String: String]) ?? [:]
        self.inPublications = (data["inPublications"] as? Bool) ?? false
        self.fields = try ItemResponse.parseFields(from: data, rawType: rawType, schemaController: schemaController)
        self.createdBy = try createdByData.flatMap { try decoder.decode(UserResponse.self, from: $0) }
        self.lastModifiedBy = try lastModifiedByData.flatMap { try decoder.decode(UserResponse.self, from: $0) }
    }

    private init(translatorResponse: [String: Any], schemaController: SchemaController) throws {
        let decoder = JSONDecoder()
        let rawType: String = try ItemResponse.parse(key: "itemType", from: translatorResponse)
        let accessDate = (translatorResponse["accessDate"] as? String).flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        let tagsDictionaries = (translatorResponse["tags"] as? [[String: Any]]) ?? []
        let tagsData = try tagsDictionaries.map({ try JSONSerialization.data(withJSONObject: $0) })
        let creatorsDictionary = (translatorResponse["creators"] as? [[String: Any]]) ?? []
        let creatorsData = try creatorsDictionary.map({ try JSONSerialization.data(withJSONObject: $0) })

        self.rawType = rawType
        self.key = KeyGenerator.newKey
        self.version = 0
        self.collectionKeys = []
        self.parentKey = nil
        self.dateAdded = accessDate
        self.dateModified = accessDate
        self.parsedDate = translatorResponse["date"] as? String
        self.isTrash = false
        // We create a dummy library here, it's not returned by translation server, it'll be picked in the share extension
        self.library = LibraryResponse(id: 0, name: "", type: "", links: nil)
        self.links = nil
        self.tags = try tagsData.map({ try decoder.decode(TagResponse.self, from: $0) })
        self.creators = try creatorsData.map({ try decoder.decode(CreatorResponse.self, from: $0) })
        self.relations = [:]
        self.inPublications = false
        // Translator returns some extra fields, which may not be recognized by schema, so we just ignore those
        self.fields = try ItemResponse.parseFields(from: translatorResponse,
                                                   rawType: rawType,
                                                   schemaController: schemaController,
                                                   ignoreUnknownFields: true)
        self.createdBy = nil
        self.lastModifiedBy = nil
    }

    func copy(libraryId: LibraryIdentifier, collectionKeys: Set<String>) -> ItemResponse {
        let library: LibraryResponse

        switch libraryId {
        case .custom:
            library = LibraryResponse(id: 0, name: "", type: "user", links: nil)
        case .group(let id):
            library = LibraryResponse(id: id, name: "", type: "group", links: nil)
        }

        return ItemResponse(rawType: self.rawType,
                            key: self.key,
                            library: library,
                            parentKey: self.parentKey,
                            collectionKeys: collectionKeys,
                            links: self.links,
                            parsedDate: self.parsedDate,
                            isTrash: self.isTrash,
                            version: self.version,
                            dateModified: self.dateModified,
                            dateAdded: self.dateAdded,
                            fields: self.fields,
                            tags: self.tags,
                            creators: self.creators,
                            relations: self.relations,
                            createdBy: self.createdBy,
                            lastModifiedBy: self.lastModifiedBy)
    }

    private static func parseFields(from data: [String: Any],
                                    rawType: String,
                                    schemaController: SchemaController,
                                    ignoreUnknownFields: Bool = false) throws -> [String: String] {
        let excludedKeys = ItemResponse.notFieldKeys
        var fields: [String: String] = [:]

        guard let schemaFields = schemaController.fields(for: rawType) else { throw Error.missingFieldsForType(rawType) }

        for object in data {
            guard !excludedKeys.contains(object.key) else { continue }

            var isKnownField = true

            // Check whether schema contains this key
            if !schemaFields.contains(where: { $0.field == object.key }) {
                if rawType == ItemTypes.attachment {
                    // Attachments don't have some fields that are returned by backend in schema,
                    // so we have to filter them out here manually.
                    if object.key != FieldKeys.contentType && object.key != FieldKeys.md5 &&
                       object.key != FieldKeys.mtime && object.key != FieldKeys.filename &&
                       object.key != FieldKeys.linkMode && object.key != "charset" &&
                       object.key != FieldKeys.note {
                        if ignoreUnknownFields {
                            isKnownField = false
                        } else {
                            throw Error.unknownField(object.key)
                        }
                    }
                } else {
                    // Note is not a field in schema but we consider it as one, since it can be returned with fields
                    // together with other data. So we filter it out as well and report all other keys.
                    if object.key != FieldKeys.note {
                        if ignoreUnknownFields {
                            isKnownField = false
                        } else {
                            throw Error.unknownField(object.key)
                        }
                    }
                }
            }

            if isKnownField {
                fields[object.key] = object.value as? String
            }
        }

        return fields
    }

    static func decode(response: Any, schemaController: SchemaController) throws -> ([ItemResponse], [[String: Any]], [Swift.Error]) {
        guard let array = response as? [[String: Any]] else {
            throw ZoteroApiError.jsonDecoding(Error.notArray)
        }

        var items: [ItemResponse] = []
        var objects: [[String: Any]] = []
        var errors: [Swift.Error] = []
        array.forEach { data in
            do {
                let item = try ItemResponse(response: data, schemaController: schemaController)
                items.append(item)
                objects.append(data)
            } catch let error {
                errors.append(error)
            }
        }
        return (items, objects, errors)
    }

    private static func parse<T>(key: String, from data: [String: Any]) throws -> T {
        guard let parsed = data[key] as? T else {
            throw ZoteroApiError.jsonDecoding(Error.missingKey(key))
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

struct UserResponse: Decodable {
    let id: Int
    let name: String
    let username: String
}
