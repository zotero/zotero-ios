//
//  PDFAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol PDFAnnotation: ReaderAnnotation {
    var readerKey: PDFReaderAnnotationKey { get }
    var page: Int { get }
    var rotation: UInt? { get }
    var isSyncable: Bool { get }

    func rects(boundingBoxConverter: AnnotationBoundingBoxConverter) -> [CGRect]
    func paths(boundingBoxConverter: AnnotationBoundingBoxConverter) -> [[CGPoint]]
}

extension PDFAnnotation {
    func previewBoundingBox(boundingBoxConverter: AnnotationBoundingBoxConverter) -> CGRect {
        let boundingBox = boundingBox(boundingBoxConverter: boundingBoxConverter)
        switch self.type {
        case .image:
            return AnnotationPreviewBoundingBoxCalculator.imagePreviewRect(from: boundingBox, lineWidth: AnnotationsConfig.imageAnnotationLineWidth)

        case .ink:
            return AnnotationPreviewBoundingBoxCalculator.inkPreviewRect(from: boundingBox)

        case .freeText:
            return AnnotationPreviewBoundingBoxCalculator.freeTextPreviewRect(from: boundingBox, rotation: self.rotation ?? 0)

        case .note, .highlight, .underline:
            return boundingBox
        }
    }

    func boundingBox(rects: [CGRect]) -> CGRect {
        if rects.count == 1 {
            return rects[0]
        }
        return AnnotationBoundingBoxCalculator.boundingBox(from: rects).rounded(to: 3)
    }

    func boundingBox(paths: [[CGPoint]], lineWidth: CGFloat) -> CGRect {
        return AnnotationBoundingBoxCalculator.boundingBox(from: paths, lineWidth: lineWidth)
    }

    func boundingBox(boundingBoxConverter: AnnotationBoundingBoxConverter) -> CGRect {
        switch self.type {
        case .ink:
            let paths = self.paths(boundingBoxConverter: boundingBoxConverter)
            let lineWidth = self.lineWidth ?? 1
            return boundingBox(paths: paths, lineWidth: lineWidth)

        case .note, .image, .highlight, .underline, .freeText:
            let rects = self.rects(boundingBoxConverter: boundingBoxConverter)
            return boundingBox(rects: rects)
        }
    }

    func matches(term: String?, filter: AnnotationsFilter?, displayName: String, username: String) -> Bool {
        let hasTerm = matchesTerm(term: term, displayName: displayName, username: username)
        let hasFilter: Bool
        if let filter {
            hasFilter = matchesFilter(filter: filter)
        } else {
            hasFilter = true
        }
        return hasTerm && hasFilter
    }

    private func matchesTerm(term: String?, displayName: String, username: String) -> Bool {
        guard let term else { return true }
        return key.lowercased() == term.lowercased() ||
               author(displayName: displayName, username: username).localizedCaseInsensitiveContains(term) ||
               comment.localizedCaseInsensitiveContains(term) ||
               (text ?? "").localizedCaseInsensitiveContains(term) ||
               tags.contains(where: { $0.name.localizedCaseInsensitiveContains(term) })
    }

    private func matchesFilter(filter: AnnotationsFilter) -> Bool {
        // TODO: cache this set, maybe cache and pass the intersections as well?
        let defaultColors = Set(AnnotationsConfig.allColors)
        let selectedDefaultColors = filter.colors.intersection(defaultColors)
        let selectedExtraColors = filter.colors.subtracting(defaultColors)

        let hasTag: Bool
        if filter.tags.isEmpty {
            hasTag = true
        } else if isSyncable {
            hasTag = tags.contains(where: { filter.tags.contains($0.name) })
        } else {
            return false
        }

        let hasColor: Bool
        if selectedDefaultColors.isEmpty && selectedExtraColors.isEmpty {
            hasColor = true
        } else if !isSyncable {
            hasColor = selectedDefaultColors.contains(color) || selectedExtraColors.contains(color)
        } else if !selectedDefaultColors.isEmpty {
            hasColor = selectedDefaultColors.contains(color)
        } else {
            return false
        }

        return hasTag && hasColor
    }
}
