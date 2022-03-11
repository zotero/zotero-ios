//
//  AnnotationSplitter.swift
//  Zotero
//
//  Created by Michal Rentka on 10.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol SplittablePathPoint {
    var x: Double { get }
    var y: Double { get }
}

final class AnnotationSplitter {
    static func splitRectsIfNeeded(rects: [CGRect]) -> [[CGRect]]? {
        guard !rects.isEmpty else { return nil }

        let sortedRects = rects.sorted { lRect, rRect in
            if lRect.minY == rRect.minY {
                return lRect.minX < rRect.minX
            }
            return lRect.minY > rRect.minY
        }

        var count = 2 // 2 for starting and ending brackets of array
        var splitRects: [[CGRect]] = []
        var currentRects: [CGRect] = []

        for rect in sortedRects {
            let size = "\(Decimal(rect.minX).rounded(to: 3))".count + "\(Decimal(rect.minY).rounded(to: 3))".count +
                       "\(Decimal(rect.maxX).rounded(to: 3))".count + "\(Decimal(rect.maxY).rounded(to: 3))".count + 6 // 4 commas (3 inbetween numbers, 1 after brackets) and 2 brackets for array

            if count + size > AnnotationsConfig.positionSizeLimit {
                if !currentRects.isEmpty {
                    splitRects.append(currentRects)
                    currentRects = []
                }
                count = 2
            }

            currentRects.append(rect)
            count += size
        }

        if !currentRects.isEmpty {
            splitRects.append(currentRects)
        }

        if splitRects.count == 1 {
            return nil
        }
        return splitRects
    }

    static func splitPathsIfNeeded<Point: SplittablePathPoint>(paths: [[Point]]) -> [[[Point]]]? {
        guard !paths.isEmpty else { return [] }

        var count = 2 // 2 for starting and ending brackets of array
        var splitPaths: [[[Point]]] = []
        var currentLines: [[Point]] = []
        var currentPoints: [Point] = []

        for subpaths in paths {
            if count + 3 > AnnotationsConfig.positionSizeLimit {
                if !currentPoints.isEmpty {
                    currentLines.append(currentPoints)
                    currentPoints = []
                }
                if !currentLines.isEmpty {
                    splitPaths.append(currentLines)
                    currentLines = []
                }
                count = 2
            }

            count += 3 // brackets for this group of points + comma

            for point in subpaths {
                let size = "\(Decimal(point.x).rounded(to: 3))".count + "\(Decimal(point.y).rounded(to: 3))".count + 2 // 2 commas (1 inbetween numbers, 1 after tuple)

                if count + size > AnnotationsConfig.positionSizeLimit {
                    if !currentPoints.isEmpty {
                        currentLines.append(currentPoints)
                        currentPoints = []
                    }
                    if !currentLines.isEmpty {
                        splitPaths.append(currentLines)
                        currentLines = []
                    }
                    count = 5
                }

                count += size
                currentPoints.append(point)
            }

            currentLines.append(currentPoints)
            currentPoints = []
        }

        if !currentPoints.isEmpty {
            currentLines.append(currentPoints)
        }
        if !currentLines.isEmpty {
            splitPaths.append(currentLines)
        }

        if splitPaths.count == 1 {
            return nil
        }
        return splitPaths
    }
}
