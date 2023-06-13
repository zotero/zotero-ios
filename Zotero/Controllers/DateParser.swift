//
//  DateParser.swift
//  Zotero
//
//  Created by Michal Rentka on 27/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

private struct Part {
    enum Position {
        case beginning
        case ending
        case before(String)
        case after(String)
    }

    let value: String
    let position: Position
}

/// Rewritten from JS https://github.com/zotero/zotero/blob/master/chrome/content/zotero/xpcom/date.js.
/// Parser inspects unknown string and parses date while detecting the order of day/month/year if possible.
final class DateParser {
    private let enLocale: Locale
    private let partsPattern = #"^(.*?)\b([0-9]{1,4})(?:([\-\/\.\u5e74])([0-9]{1,2}))?(?:([\-\/\.\u6708])([0-9]{1,4}))?((?:\b|[^0-9]).*?)$"#
    private let yearPattern = #"^(.*?)\b((?:circa |around |about |c\.? ?)?[0-9]{1,4}(?: ?B\.? ?C\.?(?: ?E\.?)?| ?C\.? ?E\.?| ?A\.? ?D\.?)|[0-9]{3,4})\b(.*?)$"#
    private let monthPattern = #"^(.*)\b(months)[^ ]*(?: (.*)$|$)"#
    private let dayPattern = #"\b([0-9]{1,2})(?:suffixes)?\b(.*)"#

    private var calendar: Calendar
    private var lastLocaleId: String?
    private lazy var partsExpression: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: self.partsPattern)
        } catch let error {
            DDLogError("DateParser: can't create parts expression - \(error)")
            return nil
        }
    }()
    private lazy var yearExpression: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: self.yearPattern, options: .caseInsensitive)
        } catch let error {
            DDLogError("DateParser: can't create year expression - \(error)")
            return nil
        }
    }()
    private var months: [String] = []
    private var monthExpression: NSRegularExpression?
    private var dayExpression: NSRegularExpression?

    // MARK: - Lifecycle

    init() {
        self.calendar = Calendar(identifier: .gregorian)
        self.enLocale = Locale(identifier: "en_US")
    }

    // MARK: - Parsing

    /// Parses string to `ComponentDate` if it contains valid date.
    /// - parameter string: String to parse.
    /// - returns: `ComponentDate` with parsed date components and order.
    func parse(string: String) -> ComponentDate? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var day = 0
        var month = 0
        var year = 0
        var order = ""
        var parts: [Part] = []

        // Inspect the whole string. Parse possible values.
        self.parseParts(from: trimmed, day: &day, month: &month, year: &year, order: &order, parts: &parts)

        // Parse individual values from remaining parts
        if year == 0 {
            self.parseYear(from: &parts, year: &year, order: &order)
        }
        if month == 0 {
            self.parseMonth(from: &parts, month: &month, order: &order)
        }
        if day == 0 {
            self.parseDay(from: &parts, day: &day, order: &order)
        }

        // Return only valid zotero date
        if ((day > 0 && day <= 31) || (month > 0 && month <= 12) || year > 0) && !order.isEmpty {
            return ComponentDate(day: day, month: month, year: year, order: order)
        }
        return nil
    }

    /// Inspects string for possible date values based on valid separators and field positions.
    /// - parameter string: String to inspect.
    /// - parameter day: Day variable to update if found.
    /// - parameter month: Month variable to update if found.
    /// - parameter year: Year variable to update if found.
    /// - parameter order: Order variable to update if found.
    /// - parameter parts: Parts array which will be filled with remaining parts of original string.
    private func parseParts(from string: String, day: inout Int, month: inout Int, year: inout Int, order: inout String, parts: inout [Part]) {
        guard let match = self.partsExpression?.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) else { return }
        
        let preDatePart = match.substring(at: 1, in: string)
        let datePart1 = match.substring(at: 2, in: string)
        let separator1 = match.substring(at: 3, in: string)
        let datePart2 = match.substring(at: 4, in: string)
        let separator2 = match.substring(at: 5, in: string)
        let datePart3 = match.substring(at: 6, in: string)
        let postDatePart = match.substring(at: 7, in: string)

        let shouldCheck = ((separator1.isJsNegative || separator2.isJsNegative) || (separator1 == separator2) || (separator1 == "\u{5e74}" && separator2 == "\u{6708}")) &&            // require sane separators
                          ((datePart1?.isEmpty == false && datePart2?.isEmpty == false && datePart3?.isEmpty == false) || (preDatePart.isJsNegative && postDatePart.isJsNegative))     // require all parts are found

        if !shouldCheck { // or else this is the entire date field
            parts.append(Part(value: string, position: .ending))
            return
        }

        // Inspect individual date parts

        if datePart1?.count == 3 || datePart1?.count == 4 || separator1 == "\u{5e74}" {
            // ISO 8601 style date (big endian)
            day = datePart3.asInt
            month = datePart2.asInt
            year = self.year(from: datePart1)

            order = (year > 0 ? "y" : "") + (month > 0 ? "m" : "") + (day > 0 ? "d" : "")
        } else if datePart1?.isEmpty == false && datePart2.isJsNegative && datePart3?.isEmpty == false {
            // Only 2 parts found, assume month and year
            month = datePart1.asInt
            year = self.year(from: datePart3)
            order = (month > 0 ? "m" : "") + (year > 0 ? "y" : "")
        } else if datePart1?.isEmpty == false && datePart2.isJsNegative && datePart3.isJsNegative {
            // Only 1 part found, assume day/month
            let value = datePart1.asInt
            if value <= 12 {
                month = value
                order = "m"
            } else if value <= 31 {
                day = value
                order = "d"
            } else {
                year = value
                order = "y"
            }
        } else {
            // Local style date (middle or little endian)
            let localeParts = Locale.autoupdatingCurrent.identifier.split(separator: "_")
            let country = localeParts.count == 2 ? localeParts[1] : "US"
            switch country {
            case "US",  // The United States
                 "FM",  // The Federal States of Micronesia
                 "PW",  // Palau
                 "PH":  // The Philippines
                day = datePart2.asInt
                month = datePart1.asInt
                order = (month > 0 ? "m" : "") + (day > 0 ? "d" : "")

            default:
                day = datePart1.asInt
                month = datePart2.asInt
                order = (day > 0 ? "d" : "") + (month > 0 ? "m" : "")
            }

            year = self.year(from: datePart3)
            if year > 0 {
                order += "y"
            }
        }

        // Validate month and fix if possible
        if month > 12 {
            if day == 0 {
                // If day doesn't exist, just replace month with day
                day = month
                month = 0
                order = order.replacingOccurrences(of: "m", with: "d")
            } else if day <= 12 {
                // If day exists and can be a month, swap it with month
                let tmpDay = day
                day = month
                month = tmpDay

                if let dIdx = order.firstIndex(of: "d"), let mIdx = order.firstIndex(of: "m") {
                    var characters = Array(order)
                    characters.swapAt(order.distance(from: order.startIndex, to: dIdx),
                                      order.distance(from: order.startIndex, to: mIdx))
                    order = String(characters)
                }
            }
        }

        if day <= 31 && month <= 12 {
            // Day and month were either parsed correctly or are missing and will be parsed from remaining parts.
            if let value = preDatePart {
                parts.append(Part(value: String(value), position: .beginning))
            }
            if let value = postDatePart {
                parts.append(Part(value: String(value), position: .ending))
            }
        } else {
            // Parsed values were invalid, reset and try parsing individual values below.
            DDLogInfo("DateParser: partsExpression failed sanity check ('\(string)' -> \(day) | \(month) | \(year) | '\(order)')")
            day = 0
            month = 0
            year = 0
            order = ""
            // Append whole string, since it failed
            parts.append(Part(value: string, position: .ending))
        }
    }

    /// Tries parsing year from given parts. If found, updates `year` value and inserts "y" at appropriate index in `order`.
    /// - parameter parts: Remaining parts to inspect from previous parsing.
    /// - parameter year: Year variable to update if found.
    /// - parameter order: Order variable to update if found.
    private func parseYear(from parts: inout [Part], year: inout Int, order: inout String) {
        for (index, part) in parts.enumerated() {
            guard !part.value.isEmpty,
                  let match = self.yearExpression?.firstMatch(in: part.value, range: NSRange(part.value.startIndex..., in: part.value)) else { continue }

            year = match.substring(at: 2, in: part.value).asInt

            if year == 0 {
                continue
            }
            // Update order with year at current part
            self.update(&order, at: part, with: "y")
            // Update parts with new pre/post-part parts
            parts.remove(at: index)
            parts.insert(contentsOf: [Part(value: (match.substring(at: 1, in: part.value) ?? "").trimmingCharacters(in: .whitespaces),
                                           position: .beginning),
                                      Part(value: (match.substring(at: 3, in: part.value) ?? "").trimmingCharacters(in: .whitespaces),
                                           position: .ending)],
                         at: index)

            break
        }
    }

    /// Tries parsing month from given parts. If found, updates `month` value and inserts "m" at appropriate index in `order`.
    /// - parameter parts: Remaining parts to inspect from previous parsing.
    /// - parameter month: Month variable to update if found.
    /// - parameter order: Order variable to update if found.
    private func parseMonth(from parts: inout [Part], month: inout Int, order: inout String) {
        self.updateLocalizedExpressionsIfNeeded()

        for (index, part) in parts.enumerated() {
            guard !part.value.isEmpty,
                  let match = self.monthExpression?.firstMatch(in: part.value, range: NSRange(part.value.startIndex..., in: part.value)),
                  let monthString = match.substring(at: 2, in: part.value)?.lowercased() else { continue }
            guard let monthIndex = self.months.firstIndex(of: monthString) else { break }

            // Modulo 12 in case of multiple languages
            month = (monthIndex % 12) + 1
            // Update order with month at current part
            self.update(&order, at: part, with: "m")
            // Update parts with new pre/post-part parts
            parts.remove(at: index)
            parts.insert(contentsOf: [Part(value: (match.substring(at: 1, in: part.value) ?? "").trimmingCharacters(in: .whitespaces),
                                           position: .before("m")),
                                      Part(value: (match.substring(at: 3, in: part.value) ?? "").trimmingCharacters(in: .whitespaces),
                                           position: .after("m"))],
                         at: index)

            break
        }
    }

    /// Tries parsing day from given parts. If found, updates `day` value and inserts "d" at appropriate index in `order`.
    /// - parameter parts: Remaining parts to inspect from previous parsing.
    /// - parameter day: Day variable to update if found.
    /// - parameter order: Order variable to update if found.
    private func parseDay(from parts: inout [Part], day: inout Int, order: inout String) {
        self.updateLocalizedExpressionsIfNeeded()

        for (index, part) in parts.enumerated() {
            guard !part.value.isEmpty,
                  let match = self.dayExpression?.firstMatch(in: part.value, range: NSRange(part.value.startIndex..., in: part.value)) else { continue }

            day = (match.substring(at: 1, in: part.value)?.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789").inverted))
                                                          .flatMap({ Int($0) }) ?? 0

            // Validate day value, if invalid continue searching for valid day
            if day == 0 || day > 31 {
                continue
            }

            // Update order with day at current part
            self.update(&order, at: part, with: "d")
            // Update parts with new pre/post-part parts
            let location = match.range(at: 0).location
            var newPart: String = ""
            if let postPart = match.substring(at: 2, in: part.value) {
                newPart = String(postPart)
            }
            if location > 0 && location < part.value.count {
                newPart = String(part.value[part.value.startIndex..<part.value.index(part.value.startIndex, offsetBy: location)]) + newPart
            }
            parts[index] = Part(value: newPart.trimmingCharacters(in: .whitespaces), position: .ending)

            break
        }
    }

    /// Updates given order with new part at position of given part.
    /// - parameter order: Current order to update.
    /// - parameter part: Part that needs to be updated.
    /// - parameter newPart: Part which will be inserted at given position.
    private func update(_ order: inout String, at part: Part, with newPart: String) {
        if order.isEmpty {
            order = newPart
            return
        }

        switch part.position {
        case .beginning:
            order = newPart + order

        case .ending:
            order += newPart

        case .before(let string):
            order = order.replacingOccurrences(of: string, with: (newPart + string))

        case .after(let string):
            order = order.replacingOccurrences(of: string, with: (string + newPart))
        }
    }

    /// Calculates a year from given string. For full year strings an int value is returned.
    /// For shortened years a century is calculated and full year is returned.
    /// For example: "2020" -> 2020
    ///              "20"   -> 2020
    ///              "020"  -> 20
    ///              "0020" -> 20
    ///              "50"   -> 1950
    /// - parameter string: String to convert to year.
    /// - returns: A full year a `Int` value.
    private func year(from string: Substring?) -> Int {
        guard let string = string else { return 0 }

        let year = Int(string) ?? 0

        if string.count > 2 {
            return year
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        let twoDigitYear = currentYear % 100
        let century = currentYear - twoDigitYear

        if year <= twoDigitYear {
            // The date is from current century
            return century + year
        } else {
            // The date is from last century
            return century - 100 + year
        }
    }

    // MARK: - Regular expression helpers

    /// Updates months, month expression and day expression if locale changed.
    private func updateLocalizedExpressionsIfNeeded() {
        let locale = Locale.autoupdatingCurrent
        guard self.lastLocaleId != locale.identifier else { return }
        self.months = self.createMonths(for: locale)
        self.monthExpression = self.createMonthsExpression(months: self.months)
        self.dayExpression = self.createDayExpression()
        self.lastLocaleId = locale.identifier
    }

    /// Creates regular expression for months.
    /// - parameter months: Month names which should be searched for.
    /// - returns: Regular expression if successful, `nil` otherwise
    private func createMonthsExpression(months: [String]) -> NSRegularExpression? {
        let pattern = self.monthPattern.replacingOccurrences(of: "months", with: months.joined(separator: "|"))
        do {
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch let error {
            DDLogError("DateParser: can't create month expression - \(error)")
            return nil
        }
    }

    /// Creates array of localized month names and their short names.
    /// - parameter locale: Locale for which month names are created.
    /// - returns: Localized month names, month short names. English names are always included. Lowercased.
    private func createMonths(for locale: Locale) -> [String] {
        self.calendar.locale = locale

        let months = self.calendar.monthSymbols
        var allMonths = months + self.calendar.shortMonthSymbols

        self.calendar.locale = self.enLocale

        if months != self.calendar.monthSymbols {
            allMonths += (self.calendar.monthSymbols + self.calendar.shortMonthSymbols)
        }
        return allMonths.map({ $0.lowercased() })
    }

    /// Creates regular expression for days.
    /// - returns: Regular expression if successful, `nil` otherwise
    private func createDayExpression() -> NSRegularExpression? {
        let suffixes = L10n.daySuffixes.replacingOccurrences(of: ",", with: "|")
        let pattern = self.dayPattern.replacingOccurrences(of: "suffixes", with: suffixes)
        do {
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch let error {
            DDLogError("DateParser: can't create day expression - \(error)")
            return nil
        }
    }
}

extension Optional where Wrapped == Substring {
    /// `Bool` value same as JS alternative to `!variable` where `variable` is a `String` variable.
    /// Returns `false` if string exists and is not empty, `true` otherwise.
    fileprivate var isJsNegative: Bool {
        return self == nil || self?.isEmpty == true
    }

    /// Returns `Int` value of this `String` or 0 if `nil`.
    fileprivate var asInt: Int {
        return self.flatMap({ Int($0) }) ?? 0
    }
}
