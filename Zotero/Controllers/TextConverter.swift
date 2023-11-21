//
//  TextConverter.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 15/11/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct TextConverter {
    private static var hyphenAndNewlineExpression: NSRegularExpression? = {
        do {
            let pattern = #"[\x2D\u058A\u05BE\u1400\u1806\u2010-\u2015\u2E17\u2E1A\u2E3A\u2E3B\u301C\u3030\u30A0\uFE31\uFE32\uFE58\uFE63\uFF0D][\n\r]+"#
            return try NSRegularExpression(pattern: pattern)
        } catch let error {
            DDLogError("CopiedTextConverter: can't create hyphen and newline expression - \(error)")
            return nil
        }
    }()

    private static var newlineExpression: NSRegularExpression? = {
        do {
            let pattern = #"[\n\r]+"#
            return try NSRegularExpression(pattern: pattern)
        } catch let error {
            DDLogError("CopiedTextConverter: can't create newline expression - \(error)")
            return nil
        }
    }()

    private static var newlineOptionallySurroundedByWhitespaceExcludingEndingSentencesExpression: NSRegularExpression? = {
        do {
            let pattern = #"(?<!\.)\s*[\n\r]+\s*"#
            return try NSRegularExpression(pattern: pattern)
        } catch let error {
            DDLogError("CopiedTextConverter: can't create newline optionally surrounded by whitespace excluding ending sentences expression - \(error)")
            return nil
        }
    }()

    private static func replaceMatches(of expression: NSRegularExpression, with replacement: String, in string: String) -> String {
        let matches = expression.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
        var newString = string
        for match in matches.reversed() {
            guard let range = Range(match.range, in: newString) else { continue }
            newString = newString.replacingCharacters(in: range, with: replacement)
        }
        return newString
    }

    static func removeHyphenAndNewlinePairs(from string: String) -> String {
        guard let expression = hyphenAndNewlineExpression else { return string }
        return replaceMatches(of: expression, with: "", in: string)
    }

    static func replaceNewlineOptionallySurroundedByWhitespaceExcludingEndingSentencesExpressionWithSingleSpace(from string: String) -> String {
        guard let expression = newlineOptionallySurroundedByWhitespaceExcludingEndingSentencesExpression else { return string }
        return replaceMatches(of: expression, with: " ", in: string)
    }

    static func replaceNewlinesWithSingleSpace(from string: String) -> String {
        guard let expression = newlineExpression else { return string }
        return replaceMatches(of: expression, with: " ", in: string)
    }

    static func convertTextForAnnotation(from string: String) -> String {
        let stringWithoutHyphens = removeHyphenAndNewlinePairs(from: string)
        return replaceNewlineOptionallySurroundedByWhitespaceExcludingEndingSentencesExpressionWithSingleSpace(from: stringWithoutHyphens).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func convertTextForCopying(from string: String) -> String {
        let stringWithoutHyphens = removeHyphenAndNewlinePairs(from: string)
        return replaceNewlinesWithSingleSpace(from: stringWithoutHyphens)
    }
}
