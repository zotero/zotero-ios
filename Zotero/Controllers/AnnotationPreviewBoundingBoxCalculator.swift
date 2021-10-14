//
//  AnnotationPreviewBoundingBoxCalculator.swift
//  Zotero
//
//  Created by Michal Rentka on 14.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationPreviewBoundingBoxCalculator {
    private static let inkMinHeight: CGFloat = 20
    private static let inkMinWidth: CGFloat = 50

    static func inkPreviewRect(from boundingBox: CGRect) -> CGRect {
        let widthDifference = boundingBox.width - AnnotationPreviewBoundingBoxCalculator.inkMinWidth
        let heightDifference = boundingBox.height - AnnotationPreviewBoundingBoxCalculator.inkMinHeight

        guard widthDifference < 0 || heightDifference < 0 else { return boundingBox }

        if boundingBox.width == boundingBox.height {
            // If it's square, increase size to match min width.
            return boundingBox.insetBy(dx: widthDifference/2, dy: widthDifference/2)
        }

        // Otherwise increase individual sizes to match their minimums
        var newBoundingBox = boundingBox
        if widthDifference < 0 {
            newBoundingBox = newBoundingBox.insetBy(dx: widthDifference/2, dy: 0)
        }
        if heightDifference < 0 {
            // Narrow heights are lines. Lines usually want to highlight something above them. Move the preview bounding box above line.
            newBoundingBox.size.height -= heightDifference
        }
        return newBoundingBox
    }

    static func imagePreviewRect(from boundingBox: CGRect, lineWidth: CGFloat) -> CGRect {
        return boundingBox.insetBy(dx: (lineWidth + 1), dy: (lineWidth + 1))
    }
}
