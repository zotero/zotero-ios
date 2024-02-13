//
//  AnnotationsConfig.swift
//  Zotero
//
//  Created by Michal Rentka on 12/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

struct AnnotationsConfig {
    static let defaultActiveColor = "#ffd400"
    static let allColors: [String] = ["#ffd400", "#ff6666", "#5fb236", "#2ea8e5", "#a28ae5", "#e56eee", "#f19837", "#aaaaaa", "#000000"]
    static let colorNames: [String: String] = ["#ffd400": "Yellow", "#ff6666": "Red", "#5fb236": "Green", "#2ea8e5": "Blue", "#a28ae5": "Purple", "#e56eee": "Magenta", "#f19837": "Orange", "#aaaaaa": "Gray", "#000000": "Black"]
    // Maps different variations colors to their base color
    static let colorVariationMap: [String: String] = createColorVariationMap()
    static let keyKey = "Zotero:Key"
    // Line width of image annotation in PDF document.
    static let imageAnnotationLineWidth: CGFloat = 2
    // Size of note annotation in PDF document.
    static let noteAnnotationSize: CGSize = CGSize(width: 16, height: 16)
    static let positionSizeLimit = 65000
    static let supported: PSPDFKit.Annotation.Kind = [.note, .highlight, .square, .ink]

    static func colors(for type: AnnotationType) -> [String] {
        switch type {
        case .ink:
            return ["#ffd400", "#ff6666", "#5fb236", "#2ea8e5", "#a28ae5", "#e56eee", "#f19837", "#aaaaaa", "#000000"]

        default:
            return ["#ffd400", "#ff6666", "#5fb236", "#2ea8e5", "#a28ae5", "#e56eee", "#f19837", "#aaaaaa"]
        }
    }

    private static func createColorVariationMap() -> [String: String] {
        var map: [String: String] = [:]
        for hexBaseColor in self.allColors {
            let baseColor = UIColor(hex: hexBaseColor)
            let color1 = AnnotationColorGenerator.color(from: baseColor, isHighlight: false, userInterfaceStyle: .light).color
            map[color1.hexString] = hexBaseColor
            let color2 = AnnotationColorGenerator.color(from: baseColor, isHighlight: false, userInterfaceStyle: .dark).color
            map[color2.hexString] = hexBaseColor
            let color3 = AnnotationColorGenerator.color(from: baseColor, isHighlight: true, userInterfaceStyle: .light).color
            map[color3.hexString] = hexBaseColor
            let color4 = AnnotationColorGenerator.color(from: baseColor, isHighlight: true, userInterfaceStyle: .dark).color
            map[color4.hexString] = hexBaseColor
        }
        return map
    }
}
