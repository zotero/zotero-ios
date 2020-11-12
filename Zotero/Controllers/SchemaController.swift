//
//  SchemaController.swift
//  Zotero
//
//  Created by Michal Rentka on 08/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

protocol SchemaDataSource: class {
    var itemTypes: [String] { get }

    func fields(for type: String) -> [FieldSchema]?
    func titleKey(for type: String) -> String?
    func baseKey(for type: String, field: String) -> String?
    func creators(for type: String) -> [CreatorSchema]?
    func creatorIsPrimary(_ creatorType: String, itemType: String) -> Bool
    func locale(for localeId: String) -> SchemaLocale?
    func localized(itemType: String) -> String?
    func localized(field: String) -> String?
    func localized(creator: String) -> String?
}

class SchemaController {
    private(set) var itemSchemas: [String: ItemSchema] = [:]
    private(set) var locales: [String: SchemaLocale] = [:]
    private(set) var version: Int = 0

    init() {
        self.loadBundledData()
    }

    private func loadBundledData() {
        guard let schemaPath = Bundle.main.path(forResource: "Bundled/schema", ofType: "json") else { return }
        let url = URL(fileURLWithPath: schemaPath)

        guard let schemaData = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: schemaData, options: .allowFragments) as? [String: Any] else { return }

        let schema = SchemaResponse(data: json)
        self.itemSchemas = schema.itemSchemas
        self.locales = schema.locales
        self.version = schema.version
    }
}

extension SchemaController: SchemaDataSource {
    var itemTypes: [String] {
        return Array(self.itemSchemas.keys)
    }

    func fields(for type: String) -> [FieldSchema]? {
        return self.itemSchemas[type]?.fields
    }

    func titleKey(for type: String) -> String? {
        return self.fields(for: type)?.first(where: { $0.field == FieldKeys.Item.title ||
                                                      $0.baseField == FieldKeys.Item.title })?.field
    }

    func baseKey(for type: String, field: String) -> String? {
        return self.fields(for: type)?.first(where: { $0.field == field })?.baseField
    }

    func creators(for type: String) -> [CreatorSchema]? {
        return self.itemSchemas[type]?.creatorTypes
    }

    func creatorIsPrimary(_ creatorType: String, itemType: String) -> Bool {
        return self.creators(for: itemType)?.first(where: { $0.creatorType == creatorType })?.primary ?? false
    }

    func locale(for localeId: String) -> SchemaLocale? {
        if let locale = self.locales[localeId] {
            return locale
        }

        let languagePart = localeId.split(separator: "_").first.flatMap(String.init) ?? localeId

        if let locale = self.locales.first(where: { $0.key.contains(languagePart) })?.value {
            return locale
        }

        return self.locales["en_US"]
    }

    private var currentLocale: SchemaLocale? {
        let localeId = Locale.autoupdatingCurrent.identifier
        return self.locale(for: localeId)
    }

    func localized(itemType: String) -> String? {
        return self.currentLocale?.itemTypes[itemType]
    }

    func localized(field: String) -> String? {
        return self.currentLocale?.fields[field]
    }

    func localized(creator: String) -> String? {
        return self.currentLocale?.creatorTypes[creator]
    }
}
