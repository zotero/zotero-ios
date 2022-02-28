//
//  AnnotationBoundingBoxCalculator.swift
//  Zotero
//
//  Created by Michal Rentka on 28.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationBoundingBoxCalculator {
    static func boundingBox(from paths: [[CGPoint]], lineWidth: CGFloat) -> CGRect {
        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = 0.0
        var maxY: CGFloat = 0.0

        for path in paths {
            for point in path {
                let _minX = point.x - lineWidth
                let _maxX = point.x + lineWidth
                let _minY = point.y - lineWidth
                let _maxY = point.y + lineWidth

                if _minX < minX {
                    minX = _minX
                }
                if _maxX > maxX {
                    maxX = _maxX
                }
                if _minY < minY {
                    minY = _minY
                }
                if _maxY > maxY {
                    maxY = _maxY
                }
            }
        }

        return CGRect(x: minX, y: minY, width: (maxX - minX), height: (maxY - minY))
    }

    static func boundingBox(from rects: [CGRect]) -> CGRect {
        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = 0.0
        var maxY: CGFloat = 0.0

        for rect in rects {
            if rect.minX < minX {
                minX = rect.minX
            }
            if rect.minY < minY {
                minY = rect.minY
            }
            if rect.maxX > maxX {
                maxX = rect.maxX
            }
            if rect.maxY > maxY {
                maxY = rect.maxY
            }
        }

        return CGRect(x: minX, y: minY, width: (maxX - minX), height: (maxY - minY))
    }
}

