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
    case smallcaps

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

        case #"span style="font-variant:small-caps;""#, "span":
            self = .smallcaps

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

        case .smallcaps:
            tag = isClosing ? "span" : #"span style="font-variant:small-caps;""#
        }
        return "<\(isClosing ? "/" : "")\(tag)>"
    }

    static func attributes(from nsStringAttributes: [NSAttributedString.Key: Any]) -> [StringAttribute] {
        var actions: [StringAttribute] = []

        if let fontDescriptor = (nsStringAttributes[.font] as? UIFont)?.fontDescriptor {
            if fontDescriptor.symbolicTraits.contains(.traitBold) {
                actions.append(.bold)
            }
            if fontDescriptor.symbolicTraits.contains(.traitItalic) {
                actions.append(.italic)
            }
            if let settings = fontDescriptor.fontAttributes[UIFontDescriptor.AttributeName.featureSettings] as? [[UIFontDescriptor.FeatureKey: Int]], !settings.isEmpty {
                actions.append(.smallcaps)
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
        var descriptorAttributes: [UIFontDescriptor.AttributeName: Any] = [:]

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

            case .smallcaps:
                descriptorAttributes[.featureSettings] = [
                    [UIFontDescriptor.FeatureKey.featureIdentifier: kLowerCaseType, UIFontDescriptor.FeatureKey.typeIdentifier: kLowerCaseSmallCapsSelector],
                    [UIFontDescriptor.FeatureKey.featureIdentifier: kUpperCaseType, UIFontDescriptor.FeatureKey.typeIdentifier: kUpperCaseSmallCapsSelector]
                ]
            }
        }

        allKeys[.font] = font.with(traits: traits, attributes: descriptorAttributes)

        return allKeys
    }

    static func toggleSuperscript(in string: NSMutableAttributedString, range: NSRange, defaultFont: UIFont) {
        self.toggle(superscript: true, in: string, range: range, defaultFont: defaultFont)
    }

    static func toggleSubscript(in string: NSMutableAttributedString, range: NSRange, defaultFont: UIFont) {
        self.toggle(superscript: false, in: string, range: range, defaultFont: defaultFont)
    }

    private static func toggle(superscript: Bool, in string: NSMutableAttributedString, range: NSRange, defaultFont: UIFont) {
        string.enumerateAttributes(in: range, options: []) { attributes, range, _ in
            let active = !(superscript ? self.superscriptIsActive(in: attributes) : self.subscriptIsActive(in: attributes))

            let font = (attributes[.font] as? UIFont) ?? defaultFont
            let newFontSize = active ? StringAttribute.subOrSuperScriptFontSizeRatio * defaultFont.pointSize : defaultFont.pointSize
            if font.pointSize != newFontSize {
                string.addAttributes([.font: font.withSize(newFontSize)], range: range)
            }

            if active {
                let offsetRatio = superscript ? StringAttribute.superscriptFontOffset : StringAttribute.subscriptFontOffset
                let offset = defaultFont.pointSize * offsetRatio * (superscript ? 1 : -1)
                string.addAttributes([.baselineOffset: offset], range: range)
            } else {
                string.removeAttribute(.baselineOffset, range: range)
            }
        }
    }

    private static func superscriptIsActive(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let baselineOffset = attributes[.baselineOffset] as? CGFloat, baselineOffset != 0 else { return false }
        return baselineOffset > 0
    }

    private static func subscriptIsActive(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let baselineOffset = attributes[.baselineOffset] as? CGFloat, baselineOffset != 0 else { return false }
        return baselineOffset < 0
    }
}
