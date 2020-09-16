//
//  SchemaError.swift
//  Zotero
//
//  Created by Michal Rentka on 14/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Errors that can happen during schema validation.
/// - missingSchemaFields: Schema doesn't contain fields for given item type.
/// - unknownField: An unknown field was detected during parsing.
/// - missingField: Field that is mandatory is missing.
/// - invalidValue: Value for given field is invalid.
/// - embeddedImageMissingParent: An attachment with link mode `embedded_image` is missing a `parentItem`
enum SchemaError: Error {
    case missingSchemaFields(itemType: String)
    case unknownField(key: String, field: String)
    case missingField(key: String, field: String, itemType: String)
    case invalidValue(value: String, field: String, key: String)
    case embeddedImageMissingParent(key: String)
}
