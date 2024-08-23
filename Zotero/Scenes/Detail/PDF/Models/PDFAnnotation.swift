//
//  PDFAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol PDFAnnotation {
    var key: String { get }
    var readerKey: PDFReaderState.AnnotationKey { get }
    var type: AnnotationType { get }
    var page: Int { get }
    var pageLabel: String { get }
    var lineWidth: CGFloat? { get }
    var color: String { get }
    var comment: String { get }
    var text: String? { get }
    var fontSize: CGFloat? { get }
    var rotation: UInt? { get }
    var sortIndex: String { get }
    var dateModified: Date { get }
    var isSyncable: Bool { get }
    var tags: [Tag] { get }

    func isAuthor(currentUserId: Int) -> Bool
    func author(displayName: String, username: String) -> String
    func editability(currentUserId: Int, library: Library) -> AnnotationEditability
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
}
