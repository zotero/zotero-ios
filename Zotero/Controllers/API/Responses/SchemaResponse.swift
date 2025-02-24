//
//  SchemaResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SchemaResponse {
    let version: Int
    let itemSchemas: [String: ItemSchema]
    let locales: [String: SchemaLocale]

    init(data: [String: Any]) {
        var itemTypes: [String: ItemSchema] = [:]
        if let typeData = data["itemTypes"] as? [[String: Any]] {
            for data in typeData {
                guard let itemSchema = ItemSchema(data: data) else { continue }
                itemTypes[itemSchema.itemType] = itemSchema
            }
        }

        var locales: [String: SchemaLocale] = [:]
        if let localeData = data["locales"] as? [String: [String: Any]] {
            localeData.forEach { data in
                let fixedKey = data.key.replacingOccurrences(of: "-", with: "_")
                locales[fixedKey] = SchemaLocale(data: data.value)
            }
        }

        self.version = (data["version"] as? Int) ?? 0
        self.itemSchemas = itemTypes
        self.locales = locales
    }
}

struct ItemSchema {
    let itemType: String
    let fields: [FieldSchema]
    let creatorTypes: [CreatorSchema]

    init?(data: [String: Any]) {
        guard let itemType = data["itemType"] as? String else { return nil }
        self.itemType = itemType
        let fieldData = (data["fields"] as? [[String: Any]]) ?? []
        self.fields = fieldData.compactMap(FieldSchema.init)
        let creatorData = (data["creatorTypes"] as? [[String: Any]]) ?? []
        self.creatorTypes = creatorData.compactMap(CreatorSchema.init)
    }
}

struct FieldSchema {
    let field: String
    let baseField: String?

    init?(data: [String: Any]) {
        guard let field = data["field"] as? String else { return nil }
        self.field = field
        self.baseField = data["baseField"] as? String
    }
}

struct CreatorSchema {
    let creatorType: String
    let primary: Bool

    init?(data: [String: Any]) {
        guard let creatorType = data["creatorType"] as? String else { return nil }
        self.creatorType = creatorType
        self.primary = (data["primary"] as? Bool) ?? false
    }
}

struct SchemaLocale {
    let itemTypes: [String: String]
    let fields: [String: String]
    let creatorTypes: [String: String]

    init(data: [String: Any]) {
        self.itemTypes = (data["itemTypes"] as? [String: String]) ?? [:]
        self.fields = (data["fields"] as? [String: String]) ?? [:]
        self.creatorTypes = (data["creatorTypes"] as? [String: String]) ?? [:]
    }
}
