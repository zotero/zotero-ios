//
//  StringAttributes.swift
//  Zotero
//
//  Created by Michal Rentka on 02/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum StringAttribute: CaseIterable {
    case bold
    case italic
    case superscript
    case `subscript`

    static let subscriptFontOffset: CGFloat = 0.2
    static let superscriptFontOffset: CGFloat = 0.4
    static let subOrSuperScriptFontSizeRatio: CGFloat = 0.75

    init?(tag: Substring) {
        switch tag {
        case "b":
            self = .bold
        case "i":
            self = .italic
        case "sup":
            self = .superscript
        case "sub":
            self = .subscript
        default:
            return nil
        }
    }

    func htmlTag(isClosing: Bool) -> String {
        let tag: String
        switch self {
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

    static func attributes(from nsStringAttributes: [NSAttributedString.Key: Any]) -> [StringAttribute] {
        var actions: [StringAttribute] = []

        if let traits = (nsStringAttributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits {
            if traits.contains(.traitBold) {
                actions.append(.bold)
            }
            if traits.contains(.traitItalic) {
                actions.append(.italic)
            }
        }

        if let baselineOffset = nsStringAttributes[.baselineOffset] as? CGFloat, baselineOffset != 0 {
            if baselineOffset > 0 {
                actions.append(.superscript)
            } else {
                actions.append(.subscript)
            }
        }

        return actions
    }

    static func nsStringAttributes(from attributes: [StringAttribute], baseFont: UIFont) -> [NSAttributedString.Key: Any] {
        guard !attributes.isEmpty else { return [:] }

        var allKeys: [NSAttributedString.Key: Any] = [:]
        var font = baseFont
        var traits: UIFontDescriptor.SymbolicTraits = []

        for attribute in attributes {
            switch attribute {
            case .bold:
                if !traits.contains(.traitBold) {
                    traits.insert(.traitBold)
                }

            case .italic:
                if !traits.contains(.traitItalic) {
                    traits.insert(.traitItalic)
                }

            case .subscript:
                let offset = font.pointSize * StringAttribute.subscriptFontOffset
                font = font.size(font.pointSize * StringAttribute.subOrSuperScriptFontSizeRatio)
                let baseline = (allKeys[.baselineOffset] as? CGFloat) ?? 0
                allKeys[.baselineOffset] = baseline - offset

            case .superscript:
                let offset = font.pointSize * StringAttribute.superscriptFontOffset
                font = font.size(font.pointSize * StringAttribute.subOrSuperScriptFontSizeRatio)
                let baseline = (allKeys[.baselineOffset] as? CGFloat) ?? 0
                allKeys[.baselineOffset] = baseline + offset
            }
        }

        if traits.isEmpty {
            allKeys[.font] = font
        } else {
            allKeys[.font] = font.withTraits(traits)
        }

        return allKeys
    }
}
