//
//  HtmlEpubAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 28.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct HtmlEpubAnnotation: Hashable, Equatable {
    let key: String
    let type: AnnotationType
    let pageLabel: String
    let position: [String: Any]
    let author: String
    let isAuthor: Bool
    let color: String
    let comment: String
    let text: String?
    let sortIndex: String
    let dateModified: Date
    let dateCreated: Date
    let tags: [Tag]

    static func == (lhs: HtmlEpubAnnotation, rhs: HtmlEpubAnnotation) -> Bool {
        func compare(lhsPosition: [String: Any], rhsPosition: [String: Any]) -> Bool {
            for (lKey, lValue) in lhsPosition {
                guard let rValue = rhsPosition[lKey] else { return false }

                if let lValue = lValue as? String, let rValue = rValue as? String, lValue != rValue {
                    return false
                }
                // These values should be mostly strings, in the worst case numbers or simple dictionaries, so comparing them based on their string value should be fine.
                if "\(lValue)" != "\(rValue)" {
                    return false
                }
            }
            return true
        }
        return lhs.key == rhs.key &&
            lhs.type == rhs.type &&
            lhs.pageLabel == rhs.pageLabel &&
            lhs.author == rhs.author &&
            lhs.isAuthor == rhs.isAuthor &&
            lhs.color == rhs.color &&
            lhs.comment == rhs.comment &&
            lhs.text == rhs.text &&
            lhs.sortIndex == rhs.sortIndex &&
            lhs.dateModified == rhs.dateModified &&
            lhs.dateCreated == rhs.dateCreated &&
            compare(lhsPosition: lhs.position, rhsPosition: rhs.position) &&
            lhs.tags == rhs.tags
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(type)
        hasher.combine(pageLabel)
        hasher.combine(author)
        hasher.combine(isAuthor)
        hasher.combine(color)
        hasher.combine(comment)
        hasher.combine(text)
        hasher.combine(sortIndex)
        hasher.combine(dateModified)
        hasher.combine(dateCreated)
        hasher.combine(tags)

        for (key, value) in position {
            hasher.combine(key)
            if let value = value as? String {
                hasher.combine(value)
            } else {
                // These values should be mostly strings, in the worst case numbers or simple dictionaries, so hashing them based on their string value should be fine.
                hasher.combine("\(value)")
            }
        }
    }
}
