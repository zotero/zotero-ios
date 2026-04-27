//
//  AnnotationsConfig.swift
//  Zotero
//
//  Created by Michal Rentka on 12/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

#if MAINAPP
import PSPDFKit
#endif

struct AnnotationsConfig {
    static let positionSizeLimit = 65000
    #if MAINAPP
    static let defaultActiveColor = "#ffd400"
    static let allColors: [String] = ["#ffd400", "#ff6666", "#5fb236", "#2ea8e5", "#a28ae5", "#e56eee", "#f19837", "#aaaaaa", "#000000"]
    static let typesWithColorVariation: [AnnotationType?] = [.none, .highlight, .underline]
    static let appearancesWithVariation: [Appearance] = [.light, .dark, .sepia]
    static let colorNames: [String: String] = [
        "#ffd400": "Yellow",
        "#ff6666": "Red",
        "#5fb236": "Green",
        "#2ea8e5": "Blue",
        "#a28ae5": "Purple",
        "#e56eee": "Magenta",
        "#f19837": "Orange",
        "#aaaaaa": "Gray",
        "#000000": "Black"
    ]
    // Maps different variations colors to their base color
    static let colorVariationMap: [String: String] = createColorVariationMap()
    static let keyKey = "Zotero:Key"
    static let baseColorKey = "Zotero:BaseColor"
    // Line width of image annotation in PDF document.
    static let imageAnnotationLineWidth: CGFloat = 2
    // Free text annotation font size minimum, maximum, increment and rounding
    static let freeTextAnnotationFontSizeMinimum: CGFloat = 1
    static let freeTextAnnotationFontSizeMaximum: CGFloat = 200
    static let freeTextAnnotationFontSizeIncrement: CGFloat = 0.5
    static func roundFreeTextAnnotationFontSize(_ fontSize: CGFloat) -> CGFloat {
        round(fontSize * 2) / 2
    }
    // Size of note annotation in PDF document.
    static let noteAnnotationSize: CGSize = CGSize(width: 22, height: 22)
    static let supported: PSPDFKit.Annotation.Kind = [.note, .highlight, .square, .ink, .underline, .freeText]
    static let editableAnnotationTypes: Set<PSPDFKit.Annotation.Tool> = Set([.note, .highlight, .square, .ink, .underline, .freeText])

    static func colors(for type: AnnotationType) -> [String] {
        switch type {
        case .ink, .freeText:
            return ["#ffd400", "#ff6666", "#5fb236", "#2ea8e5", "#a28ae5", "#e56eee", "#f19837", "#aaaaaa", "#000000"]

        default:
            return ["#ffd400", "#ff6666", "#5fb236", "#2ea8e5", "#a28ae5", "#e56eee", "#f19837", "#aaaaaa"]
        }
    }

    private static func createColorVariationMap() -> [String: String] {
        var map: [String: String] = [:]
        for hexBaseColor in allColors {
            let baseColor = UIColor(hex: hexBaseColor)
            for type in typesWithColorVariation {
                for appearance in appearancesWithVariation {
                    let variation = AnnotationColorGenerator.color(from: baseColor, type: type, appearance: appearance).color
                    map[variation.hexString] = hexBaseColor
                }
            }
        }
        return map
    }
    #endif
}
