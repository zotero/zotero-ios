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

    static func color(from color: UIColor, isHighlight: Bool, userInterfaceStyle: UIUserInterfaceStyle) -> (color: UIColor, alpha: CGFloat, blendMode: CGBlendMode?) {
        if !isHighlight {
            return (color, 1, nil)
        }

        switch userInterfaceStyle {
        case .dark:
            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var brg: CGFloat = 0
            var alpha: CGFloat = 0

            color.getHue(&hue, saturation: &sat, brightness: &brg, alpha: &alpha)

            let adjustedSat = min(1, (sat * 1.2))
            let adjustedColor = UIColor(hue: hue, saturation: adjustedSat, brightness: brg, alpha: AnnotationColorGenerator.highlightDarkOpacity)
            return (adjustedColor, AnnotationColorGenerator.highlightDarkOpacity, .lighten)
        default:
            let adjustedColor = color.withAlphaComponent(AnnotationColorGenerator.highlightOpacity)
            return (adjustedColor, AnnotationColorGenerator.highlightOpacity, .multiply)
        }
    }

    static func blendMode(for userInterfaceStyle: UIUserInterfaceStyle, isHighlight: Bool) -> CGBlendMode? {
        guard isHighlight else { return nil }
        return userInterfaceStyle == .dark ? .lighten : .multiply
    }
}
