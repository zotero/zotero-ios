//
//  NoteConverter.swift
//  Zotero
//
//  Created by Michal Rentka on 01/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class NoteConverter {
    private struct Attribute {
        let type: StringAttribute
        let index: Int
        let isClosing: Bool
    }

    private struct AttributedContent {
        let attributes: [StringAttribute]
        let startIndex: Int
        let length: Int
    }

    private struct HtmlTag {
        let type: StringAttribute
        let startIndex: Int
        let endIndex: Int
        let deletedCount: Int
        let closed: Bool

        func copy(closed: Bool) -> HtmlTag {
            return HtmlTag(type: self.type,
                       startIndex: self.startIndex,
                       endIndex: self.endIndex,
                       deletedCount: self.deletedCount,
                       closed: closed)
        }
    }

    func convert(attributedString: NSAttributedString) -> String {
        var attributes: [Attribute] = []

        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { nsAttributes, range, _ in
            // Currently active attributes
            let active = StringAttribute.attributes(from: nsAttributes)
            // Opened attributes so far
            let opened = self.openedAttributes(from: attributes)
            // Close opened attributes if they are not active anymore
            for openedAttribute in opened {
                if !active.contains(openedAttribute) {
                    attributes.insert(Attribute(type: openedAttribute, index: range.location, isClosing: true), at: 0)
                }
            }
            // Open new attributes
            for activeAttribute in active {
                if !opened.contains(activeAttribute) {
                    attributes.insert(Attribute(type: activeAttribute, index: range.location, isClosing: false), at: 0)
                }
            }
        }

        // Close remaining attributes
        for openedAttribute in self.openedAttributes(from: attributes) {
            attributes.insert(Attribute(type: openedAttribute, index: attributedString.length, isClosing: true), at: 0)
        }

        // Generate new string with html tags
        var newString = attributedString.string
        for attribute in attributes {
            newString.insert(contentsOf: self.htmlTag(from: attribute.type, isClosing: attribute.isClosing),
                             at: newString.index(newString.startIndex, offsetBy: attribute.index))
        }
        return newString
    }

    private func openedAttributes(from attributes: [Attribute]) -> [StringAttribute] {
        let allCount = StringAttribute.allCases.count
        var opened: [StringAttribute] = []
        var closed: [StringAttribute] = []

        for attribute in attributes {
            if attribute.isClosing {
                closed.append(attribute.type)
            } else if !closed.contains(attribute.type) {
                opened.append(attribute.type)
            }

            if (opened.count + closed.count) == allCount {
                break
            }
        }

        return opened
    }

    func convert(comment: String, baseFont: UIFont) -> NSAttributedString {
        var tagStart: Int?
        var deletedCharacters = 0
        var tags: [HtmlTag] = []
        var attributes: [Attribute] = []

        // Find tags and attributed content

        for (index, character) in comment.enumerated() {
            if character == "<" {
                tagStart = index
                continue
            }

            guard character == ">", let start = tagStart else { continue }

            let tagStartIndex = comment.index(comment.startIndex, offsetBy: (start + 1))
            let tagEndIndex = comment.index(comment.startIndex, offsetBy: index)
            let tag = comment[tagStartIndex..<tagEndIndex]
            let strippedTag = self.stripClosingCharacter(in: tag)

            guard let type = self.attributeType(from: (strippedTag ?? tag)) else {
                // If tag is not recognized, ignore
                tagStart = nil
                continue
            }

            guard strippedTag != nil else {
                // Opening tag
                tags.insert(HtmlTag(type: type, startIndex: start, endIndex: index, deletedCount: deletedCharacters, closed: false), at: 0)
                deletedCharacters += tag.count + 2 // + '<', '>'
                tagStart = nil
                continue
            }

            // Closing tag

            guard let openingTagIndex = tags.firstIndex(where: { !$0.closed && $0.type == type }) else {
                // If opening tag is not found, ignore closing tag
                tagStart = nil
                continue
            }

            let openingTag = tags[openingTagIndex].copy(closed: true)
            let closingTag = HtmlTag(type: type, startIndex: start, endIndex: index, deletedCount: deletedCharacters, closed: true)

            tags[openingTagIndex] = openingTag
            tags.insert(closingTag, at: 0)

            attributes.append(Attribute(type: type, index: (openingTag.startIndex - openingTag.deletedCount), isClosing: false))
            attributes.append(Attribute(type: type, index: (closingTag.startIndex - deletedCharacters), isClosing: true))

            deletedCharacters += tag.count + 2 // + '<', '>'
            tagStart = nil
        }

        // Strip tags from comment
        var strippedComment = comment
        for tag in tags {
            let start = strippedComment.index(strippedComment.startIndex, offsetBy: tag.startIndex)
            let end = strippedComment.index(strippedComment.startIndex, offsetBy: tag.endIndex)
            strippedComment.removeSubrange(start...end)
        }

        attributes.sort(by: { $0.index < $1.index })

        // Split overlaying ranges into unique ranges with multiple attribute kinds
        var splitRanges: [AttributedContent] = []
        var activeAttributes: [StringAttribute] = []

        for (index, attribute) in attributes.enumerated() {
            guard index < attributes.count - 1 else { break }

            if attribute.isClosing {
                // If attribute was closed, remove it from active attributes
                if let index = activeAttributes.firstIndex(of: attribute.type) {
                    activeAttributes.remove(at: index)
                }
            } else {
                // If attribute was opened, add it to active attributes
                activeAttributes.append(attribute.type)
            }

            let nextAttribute = attributes[index + 1]

            if attribute.index <= nextAttribute.index && !activeAttributes.isEmpty {
                let length = nextAttribute.index - attribute.index
                guard length > 0 else { continue }
                splitRanges.append(AttributedContent(attributes: activeAttributes, startIndex: attribute.index, length: length))
            }
        }

        // Create mutable attributed string, apply attributed content
        let attributedString = NSMutableAttributedString(string: strippedComment, attributes: [.font: baseFont])
        for content in splitRanges {
            let nsStringAttributes = StringAttribute.nsStringAttributes(from: content.attributes, baseFont: baseFont)
            attributedString.addAttributes(nsStringAttributes, range: NSMakeRange(content.startIndex, content.length))
        }

        return attributedString
    }

    private func stripClosingCharacter(in tag: Substring) -> Substring? {
        if tag.first == "/" {
            return tag[tag.index(tag.startIndex, offsetBy: 1)..<tag.endIndex]
        }

        if tag.last == "/" {
            return tag[tag.startIndex..<tag.index(tag.endIndex, offsetBy: -1)]
        }

        return nil
    }

    private func attributeType(from tag: Substring) -> StringAttribute? {
        switch tag {
        case "b":
            return .bold
        case "i":
            return .italic
        case "sup":
            return .superscript
        case "sub":
            return .subscript
        default:
            return nil
        }
    }

    private func htmlTag(from attributeType: StringAttribute, isClosing: Bool) -> String {
        let tag: String
        switch attributeType {
        case .bold:
            tag = "b"
        case .italic:
            tag = "i"
        case .subscript:
            tag = "sub"
        case .superscript:
            tag = "sup"
        }
        return "<\(isClosing ? "/" : "")\(tag)>"
    }
}
