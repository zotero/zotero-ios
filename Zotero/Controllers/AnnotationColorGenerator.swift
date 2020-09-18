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
    private static let highlightDarkOpacity: CGFloat = 0.7

    static func color(from color: UIColor, isHighlight: Bool, userInterfaceStyle: UIUserInterfaceStyle) -> UIColor {
        if !isHighlight {
            return color
        }

        switch userInterfaceStyle {
        case .dark:
            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var brg: CGFloat = 0
            var alpha: CGFloat = 0

            color.getHue(&hue, saturation: &sat, brightness: &brg, alpha: &alpha)

            return UIColor(hue: hue, saturation: sat * 1.2, brightness: brg, alpha: AnnotationColorGenerator.highlightDarkOpacity)
        default:
            return color.withAlphaComponent(AnnotationColorGenerator.highlightOpacity)
        }
    }
}
