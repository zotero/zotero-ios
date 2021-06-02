//
//  RegularExpression+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 02.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension NSTextCheckingResult {
    /// Creates Swift `Range` from result at given index in string.
    /// - parameter index: Index of matched range in this result.
    /// - parameter string: String from which this result originates.
    /// - returns: `Range` if index is in bounds, `nil` otherwise.
    func swiftRange(at index: Int, in string: String) -> Range<String.Index>? {
        return Range(self.range(at: index), in: string)
    }

    /// Creates substring from result at given index in string.
    /// - parameter index: Index of matched substring in this result.
    /// - parameter string: String from which this result originates.
    /// - returns: Substring if index is in bounds, `nil` otherwise.
    func substring(at index: Int, in string: String) -> Substring? {
        return self.swiftRange(at: index, in: string).flatMap({ string[$0] })
    }
}
