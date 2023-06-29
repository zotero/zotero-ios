//
//  JSONSerialization+Utils.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension JSONSerialization {
    static func dataWithRoundedDecimals(withJSONObject obj: Any, options opt: JSONSerialization.WritingOptions = []) throws -> Data {
        return try JSONSerialization.data(withJSONObject: self.convertDoubleToRoundedDecimal(in: obj), options: opt)
    }

    private static func convertDoubleToRoundedDecimal(in object: Any) -> Any {
        if let double = object as? Double {
            return Decimal(double).rounded(to: 3)
        }

        if let array = object as? [Any] {
            return array.map({ self.convertDoubleToRoundedDecimal(in: $0) })
        }

        if let dictionary = object as? [AnyHashable: Any] {
            var newObject = dictionary
            for (key, value) in dictionary {
                newObject[key] = self.convertDoubleToRoundedDecimal(in: value)
            }
            return newObject
        }

        return object
    }
}
