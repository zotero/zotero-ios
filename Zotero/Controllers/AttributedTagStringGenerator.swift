//
//  AttributedTagStringGenerator.swift
//  Zotero
//
//  Created by Michal Rentka on 23.01.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift

struct AttributedTagStringGenerator {
    static func attributedString(fromUnsortedResults results: Results<RTag>, limit: Int? = nil) -> NSMutableAttributedString {
        let colored = results.filter("color != \"\"").sorted(byKeyPath: "name")
        let others = results.filter("color = \"\"").sorted(byKeyPath: "name")
        return self.attributedString(fromSortedColored: colored, others: others, limit: limit)
    }

    static func attributedString(fromSortedColored colored: Results<RTag>, others: Results<RTag>, limit: Int? = nil) -> NSMutableAttributedString {
        if let limit = limit {
            return self.attributedString(from: self.limitedTags(colored: colored, others: others, limit: limit))
        }
        let tags = Array(colored.map(Tag.init)) + Array(others.map(Tag.init))
        return self.attributedString(from: tags)
    }

    private static func limitedTags(colored: Results<RTag>, others: Results<RTag>, limit: Int) -> [Tag] {
        guard limit > 0 else { return [] }

        var tags: [Tag] = []

        for rTag in colored {
            tags.append(Tag(tag: rTag))

            if tags.count == limit {
                return tags
            }
        }

        for rTag in others {
            tags.append(Tag(tag: rTag))

            if tags.count == limit {
                return tags
            }
        }

        return tags
    }

    static func attributedString(from tags: [Tag], limit: Int? = nil) -> NSMutableAttributedString {
        let wholeString = NSMutableAttributedString()
        for (index, tag) in tags.enumerated() {
            if let limit = limit, index == limit {
                break
            }

            let tagInfo = TagColorGenerator.uiColor(for: tag.color)
            let color: UIColor
            switch tagInfo.style {
            case .border:
                // Overwrite default gray color
                color = UIColor(dynamicProvider: { traitCollection -> UIColor in
                    return traitCollection.userInterfaceStyle == .dark ? .white : .darkText
                })
            case .filled:
                color = tagInfo.color
            }
            let string = NSAttributedString(string: tag.name, attributes: [.foregroundColor: color])
            wholeString.append(string)
            if index != (tags.count - 1) {
                wholeString.append(NSAttributedString(string: ", "))
            }
        }
        return wholeString
    }
}
