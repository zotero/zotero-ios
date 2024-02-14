//
//  CommentIconDrawingController.swift
//  Zotero
//
//  Created by Michal Rentka on 12.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct CommentIconDrawingController {
    static let iconSize: CGSize = CGSize(width: 12, height: 12)

    static func draw(context: CGContext, boundingBox: CGRect, color: UIColor) {
        let size = Self.iconSize
        let width = size.width
        let height = size.height

        let scale = UIScreen.main.nativeScale
        let onePixelWidthInPoints = 1.0 / scale

        context.saveGState()
        context.setAlpha(0.5)
        context.translateBy(x: boundingBox.minX - (width / 2), y: boundingBox.maxY - (height / 2))

        let poly1: [(CGFloat, CGFloat)] = [(width / 2, 0), (width, 0), (width, height), (0, height), (0, height / 2)]
        let points1 = poly1.map { CGPoint(x: $0, y: $1) }

        let poly2: [(CGFloat, CGFloat)] = [(width / 2, 0), (width / 2, height / 2), (0, height / 2)]
        let points2 = poly2.map { CGPoint(x: $0, y: $1) }

        context.beginPath()
        context.addLines(between: points1)
        context.closePath()
        color.setFill()
        context.fillPath()

        context.beginPath()
        context.addLines(between: points2)
        context.closePath()
        UIColor.white.withAlphaComponent(0.4).setFill()
        context.fillPath()

        context.beginPath()
        context.addLines(between: points1 + points2)
        context.setLineWidth(onePixelWidthInPoints)
        UIColor.black.setStroke()
        context.strokePath()

        context.restoreGState()
    }
}
