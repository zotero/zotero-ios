//
//  SchemaController.swift
//  Zotero
//
//  Created by Michal Rentka on 08/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
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
    enum Error: Swift.Error {
        case etagMissing, cachedDataNotJson
    }

    private let apiClient: ApiClient
    private let fileStorage: FileStorage
    private let disposeBag: DisposeBag

    private(set) var itemSchemas: [String: ItemSchema] = [:]
    private(set) var locales: [String: SchemaLocale] = [:]
    private(set) var version: Int = 0
    private(set) var etag: String = ""

    init(apiClient: ApiClient, fileStorage: FileStorage) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.disposeBag = DisposeBag()

        if self.fileStorage.has(Files.schemaFile) {
            self.loadCachedData()
        } else {
            self.loadBundledData()
        }
    }

    func createFetchSchemaCompletable() -> Completable {
        return self.apiClient.send(request: SchemaRequest(etag: etag))
                             .do(onSuccess: { [weak self] (data, headers) in
                                 guard let `self` = self else { return }
                                 // Workaround for broken headers (stored in case-sensitive dictionary) on iOS
                                 let lowercase = headers["etag"] as? String
                                 let uppercase = headers["Etag"] as? String
                                 let etag = lowercase ?? uppercase ?? ""
                                 self.processResponse(data, etag: etag)
                             }, onError: { error in
                                 if error.isUnchangedError {
                                     return
                                 }

                                 // Don't need to do anything, we've got bundled schema, we've got auto retries
                                 // on backend errors, if everything fails we'll try again on app becoming active
                                 DDLogError("SchemaController: could not fetch schema - \(error)")
                             })
                             .asCompletable()
    }

    private func processResponse(_ data: Data, etag: String) {
        guard let jsonData = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else { return }
        self.storeSchema(from: jsonData, etag: etag)
        self.cache(json: jsonData, etag: etag)
    }

    private func cache(json: [String: Any], etag: String) {
        var newJson = json
        newJson["etag"] = etag

        do {
            let data = try JSONSerialization.data(withJSONObject: newJson, options: [])
            try self.fileStorage.write(data, to: Files.schemaFile, options: .atomicWrite)
        } catch let error {
            DDLogError("SchemaController: could not cache file - \(error)")
        }
    }

    private func loadCachedData() {
        do {
            let data = try self.fileStorage.read(Files.schemaFile)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)

            guard let json = jsonObject as? [String: Any] else { throw Error.cachedDataNotJson }
            guard let etag = json["etag"] as? String else { throw Error.etagMissing }

            self.storeSchema(from: json, etag: etag)
        } catch let error {
            DDLogError("SchemaController: could not load cached data - \(error)")
            self.loadBundledData()
        }
    }

    private func loadBundledData() {
        guard let schemaPath = Bundle.main.path(forResource: "schema", ofType: "json") else { return }
        let url = URL(fileURLWithPath: schemaPath)
        guard let schemaData = try? Data(contentsOf: url),
              let (etagPart, schemaPart) = self.chunks(from: schemaData, separator: "\n\n"),
              let etag = self.etag(from: etagPart),
              let json = try? JSONSerialization.jsonObject(with: schemaPart, options: .allowFragments) as? [String: Any] else { return }
        self.storeSchema(from: json, etag: etag)
    }

    private func storeSchema(from json: [String: Any], etag: String) {
        let schema = SchemaResponse(data: json)
        self.itemSchemas = schema.itemSchemas
        self.locales = schema.locales
        self.version = schema.version
        self.etag = etag
    }

    // MARK: - Helpers

    private func etag(from data: Data) -> String? {
        guard let headers = String(data: data, encoding: .utf8) else { return nil }

        for line in headers.split(separator: "\n") {
            guard line.contains("etag") else { continue }
            let separator = ":"
            let separatorChar = separator[separator.startIndex]
            guard let etag = line.split(separator: separatorChar).last.flatMap(String.init) else { continue }
            return etag.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        }

        return nil
    }

    private func chunks(from data: Data, separator: String) -> (Data, Data)? {
        guard let separatorData = separator.data(using: .utf8) else { return nil }

        let wholeRange = data.startIndex..<data.endIndex
        if let range = data.range(of: separatorData, options: [], in: wholeRange) {
            let first = data.subdata(in: data.startIndex..<range.lowerBound)
            let second = data.subdata(in: range.upperBound..<data.endIndex)
            return (first, second)
        }

        return nil
    }

    private var currentLocale: SchemaLocale? {
        let localeId = Locale.autoupdatingCurrent.identifier
        return self.locale(for: localeId)
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
        return self.fields(for: type)?.first(where: { $0.field == FieldKeys.title ||
                                                      $0.baseField == FieldKeys.title })?.field
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
