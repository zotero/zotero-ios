//
//  TranslatorMetadata.swift
//  Zotero
//
//  Created by Michal Rentka on 23/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

struct TranslatorMetadata {
    private static let formatter = createFormatter()

    let id: String
    let label: String
    let filename: String
    let lastUpdated: Date

    init?(id: String, data: [String: Any]) {
        guard let label = data["label"] as? String,
              let filename = data["fileName"] as? String,
              let lastUpdatedRawDate = data["lastUpdated"] as? String,
              let lastUpdated = TranslatorMetadata.formatter.date(from: lastUpdatedRawDate) else {
            DDLogError("TranslatorMetadata: can't parse data for \(id)")
            DDLogError("\(data)")
            return nil
        }

        self.id = id
        self.label = label
        self.filename = filename
        self.lastUpdated = lastUpdated
    }

    private static func createFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ss"
        return formatter
    }
}
