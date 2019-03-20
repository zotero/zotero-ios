//
//  ItemFieldsController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

enum ItemFieldsControllerError: Error {
    case pathNotFound
}

class ItemFieldsController {
    let abstractKey = "abstractNote"
    private(set) var types: [String]
    private(set) var fields: [String: [String]]

    init() {
        do {
            let data = try ItemFieldsController.loadBundledData()
            self.types = data.0
            self.fields = data.1
        } catch let error {
            DDLogError("ItemFieldsController: couldn't load bundled data - \(error)")
            // Well, we'll have to wait for something from backend
            self.types = []
            self.fields = [:]
        }
    }

    private static func loadBundledData() throws -> ([String], [String: [String]]) {
        let bundle = Bundle.main
        guard let typesPath = bundle.path(forResource: "item_types", ofType: "txt") else {
            throw ItemFieldsControllerError.pathNotFound
        }

        let types = try String(contentsOfFile: typesPath).trimmingCharacters(in: .newlines)
                                                         .split(separator: ",")
                                                         .map(String.init)
        var allFields: [String: [String]] = [:]
        for type in types {
            guard let path = bundle.path(forResource: "item_fields_\(type)", ofType: "txt") else { continue }
            let fields = try String(contentsOfFile: path).trimmingCharacters(in: .newlines)
                                                         .split(separator: ",")
                                                         .map(String.init)
            allFields[type] = fields
        }
        return (types, allFields)
    }
}
