//
//  SchemaController.swift
//  Zotero
//
//  Created by Michal Rentka on 08/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

protocol SchemaDataSource: class {
    var itemTypes: [String] { get }

    func fields(for type: String) -> [FieldSchema]?
    func creators(for type: String) -> [CreatorSchema]?
    func localized(itemType: String) -> String?
    func localized(field: String) -> String?
    func localized(creator: String) -> String?
}

class SchemaController {
    static let abstractKey = "abstractNote"

    private let apiClient: ApiClient
    private let userDefaults: UserDefaults
    private let defaultsDateKey: String
    private let disposeBag: DisposeBag
    private let minReloadInterval: Double
    private let retryInterval: Double

    private(set) var itemSchemas: [String: ItemSchema] = [:]
    private(set) var locales: [String: SchemaLocale] = [:]
    private var isRetry = false

    init(apiClient: ApiClient, userDefaults: UserDefaults) {
        self.apiClient = apiClient
        self.userDefaults = userDefaults
        self.defaultsDateKey = "SchemaControllerLastFetchKey"
        self.disposeBag = DisposeBag()
        self.minReloadInterval = 86400 // 1 day
        self.retryInterval = 30 // seconds
    }

    func reloadSchemaIfNeeded() {
        if self.itemSchemas.isEmpty || self.locales.isEmpty {
            self.loadBundledData()
        }
        self.fetchSchemaIfNeeded()
    }

    private func fetchSchemaIfNeeded() {
        let lastFetchTimestamp = self.userDefaults.double(forKey: self.defaultsDateKey)

        if lastFetchTimestamp == 0 {
            self.fetchSchema()
            return
        }

        let lastFetchDate = Date(timeIntervalSince1970: lastFetchTimestamp)
        if Date().timeIntervalSince(lastFetchDate) >= self.minReloadInterval {
            self.fetchSchema()
        }
    }

    private func fetchSchema() {
        self.apiClient.send(dataRequest: SchemaRequest())
                      .observeOn(MainScheduler.instance)
                      .subscribe(onSuccess: { [weak self] response in
                          guard let `self` = self else { return }
                          self.reloadSchema(from: response.0)
                          self.userDefaults.set(Date().timeIntervalSince1970, forKey: self.defaultsDateKey)
                      }, onError: { [weak self] error in
                          guard let `self` = self else { return }
                          guard !self.isRetry else {
                              self.isRetry = false
                              return
                          }

                          self.isRetry = true
                          DispatchQueue.main.asyncAfter(deadline: (.now() + self.retryInterval)) { [weak self] in
                              self?.fetchSchemaIfNeeded()
                          }
                      })
                      .disposed(by: self.disposeBag)
    }

    private func loadBundledData() {
        guard let schemaPath = Bundle.main.path(forResource: "schema", ofType: "json") else { return }
        let url = URL(fileURLWithPath: schemaPath)
        guard let schemaData = try? Data(contentsOf: url) else { return }
        self.reloadSchema(from: schemaData)
    }

    private func reloadSchema(from data: Data) {
        guard let jsonData = try? JSONSerialization.jsonObject(with: data,
                                                               options: .allowFragments) as? [String: Any] else { return }
        let schema = SchemaResponse(data: jsonData)
        self.itemSchemas = schema.itemSchemas
        self.locales = schema.locales
    }
}

extension SchemaController: SchemaDataSource {
    var itemTypes: [String] {
        return Array(self.itemSchemas.keys)
    }

    func fields(for type: String) -> [FieldSchema]? {
        return self.itemSchemas[type]?.fields
    }

    func creators(for type: String) -> [CreatorSchema]? {
        return self.itemSchemas[type]?.creatorTypes
    }

    func localized(itemType: String) -> String? {
        let localeId = Locale.autoupdatingCurrent.identifier
        return self.locales[localeId]?.itemTypes[itemType]
    }

    func localized(field: String) -> String? {
        let localeId = Locale.autoupdatingCurrent.identifier
        return self.locales[localeId]?.fields[field]
    }

    func localized(creator: String) -> String? {
        let localeId = Locale.autoupdatingCurrent.identifier
        return self.locales[localeId]?.creatorTypes[creator]
    }
}
