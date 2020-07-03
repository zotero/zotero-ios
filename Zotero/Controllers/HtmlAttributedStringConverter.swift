//
//  HtmlAttributedStringConverter.swift
//  Zotero
//
//  Created by Michal Rentka on 01/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class HtmlAttributedStringConverter {
    private struct Attribute {
        let type: StringAttribute
        let index: Int
        let isClosing: Bool
    }

    /// Converts attributed string to string with HTML tags for recognized attributes.
    /// - parameter attributedString: String to convert.
    /// - returns: String with HTML tags for recognized attributes.
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
            newString.insert(contentsOf: attribute.type.htmlTag(isClosing: attribute.isClosing),
                             at: newString.index(newString.startIndex, offsetBy: attribute.index))
        }
        return newString
    }

    /// Finds which attributes are currently opened (don't have closing attribute before them) in given array.
    /// - parameter attributesL Attributes array to check.
    /// - returns: Array of opened attributes.
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

    /// Converts string with HTML tags to attributed string. Supports only `b`, `i`, `sup` and `sub` HTML tags.
    /// - parameter comment: Comment to convert to attributed string
    /// - parameter baseFont: Base font from which attributes are derived.
    /// - returns: Attributed string with attributes assigned from recognized HTML tags.
    func convert(comment: String, baseFont: UIFont) -> NSAttributedString {
        var tagStart: Int?
        var deletedCharacters = 0
        var attributes: [Attribute] = []
        var strippedComment = comment

        // Strip HTML tags from original comment, find their positions and tag types.

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

            guard let type = StringAttribute(tag: (strippedTag ?? tag)) else {
                // If tag is not recognized, ignore it.
                tagStart = nil
                continue
            }

            // Tag recognized, store tag type and position.
            if strippedTag != nil {
                attributes.append(Attribute(type: type, index: (start - deletedCharacters), isClosing: true))
            } else {
                attributes.append(Attribute(type: type, index: (start - deletedCharacters), isClosing: false))
            }

            // Strip tag from original string.
            let tagLength = tag.count + 2 // + '<', '>'
            let strippedStart = strippedComment.index(strippedComment.startIndex, offsetBy: (start - deletedCharacters))
            let strippedEnd = strippedComment.index(strippedComment.startIndex, offsetBy: (index - deletedCharacters))
            strippedComment.removeSubrange(strippedStart...strippedEnd)

            deletedCharacters += tagLength
            tagStart = nil
        }

        // Create attributed string with parsed attributes.
        var activeAttributes: [StringAttribute] = []
        let attributedString = NSMutableAttributedString(string: strippedComment, attributes: [.font: baseFont])

        for (index, attribute) in attributes.enumerated() {
            guard index < attributes.count - 1 else { break }

            if attribute.isClosing {
                // If attribute was closed, remove it from active attributes.
                if let index = activeAttributes.firstIndex(of: attribute.type) {
                    activeAttributes.remove(at: index)
                }
            } else {
                // If attribute was opened, add it to active attributes.
                activeAttributes.append(attribute.type)
            }

            let nextAttribute = attributes[index + 1]
            let length = nextAttribute.index - attribute.index
            guard !activeAttributes.isEmpty && length > 0 else { continue }

            // If there are active attributes and there is a range, add them to attributed string.
            let nsStringAttributes = StringAttribute.nsStringAttributes(from: activeAttributes, baseFont: baseFont)
            attributedString.addAttributes(nsStringAttributes, range: NSMakeRange(attribute.index, length))
        }

        return attributedString
    }

    /// Strips closing character from html tag if available.
    /// - parameter tag: Tag to strip.
    /// - returns: Returns stripped tag if it has ending character. Otherwise returns `nil`.
    private func stripClosingCharacter(in tag: Substring) -> Substring? {
        if tag.first == "/" {
            return tag[tag.index(tag.startIndex, offsetBy: 1)..<tag.endIndex]
        }

        if tag.last == "/" {
            return tag[tag.startIndex..<tag.index(tag.endIndex, offsetBy: -1)]
        }

        return nil
    }
}
