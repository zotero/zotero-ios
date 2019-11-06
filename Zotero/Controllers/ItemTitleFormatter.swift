//
//  ItemTitleFormatter.swift
//  Zotero
//
//  Created by Michal Rentka on 06/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ItemTitleFormatter {
    static let nameCountLimit: Int = 4

    static func displayTitle(for item: RItem) -> String {
        switch item.rawType {
        case ItemTypes.letter:
            return letterDisplayTitle(from: item.baseTitle, creators: item.creators)
        case ItemTypes.interview:
            return interviewDisplayTitle(from: item.baseTitle, creators: item.creators)
        case ItemTypes.case:
            return caseDisplayTitle(from: item.baseTitle, fields: item.fields, creators: item.creators)
        default:
            return item.baseTitle
        }
    }

    private static func letterDisplayTitle(from baseTitle: String, creators: LinkingObjects<RCreator>) -> String {
        guard baseTitle.isEmpty else { return baseTitle }

        let names = separatedCreators(from: creators.filter("rawType == %@", "recipient"), limit: nameCountLimit)
        if names.isEmpty {
            return "[Letter]"
        }
        // TODO: - store localization string instead of raw string
        return "[Letter to \(names)]"
    }

    private static func interviewDisplayTitle(from baseTitle: String, creators: LinkingObjects<RCreator>) -> String {
        guard baseTitle.isEmpty else { return baseTitle }

        let names = separatedCreators(from: creators.filter("rawType == %@", "interviewer"), limit: nameCountLimit)
        if names.isEmpty {
            return "[Interview]"
        }
        // TODO: - store localization string instead of raw string
        return "[Interview by \(names)]"
    }

    private static func separatedCreators(from results: Results<RCreator>, limit: Int) -> String {
        let names = self.creatorNames(from: results, limit: limit)
        // TODO: - store localization string instead of raw string
        switch names.count {
        case 0:
            return ""
        case 1:
            return names[0]
        case 2:
            return names[0] + " and " + names[1]
        case 3:
            return names[0] + ", " + names[1] + " and " + names[2]
        default:
            return names[0] + " et al."
        }
    }

    private static func creatorNames(from results: Results<RCreator>, limit: Int) -> [String] {
        guard !results.isEmpty else { return [] }

        let sortedResults = results.sorted(byKeyPath: "orderId")

        var index = 0
        var names: [String] = []

        while (index < sortedResults.count) && (names.count < limit) {
            let name = sortedResults[index].summaryName
            index += 1

            if !name.isEmpty {
                names.append(name)
            }
        }

        return names
    }

    private static func caseDisplayTitle(from baseTitle: String, fields: LinkingObjects<RItemField>, creators: LinkingObjects<RCreator>) -> String {
        if !baseTitle.isEmpty {
            var title = baseTitle
            if let field = fields.filter("key = %@", FieldKeys.reporter).first, !field.value.isEmpty {
                title += " (\(field.value))"
            } else if let field = fields.filter("key = %@", FieldKeys.court).first, !field.value.isEmpty {
                title += " (\(field.value))"
            }
            return title
        }

        var parts: [String] = []

        if let field = fields.filter("key = %@", FieldKeys.court).first, !field.value.isEmpty {
            parts.append(field.value)
        }

        if let field = fields.filter("key = %@ or baseKey = %@", FieldKeys.date, FieldKeys.date).first, !field.value.isEmpty {
            parts.append(field.value)
        }

        if let creator = creators.filter("primary == true").sorted(byKeyPath: "orderId").first {
            let name = creator.summaryName
            if !name.isEmpty {
                parts.append(name)
            }
        }

        return "[" + parts.joined(separator: ", ") + "]"
    }
}
