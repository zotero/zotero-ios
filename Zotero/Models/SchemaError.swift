//
//  SchemaError.swift
//  Zotero
//
//  Created by Michal Rentka on 14/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Errors that can happen during schema validation.
/// - unknownField: An unknown field was detected during parsing.
/// - unknownItemType: Tried to parse unknown item type.
/// - missingFieldsForItemType: Schema doesn't contain fields for given item type.
enum SchemaError: Error {
    case unknownField(key: String, field: String)
    case unknownItemType(String)
    case missingFieldsForItemType(String)
}
