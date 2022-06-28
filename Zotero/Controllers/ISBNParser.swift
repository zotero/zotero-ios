//
//  ISBNParser.swift
//  Zotero
//
//  Created by Michal Rentka on 27.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class ISBNParser {
    private static let isbnRegex = try! NSRegularExpression(pattern: #"\b(?:97[89]\s*(?:\d\s*){9}\d|(?:\d\s*){9}[\dX])\b"#)

    /// Clean and return validated ISBNs.
    /// - param string: String to validate.
    /// - returns: Array of valid ISBNs
    static func isbns(from string: String) -> [String] {
        let cleanedString = string.replacingOccurrences(of: #"[\x2D\xAD\u2010-\u2015\u2043\u2212]+"#, with: "", options: .regularExpression, range: nil)
        let matches = self.isbnRegex.matches(in: cleanedString, range: NSRange(cleanedString.startIndex..., in: cleanedString))

        var isbns: [String] = []

        for match in matches {
            let startIndex = cleanedString.index(cleanedString.startIndex, offsetBy: match.range.lowerBound)
            let endIndex = cleanedString.index(cleanedString.startIndex, offsetBy: match.range.upperBound)
            let isbn = cleanedString[startIndex..<endIndex].replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression, range: nil)

            if isbn.count == 10 ? self.validate(isbn10: isbn) : self.validate(isbn13: isbn) {
                isbns.append(isbn)
            }
        }

        return isbns
    }

    private static func validate(isbn10 isbn: String) -> Bool {
        var sum = 0

        for idx in 0..<10 {
            let startIndex = isbn.index(isbn.startIndex, offsetBy: idx)
            let endIndex = isbn.index(isbn.startIndex, offsetBy: idx+1)
            let character = isbn[startIndex..<endIndex]

            if let intValue = Int(character) {
                sum += intValue * (10 - idx)
            } else if idx == 9 && character == "X" {
                sum += 10
            } else {
                sum = 1
                break
            }
        }

        return sum % 11 == 0
    }

    private static func validate(isbn13 isbn: String) -> Bool {
        var sum = 0

        for idx in 0..<13 {
            let startIndex = isbn.index(isbn.startIndex, offsetBy: idx)
            let endIndex = isbn.index(isbn.startIndex, offsetBy: idx+1)
            let character = isbn[startIndex..<endIndex]

            guard let intValue = Int(character) else {
                sum = 1
                break
            }

            if idx % 2 == 0 {
                sum += intValue
            } else {
                sum += intValue * 3
            }
        }

        return sum % 10 == 0
    }
}
