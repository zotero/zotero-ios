//
//  ExportLocaleReader.swift
//  Zotero
//
//  Created by Michal Rentka on 14.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct ExportLocaleReader {
    enum Error: Swift.Error {
        case bundledFileMissing
    }

    static func loadIds() throws -> [String] {
        guard let localesUrl = Bundle.main.url(forResource: "locales", withExtension: "json", subdirectory: "Bundled/locales") else { throw Error.bundledFileMissing }

        let localesData = try Data(contentsOf: localesUrl)
        let localesJson = try JSONSerialization.jsonObject(with: localesData, options: [.allowFragments])

        guard let dictionary = localesJson as? [String: Any], let codes = dictionary["language-names"] as? [String: [String]] else { return [] }

        return Array(codes.keys)
    }

    static func load() throws -> [ExportLocale] {
        let locale = Locale.current
        return try self.loadIds().map({ ExportLocale(id: $0, name: (locale.localizedString(forIdentifier: $0) ?? $0)) })
                                 .sorted(by: {
                                     $0.name.compare($1.name, options: [.numeric], locale: locale) == .orderedAscending
                                 })
    }
}
