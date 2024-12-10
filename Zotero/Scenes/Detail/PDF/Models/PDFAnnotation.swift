//
//  PDFAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol PDFAnnotation: ReaderAnnotation {
    var readerKey: PDFReaderState.AnnotationKey { get }
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
}
