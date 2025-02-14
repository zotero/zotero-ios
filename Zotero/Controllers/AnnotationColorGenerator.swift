//
//  AnnotationColorGenerator.swift
//  Zotero
//
//  Created by Michal Rentka on 18/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationColorGenerator {
    private static let highlightOpacity: CGFloat = 0.5
    private static let highlightDarkOpacity: CGFloat = 0.5
    private static let underlineOpacity: CGFloat = 1
    private static let underlineDarkOpacity: CGFloat = 1

    static func color(from color: UIColor, type: AnnotationType?, appearance: Appearance) -> (color: UIColor, alpha: CGFloat, blendMode: CGBlendMode?) {
        let opacity: CGFloat
        switch type {
        case .none, .note, .image, .ink, .freeText:
            return (color, 1, nil)

        case .highlight:
            switch appearance {
            case .dark:
                opacity = Self.highlightDarkOpacity

            case .light, .sepia:
                opacity = Self.highlightOpacity
            }

        case .underline:
            switch appearance {
            case .dark:
                opacity = Self.underlineDarkOpacity

            case .light, .sepia:
                opacity = Self.underlineOpacity
            }
        }

        let adjustedColor: UIColor
        switch appearance {
        case .dark:
            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var brg: CGFloat = 0
            var alpha: CGFloat = 0

            color.getHue(&hue, saturation: &sat, brightness: &brg, alpha: &alpha)

            let adjustedSat = min(1, (sat * 1.2))
            adjustedColor = UIColor(hue: hue, saturation: adjustedSat, brightness: brg, alpha: opacity)

        case .light, .sepia:
            adjustedColor = color.withAlphaComponent(opacity)
        }

        return (adjustedColor, opacity, Self.blendMode(for: appearance, type: type))
    }

    static func blendMode(for appearance: Appearance, type: AnnotationType?) -> CGBlendMode? {
        switch type {
        case .none, .note, .image, .ink, .freeText:
            return nil

        case .highlight, .underline:
            switch appearance {
            case .dark:
                return .lighten

            case .light, .sepia:
                return .multiply
            }
        }
    }
}
