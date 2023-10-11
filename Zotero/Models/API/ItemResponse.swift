//
//  ItemResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

/// This struct is used to connect some fields to their specific sub-fields data. Specifically this is used when parsing `annotationPosition` data. Each `key` in `annotationPosition` is assigned to
/// `key` and `baseKey` is set to `"annotationPosition"`. This way we can differentiate which fields are supposed to go to which sub-group of data.
struct KeyBaseKeyPair: Equatable, Hashable {
    let key: String
    let baseKey: String?
}

struct ItemResponse {
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
    let fields: [KeyBaseKeyPair: String]
    let tags: [TagResponse]
    let creators: [CreatorResponse]
    let relations: [String: Any]
    let inPublications: Bool
    let createdBy: UserResponse?
    let lastModifiedBy: UserResponse?
    let rects: [[Double]]?
    let paths: [[Double]]?

    init(
        rawType: String,
        key: String,
        library: LibraryResponse,
        parentKey: String?,
        collectionKeys: Set<String>,
        links: LinksResponse?,
        parsedDate: String?,
        isTrash: Bool,
        version: Int,
        dateModified: Date,
        dateAdded: Date,
        fields: [KeyBaseKeyPair: String],
        tags: [TagResponse],
        creators: [CreatorResponse],
        relations: [String: Any],
        createdBy: UserResponse?,
        lastModifiedBy: UserResponse?,
        rects: [[Double]]?,
        paths: [[Double]]?
    ) {
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
        self.rects = rects
        self.paths = paths
    }

    init(response: [String: Any], schemaController: SchemaController) throws {
        let data: [String: Any] = try response.apiGet(key: "data", caller: Self.self)
        let key: String = try response.apiGet(key: "key", caller: Self.self)
        let itemType: String = try data.apiGet(key: "itemType", caller: Self.self)

        if !schemaController.itemTypes.contains(itemType) {
            throw SchemaError.invalidValue(value: itemType, field: "itemType", key: key)
        }

        let library = try LibraryResponse(response: (try response.apiGet(key: "library", caller: Self.self)))
        let linksData = response["links"] as? [String: Any]
        let links = try linksData.flatMap { try LinksResponse(response: $0) }
        let meta = response["meta"] as? [String: Any]
        let parsedDate = meta?["parsedDate"] as? String
        let createdByData = meta?["createdByUser"] as? [String: Any]
        let createdBy = try createdByData.flatMap { try UserResponse(response: $0) }
        let lastModifiedByData = meta?["lastModifiedByUser"] as? [String: Any]
        let lastModifiedBy = try lastModifiedByData.flatMap { try UserResponse(response: $0) }
        let version: Int = try response.apiGet(key: "version", caller: Self.self)

        switch itemType {
        case ItemTypes.annotation:
            try self.init(
                key: key,
                library: library,
                links: links,
                parsedDate: parsedDate,
                createdBy: createdBy,
                lastModifiedBy: lastModifiedBy,
                version: version,
                annotationData: data,
                schemaController: schemaController
            )

        default:
            try self.init(
                key: key,
                rawType: itemType,
                library: library,
                links: links,
                parsedDate: parsedDate,
                createdBy: createdBy,
                lastModifiedBy: lastModifiedBy,
                version: version,
                data: data,
                schemaController: schemaController
            )
        }
    }

    // Init any item type except annotation
    private init(
        key: String,
        rawType: String,
        library: LibraryResponse,
        links: LinksResponse?,
        parsedDate: String?,
        createdBy: UserResponse?,
        lastModifiedBy: UserResponse?,
        version: Int,
        data: [String: Any],
        schemaController: SchemaController
    ) throws {
        let dateAdded = data["dateAdded"] as? String
        let dateModified = data["dateModified"] as? String
        let tags = (data["tags"] as? [[String: Any]]) ?? []
        let creators = (data["creators"] as? [[String: Any]]) ?? []

        self.rawType = rawType
        self.key = key
        self.version = version
        self.collectionKeys = (data["collections"] as? [String]).flatMap(Set.init) ?? []
        self.parentKey = data["parentItem"] as? String
        self.dateAdded = dateAdded.flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.dateModified = dateModified.flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.parsedDate = parsedDate
        self.isTrash = (data["deleted"] as? Bool) ?? ((data["deleted"] as? Int) == 1)
        self.library = library
        self.links = links
        self.tags = try tags.map({ try TagResponse(response: $0) })
        self.creators = try creators.map({ try CreatorResponse(response: $0) })
        self.relations = (data["relations"] as? [String: Any]) ?? [:]
        self.inPublications = (data["inPublications"] as? Bool) ?? ((data["inPublications"] as? Int) == 1)
        self.fields = try ItemResponse.parseFields(from: data, rawType: rawType, key: key, schemaController: schemaController).fields
        self.createdBy = createdBy
        self.lastModifiedBy = lastModifiedBy
        self.rects = nil
        self.paths = nil

        // Attachment with link mode "embedded_image" always needs a parent assigned
        if rawType == ItemTypes.attachment,
           let linkMode = self.fields[KeyBaseKeyPair(key: FieldKeys.Item.Attachment.linkMode, baseKey: nil)].flatMap({ LinkMode(rawValue: $0) }),
           linkMode == .embeddedImage && self.parentKey == nil {
            throw SchemaError.embeddedImageMissingParent(key: key, libraryId: library.libraryId ?? .custom(.myLibrary))
        }
    }

    // Init annotation
    private init(
        key: String,
        library: LibraryResponse,
        links: LinksResponse?,
        parsedDate: String?,
        createdBy: UserResponse?,
        lastModifiedBy: UserResponse?,
        version: Int,
        annotationData data: [String: Any],
        schemaController: SchemaController
    ) throws {
        let dateAdded = data["dateAdded"] as? String
        let dateModified = data["dateModified"] as? String
        let tags = (data["tags"] as? [[String: Any]]) ?? []

        let (fields, rects, paths) = try ItemResponse.parseFields(from: data, rawType: ItemTypes.annotation, key: key, schemaController: schemaController)

        self.rawType = ItemTypes.annotation
        self.key = key
        self.version = version
        self.collectionKeys = []
        self.parentKey = try data.apiGet(key: "parentItem", caller: Self.self)
        self.dateAdded = dateAdded.flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.dateModified = dateModified.flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.parsedDate = parsedDate
        self.isTrash = (data["deleted"] as? Bool) ?? ((data["deleted"] as? Int) == 1)
        self.library = library
        self.links = links
        self.tags = try tags.map({ try TagResponse(response: $0) })
        self.creators = []
        self.relations = [:]
        self.inPublications = false
        self.fields = fields
        self.createdBy = createdBy
        self.lastModifiedBy = lastModifiedBy
        self.rects = rects
        self.paths = paths
    }

    init(translatorResponse response: [String: Any], schemaController: SchemaController) throws {
        let key = KeyGenerator.newKey
        let rawType: String = try response.apiGet(key: "itemType", caller: Self.self)
        let accessDate = (response["accessDate"] as? String).flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        let tags = (response["tags"] as? [[String: Any]]) ?? []
        let creators = (response["creators"] as? [[String: Any]]) ?? []

        self.rawType = rawType
        self.key = key
        self.version = 0
        self.collectionKeys = []
        self.parentKey = nil
        self.dateAdded = accessDate
        self.dateModified = accessDate
        self.parsedDate = response["date"] as? String
        self.isTrash = false
        // We create a dummy library here, it's not returned by translation server, it'll be picked in the share extension
        self.library = LibraryResponse(id: 0, name: "", type: "", links: nil)
        self.links = nil
        self.tags = try tags.map({ try TagResponse(response: $0) })
        self.creators = try creators.map({ try CreatorResponse(response: $0) })
        self.relations = [:]
        self.inPublications = false
        // Translator returns some extra fields, which may not be recognized by schema, so we just ignore those
        self.fields = try ItemResponse.parseFields(from: response, rawType: rawType, key: key, schemaController: schemaController, ignoreUnknownFields: true).fields
        self.createdBy = nil
        self.lastModifiedBy = nil
        self.rects = nil
        self.paths = nil
    }

    func copy(libraryId: LibraryIdentifier, collectionKeys: Set<String>, tags: [TagResponse]) -> ItemResponse {
        return ItemResponse(
            rawType: self.rawType,
            key: self.key,
            library: LibraryResponse(libraryId: libraryId),
            parentKey: self.parentKey,
            collectionKeys: collectionKeys,
            links: self.links,
            parsedDate: self.parsedDate,
            isTrash: self.isTrash,
            version: self.version,
            dateModified: self.dateModified,
            dateAdded: self.dateAdded,
            fields: self.fields,
            tags: tags,
            creators: self.creators,
            relations: self.relations,
            createdBy: self.createdBy,
            lastModifiedBy: self.lastModifiedBy,
            rects: self.rects,
            paths: self.paths
        )
    }

    var copyWithAutomaticTags: ItemResponse {
        return ItemResponse(
            rawType: self.rawType,
            key: self.key,
            library: self.library,
            parentKey: self.parentKey,
            collectionKeys: self.collectionKeys,
            links: self.links,
            parsedDate: self.parsedDate,
            isTrash: self.isTrash,
            version: self.version,
            dateModified: self.dateModified,
            dateAdded: self.dateAdded,
            fields: self.fields,
            tags: self.tags.map({ $0.automaticCopy }),
            creators: self.creators,
            relations: self.relations,
            createdBy: self.createdBy,
            lastModifiedBy: self.lastModifiedBy,
            rects: self.rects,
            paths: self.paths
        )
    }

    /// Parses field values from item data for given type.
    /// - parameter data: Data to parse.
    /// - parameter rawType: Raw item type of parsed item.
    /// - parameter schemaController: Schema controller to check fields against schema.
    /// - parameter key: Key of item.
    /// - parameter ignoreUnknownFields: If set to `false`, when an unknown field is encountered during parsing, an exception `Error.unknownField` is thrown. Otherwise the field is silently ignored and parsing continues.
    /// - returns: Parsed dictionary of fields with their values.
    private static func parseFields(
        from data: [String: Any],
        rawType: String,
        key: String,
        schemaController: SchemaController,
        ignoreUnknownFields: Bool = false
    ) throws -> (fields: [KeyBaseKeyPair: String], rects: [[Double]]?, paths: [[Double]]?) {
        let excludedKeys = FieldKeys.Item.knownNonFieldKeys
        var fields: [KeyBaseKeyPair: String] = [:]
        var rects: [[Double]]?
        var paths: [[Double]]?

        guard let schemaFields = schemaController.fields(for: rawType) else { throw SchemaError.missingSchemaFields(itemType: rawType) }

        for object in data {
            guard !excludedKeys.contains(object.key) else { continue }

            if !self.isKnownField(object.key, in: schemaFields, itemType: rawType) {
                if ignoreUnknownFields {
                    continue
                }
                throw SchemaError.unknownField(key: key, field: object.key)
            }

            var value: String
            if let _value = object.value as? String {
                value = _value
            } else {
                value = "\(object.value)"
            }

            switch object.key {
            case FieldKeys.Item.Annotation.position:
                // Annotations have `annotationPosition` which is a JSON string, so the string needs to be decoded and stored as proper field values
                let (_rects, _paths) = try self.parsePositionFields(from: value, key: key, fields: &fields)
                rects = _rects
                paths = _paths

            case FieldKeys.Item.accessDate:
                if value == "CURRENT_TIMESTAMP" {
                    value = Formatter.iso8601.string(from: Date())
                }
                fields[KeyBaseKeyPair(key: object.key, baseKey: nil)] = value

            default:
                fields[KeyBaseKeyPair(key: object.key, baseKey: nil)] = value
            }
        }

        try self.validate(fields: fields, itemType: rawType, key: key, hasPaths: (paths != nil), hasRects: (rects != nil))

        return (fields, rects, paths)
    }

    private static func parsePositionFields(
        from encoded: String,
        key: String,
        fields: inout [KeyBaseKeyPair: String]
    ) throws -> (rects: [[Double]]?, paths: [[Double]]?) {
        guard let data = encoded.data(using: .utf8), let json = (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)) as? [String: Any] else {
            throw SchemaError.invalidValue(value: encoded, field: FieldKeys.Item.Annotation.position, key: key)
        }

        var rects: [[Double]]?
        var paths: [[Double]]?

        for object in json {
            switch object.key {
            case FieldKeys.Item.Annotation.Position.pageIndex:
                if (object.value as? Int) == nil {
                    throw SchemaError.invalidValue(value: "\(object.value)", field: FieldKeys.Item.Annotation.Position.pageIndex, key: key)
                }

            case FieldKeys.Item.Annotation.Position.lineWidth:
                if (object.value as? Double) == nil {
                    throw SchemaError.invalidValue(value: "\(object.value)", field: FieldKeys.Item.Annotation.Position.lineWidth, key: key)
                }

            case FieldKeys.Item.Annotation.Position.paths:
                guard let parsedPaths = object.value as? [[Double]], !parsedPaths.isEmpty && !parsedPaths.contains(where: { $0.count % 2 != 0 }) else {
                    throw SchemaError.invalidValue(value: "\(object.value)", field: FieldKeys.Item.Annotation.Position.paths, key: key)
                }
                paths = parsedPaths
                continue

            case FieldKeys.Item.Annotation.Position.rects:
                guard let parsedRects = object.value as? [[Double]], !parsedRects.isEmpty && !parsedRects.contains(where: { $0.count != 4 }) else {
                    throw SchemaError.invalidValue(value: "\(object.value)", field: FieldKeys.Item.Annotation.Position.rects, key: key)
                }
                rects = parsedRects
                continue

            default: break
            }

            let value: String
            if let _value = object.value as? String {
                value = _value
            } else if let _value = object.value as? Int {
                value = "\(_value)"
            } else if let _value = object.value as? Double {
                value = "\(_value.rounded(to: 3))"
            } else if let _value = object.value as? Bool {
                value = "\(_value)"
            } else if let data = try? JSONSerialization.dataWithRoundedDecimals(withJSONObject: object.value), let _value = String(data: data, encoding: .utf8) {
                // If `object.value` is not a basic type (string or number) convert it to JSON and store JSON string
                value = _value
            } else {
                value = "\(object.value)"
            }
            fields[KeyBaseKeyPair(key: object.key, baseKey: FieldKeys.Item.Annotation.position)] = value
        }

        return (rects, paths)
    }

    private static func validate(fields: [KeyBaseKeyPair: String], itemType: String, key: String, hasPaths: Bool, hasRects: Bool) throws {
        switch itemType {
        case ItemTypes.annotation:
            // `position` values are validated in `parsePositionFields(from:key:fields:)` where we have access to their original value, instead of just `String`.
            guard let rawType = fields[KeyBaseKeyPair(key: FieldKeys.Item.Annotation.type, baseKey: nil)] else {
                throw SchemaError.missingField(key: key, field: FieldKeys.Item.Annotation.type, itemType: itemType)
            }
            guard let type = AnnotationType(rawValue: rawType) else {
                throw SchemaError.invalidValue(value: rawType, field: FieldKeys.Item.Annotation.type, key: key)
            }

            let mandatoryFields = FieldKeys.Item.Annotation.mandatoryApiFields(for: type)
            for field in mandatoryFields {
                guard let value = fields[field] else {
                    throw SchemaError.missingField(key: key, field: field.key, itemType: itemType)
                }

                switch field.key {
                case FieldKeys.Item.Annotation.color:
                    if !value.starts(with: "#") {
                        throw SchemaError.invalidValue(value: value, field: field.key, key: key)
                    }

                default: break
                }
            }

        case ItemTypes.attachment:
            guard let rawLinkMode = fields[KeyBaseKeyPair(key: FieldKeys.Item.Attachment.linkMode, baseKey: nil)] else {
                throw SchemaError.missingField(key: key, field: FieldKeys.Item.Attachment.linkMode, itemType: itemType)
            }
            if LinkMode(rawValue: rawLinkMode) == nil {
                throw SchemaError.invalidValue(value: rawLinkMode, field: FieldKeys.Item.Attachment.linkMode, key: key)
            }

        default: return
        }
    }

    /// Checks whether given field is a known field for given item type.
    /// - parameter field: Field to check.
    /// - parameter schema: Schema for given item type.
    /// - parameter itemType: Raw item type of item.
    /// - returns: `true` if field is a known field for given item, `false` otherwise.
    private static func isKnownField(_ field: String, in schema: [FieldSchema], itemType: String) -> Bool {
        // Note is not a field stored in schema but we consider it as one, since it can be returned with fields together with other data.
        if field == FieldKeys.Item.note || schema.contains(where: { $0.field == field }) { return true }

        switch itemType {
        case ItemTypes.annotation:
            // Annotations don't have some fields that are returned by backend in schema, so we have to filter them out here manually.
            return FieldKeys.Item.Annotation.knownKeys.contains(field)

        case ItemTypes.attachment:
            // Attachments don't have some fields that are returned by backend in schema, so we have to filter them out here manually.
            return FieldKeys.Item.Attachment.knownKeys.contains(field)

        default:
            // Field not found in schema and is not a special case.
            return false
        }
    }
}

struct TagResponse {
    enum Error: Swift.Error {
        case unknownTagType
    }

    let tag: String
    let type: RTypedTag.Kind

    init(tag: String, type: RTypedTag.Kind) {
        self.tag = tag
        self.type = type
    }

    init(response: [String: Any]) throws {
        let rawType = (try? response.apiGet(key: "type", caller: Self.self)) ?? 0

        guard let type = RTypedTag.Kind(rawValue: rawType) else {
            throw Error.unknownTagType
        }

        self.tag = try response.apiGet(key: "tag", caller: Self.self)
        self.type = type
    }

    var automaticCopy: TagResponse {
        return TagResponse(tag: self.tag, type: RTypedTag.Kind.automatic)
    }
}

struct CreatorResponse {
    let creatorType: String
    let firstName: String?
    let lastName: String?
    let name: String?

    init(response: [String: Any]) throws {
        self.creatorType = try response.apiGet(key: "creatorType", caller: Self.self)
        self.firstName = response["firstName"] as? String
        self.lastName = response["lastName"] as? String
        self.name = response["name"] as? String
    }
}

struct RelationResponse {
}

struct UserResponse {
    let id: Int
    let name: String
    let username: String

    init(response: [String: Any]) throws {
        self.id = try response.apiGet(key: "id", caller: Self.self)
        self.name = try response.apiGet(key: "name", caller: Self.self)
        self.username = try response.apiGet(key: "username", caller: Self.self)
    }
}
