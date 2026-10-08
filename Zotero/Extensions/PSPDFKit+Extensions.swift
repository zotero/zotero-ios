//
//  PSPDFKit+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 06/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

extension Document {
    func annotation(at pageIndex: PageIndex, with key: String) -> PSPDFKit.Annotation? {
        return annotations(at: pageIndex).first(where: { $0.key == key || $0.uuid == key })
    }
}

extension Document: AnnotationBoundingBoxConverter {
    /// Converts from database to PSPDFKit rect. Database stores rects in RAW PDF Coordinate space. PSPDFKit works with Normalized PDF Coordinate Space.
    func convertFromDb(rect: CGRect, page: PageIndex) -> CGRect? {
        guard let pageInfo = pageInfoForPage(at: page) else { return nil }
        return rect.applying(pageInfo.transform)
    }

    func convertFromDb(point: CGPoint, page: PageIndex) -> CGPoint? {
        let tmpRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        return convertFromDb(rect: tmpRect, page: page)?.origin
    }

    /// Converts from PSPDFKit to database rect. Database stores rects in RAW PDF Coordinate space. PSPDFKit works with Normalized PDF Coordinate Space.
    func convertToDb(rect: CGRect, page: PageIndex) -> CGRect? {
        guard let pageInfo = pageInfoForPage(at: page) else { return nil }
        return rect.applying(pageInfo.transform.inverted())
    }

    func convertToDb(point: CGPoint, page: PageIndex) -> CGPoint? {
        let tmpRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        return convertToDb(rect: tmpRect, page: page)?.origin
    }

    /// Converts from PSPDFKit to sort index rect. PSPDFKit works with Normalized PDF Coordinate Space. Sort index stores y coordinate in RAW View Coordinate Space.
    func sortIndexMinY(rect: CGRect, page: PageIndex) -> CGFloat? {
        guard let pageInfo = pageInfoForPage(at: page) else { return nil }

        switch pageInfo.savedRotation {
        case .rotation0:
            return pageInfo.size.height - rect.maxY

        case .rotation180:
            return rect.minY

        case .rotation90:
            return pageInfo.size.width - rect.minX

        case .rotation270:
            return rect.minX
        }
    }

    func textOffset(rect: CGRect, page: PageIndex) -> Int? {
        guard let parser = textParserForPage(at: page), !parser.glyphs.isEmpty else { return nil }

        var index = 0
        var minDistance: CGFloat = .greatestFiniteMagnitude
        var textOffset = 0

        for glyph in parser.glyphs {
            guard !glyph.isWordOrLineBreaker else { continue }

            let distance = rect.distance(to: glyph.frame)

            if distance < minDistance {
                minDistance = distance
                textOffset = index
            }

            index += 1
        }

        return textOffset
    }
}

extension PSPDFKit.Annotation {
    enum Source: String {
        case database
        case document
    }

    /// Defines internal Zotero key. PDFs which were previously exported by Zotero may include this flag.
    var key: String? {
        get {
            return self.customData?[AnnotationsConfig.keyKey] as? String
        }

        set {
            if self.customData == nil {
                if let key = newValue {
                    self.customData = [AnnotationsConfig.keyKey: key]
                }
            } else {
                self.customData?[AnnotationsConfig.keyKey] = newValue
            }
        }
    }

    var baseColor: String {
        get {
            if let customBaseColor = customData?[AnnotationsConfig.baseColorKey] as? String, !customBaseColor.isEmpty {
                return customBaseColor
            }
            if let currentColorHex = color?.hexString {
                return AnnotationsConfig.colorVariationMap[currentColorHex] ?? currentColorHex
            }
            return AnnotationsConfig.defaultActiveColor
        }

        set {
            if customData == nil {
                customData = [AnnotationsConfig.baseColorKey: newValue]
            } else {
                customData?[AnnotationsConfig.baseColorKey] = newValue
            }
        }
    }

    var source: Source? {
        get {
            guard let rawValue = customData?[AnnotationsConfig.sourceKey] as? String else { return nil }
            return Source(rawValue: rawValue)
        }

        set {
            if customData == nil {
                if let newValue {
                    customData = [AnnotationsConfig.sourceKey: newValue.rawValue]
                }
            } else {
                customData?[AnnotationsConfig.sourceKey] = newValue?.rawValue
            }
        }
    }

    var createdByUserId: Int? {
        get {
            return customData?[AnnotationsConfig.createdByUserIdKey] as? Int
        }

        set {
            if customData == nil {
                if let newValue {
                    customData = [AnnotationsConfig.createdByUserIdKey: newValue]
                }
            } else {
                customData?[AnnotationsConfig.createdByUserIdKey] = newValue
            }
        }
    }

    @objc var previewBoundingBox: CGRect {
        return self.boundingBox
    }

    var isZoteroAnnotation: Bool {
        return self.key != nil || (self.name ?? "").contains("Zotero")
    }

    var shouldRenderPreview: Bool {
        return (self is PSPDFKit.SquareAnnotation) || (self is PSPDFKit.InkAnnotation) || (self is PSPDFKit.FreeTextAnnotation)
    }

    var previewId: String {
        return self.key ?? self.uuid
    }

    var tool: PSPDFKit.Annotation.Tool? {
        switch type {
        case .highlight:
            return .highlight

        case .note:
            return .note

        case .square:
            return .square

        case .ink:
            return .ink

        case .underline:
            return .underline

        case .freeText:
            return .freeText

        default:
            return nil
        }
    }
}

extension PSPDFKit.SquareAnnotation {
    override var previewBoundingBox: CGRect {
        return AnnotationPreviewBoundingBoxCalculator.imagePreviewRect(from: self.boundingBox, lineWidth: self.lineWidth)
    }
}

extension PSPDFKit.InkAnnotation {
    override var previewBoundingBox: CGRect {
        return AnnotationPreviewBoundingBoxCalculator.inkPreviewRect(from: self.boundingBox)
    }
}
