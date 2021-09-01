//
//  AnnotationConverter.swift
//  Zotero
//
//  Created by Michal Rentka on 25.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

#if PDFENABLED

import CocoaLumberjackSwift
import PSPDFKit

struct AnnotationConverter {
    enum Kind {
        case export
        case zotero
    }

    // MARK: - Helpers

    /// Creates sort index from annotation and bounding box.
    /// - parameter annotation: PSPDFKit annotation from which sort index is created
    /// - parameter boundingBox; Bounding box converted to screen coordinates.
    /// - returns: Sort index (5 places for page, 6 places for character offset, 5 places for y position)
    static func sortIndex(from annotation: PSPDFKit.Annotation, boundingBoxConverter: AnnotationBoundingBoxConverter?) -> String {
        let rect: CGRect
        if annotation is PSPDFKit.HighlightAnnotation {
            rect = annotation.rects?.first ?? annotation.boundingBox
        } else {
            rect = annotation.boundingBox
        }

        let textOffset = boundingBoxConverter?.textOffset(rect: rect, page: annotation.pageIndex) ?? 0
        let minY = boundingBoxConverter?.sortIndexMinY(rect: rect, page: annotation.pageIndex).flatMap({ Int(round($0)) }) ?? 0
        return self.sortIndex(pageIndex: annotation.pageIndex, textOffset: textOffset, minY: minY)
    }

    static func sortIndex(pageIndex: PageIndex, textOffset: Int, minY: Int) -> String {
        return String(format: "%05d|%06d|%05d", pageIndex, textOffset, minY)
    }

    // MARK: - DB -> Memory

    static func annotation(from item: RItem, editability: Annotation.Editability, currentUserId: Int, username: String, boundingBoxConverter: AnnotationBoundingBoxConverter) -> Annotation? {
        guard let rawType = item.fieldValue(for: FieldKeys.Item.Annotation.type),
              let pageIndex = item.fieldValue(for: FieldKeys.Item.Annotation.pageIndex).flatMap(Int.init),
              let pageLabel = item.fieldValue(for: FieldKeys.Item.Annotation.pageLabel),
              let color = item.fieldValue(for: FieldKeys.Item.Annotation.color) else {
            return nil
        }
        guard let type = AnnotationType(rawValue: rawType) else {
            DDLogError("AnnotationConverter: unknown annotation type '\(rawType)'")
            return nil
        }

        if type == .ink {
            // TODO: - remove when ink annotations are enabled
            return nil
        }

        let text = item.fields.filter(.key(FieldKeys.Item.Annotation.text)).first?.value

        if type == .highlight && text == nil {
            DDLogError("AnnotationConverter: highlight annotation is missing text property")
            return nil
        }

        let isAuthor: Bool
        let author: String
        if item.customLibraryKey != nil {
            // In "My Library" current user is always author
            isAuthor = true
            author = username
        } else {
            // In group library compare `createdBy` user to current user
            isAuthor = item.createdBy?.identifier == currentUserId
            // Users can only edit their own annotations
            if isAuthor {
                author = username
            } else if let name = item.createdBy?.name, !name.isEmpty {
                author = name
            } else if let name = item.createdBy?.username, !name.isEmpty {
                author = name
            } else {
                author = L10n.unknown
            }
        }

        let comment = item.fieldValue(for: FieldKeys.Item.Annotation.comment) ?? ""
        let rects: [CGRect] = item.rects.map({ CGRect(x: $0.minX, y: $0.minY, width: ($0.maxX - $0.minX), height: ($0.maxY - $0.minY)) })
                                        .compactMap({ boundingBoxConverter.convertFromDb(rect: $0, page: PageIndex(pageIndex)) })
        var paths: [[CGPoint]] = []
        for path in item.paths.sorted(byKeyPath: "sortIndex") {
            guard path.coordinates.count % 2 == 0 else { continue }
            let sortedCoordinates = path.coordinates.sorted(byKeyPath: "sortIndex")
            let lines = (0..<(path.coordinates.count / 2)).map({ idx -> CGPoint in
                return CGPoint(x: sortedCoordinates[idx * 2].value, y: sortedCoordinates[(idx * 2) + 1].value)
            })
            paths.append(lines)
        }
        let lineWidth = (item.fields.filter(.key(FieldKeys.Item.Annotation.lineWidth)).first?.value).flatMap(Double.init).flatMap(CGFloat.init)

        return Annotation(key: item.key,
                          type: type,
                          page: pageIndex,
                          pageLabel: pageLabel,
                          rects: rects,
                          paths: paths,
                          lineWidth: lineWidth,
                          author: author,
                          isAuthor: isAuthor,
                          color: color,
                          comment: comment,
                          text: text,
                          sortIndex: item.annotationSortIndex,
                          dateModified: item.dateModified,
                          tags: item.tags.map({ Tag(tag: $0) }),
                          didChange: false,
                          editability: editability,
                          isSyncable: true)
    }

    // MARK: - PSPDFKit -> Zotero

    /// Create Zotero annotation from existing PSPDFKit annotation.
    /// - parameter annotation: PSPDFKit annotation.
    /// - parameter color: Base color of annotation (can differ from current `PSPDPFKit.Annotation.color`)
    /// - parameter editability: Type of editability for given annotation.
    /// - parameter isNew: Indicating, whether the annotation has just been created.
    /// - parameter username: Username of current user.
    /// - returns: Matching Zotero annotation.
    static func annotation(from annotation: PSPDFKit.Annotation, color: String, editability: Annotation.Editability, isNew: Bool, isSyncable: Bool, username: String,
                           boundingBoxConverter: AnnotationBoundingBoxConverter?) -> Annotation? {
        guard let document = annotation.document, AnnotationsConfig.supported.contains(annotation.type) else { return nil }

        let key = isSyncable ? KeyGenerator.newKey : annotation.uuid
        let page = Int(annotation.pageIndex)
        let pageLabel = document.pageLabelForPage(at: annotation.pageIndex, substituteWithPlainLabel: false) ?? "\(annotation.pageIndex + 1)"
        let author = isNew ? username : (annotation.user ?? "")
        let isAuthor = isNew ? true : (annotation.user == username)
        let comment = annotation.contents.flatMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) ?? ""
        let sortIndex = self.sortIndex(from: annotation, boundingBoxConverter: boundingBoxConverter)
        let date = Date()

        let type: AnnotationType
        let rects: [CGRect]
        let text: String?
        let paths: [[CGPoint]]
        let lineWidth: CGFloat?

        if let annotation = annotation as? PSPDFKit.NoteAnnotation {
            type = .note
            rects = [CGRect(origin: annotation.boundingBox.origin, size: AnnotationsConfig.noteAnnotationSize)]
            text = nil
            paths = []
            lineWidth = nil
        } else if let annotation = annotation as? PSPDFKit.HighlightAnnotation {
            type = .highlight
            rects = annotation.rects ?? [annotation.boundingBox]
            text = annotation.markedUpString.trimmingCharacters(in: .whitespacesAndNewlines)
            paths = []
            lineWidth = nil
        } else if let annotation = annotation as? PSPDFKit.SquareAnnotation {
            type = .image
            rects = [annotation.boundingBox]
            text = nil
            paths = []
            lineWidth = nil
        } else if let annotation = annotation as? PSPDFKit.InkAnnotation {
            // TODO: - change when ink annotations are enabled
//            type = .ink
//            rects = []
//            text = nil
//            paths = annotation.lines.flatMap({ lines -> [[CGPoint]] in
//                return lines.map({ group in
//                    return group.map({ $0.location })
//                })
//            }) ?? []
//            lineWidth = annotation.lineWidth
            return nil
        } else {
            return nil
        }

        return Annotation(key: key,
                          type: type,
                          page: page,
                          pageLabel: pageLabel,
                          rects: rects,
                          paths: paths,
                          lineWidth: lineWidth,
                          author: author,
                          isAuthor: isAuthor,
                          color: color,
                          comment: comment,
                          text: text,
                          sortIndex: sortIndex,
                          dateModified: date,
                          tags: [],
                          didChange: isNew,
                          editability: editability,
                          isSyncable: isSyncable)
    }

    // MARK: - Zotero -> PSPDFKit

    /// Converts Zotero annotations to actual document (PSPDFKit) annotations with custom flags.
    /// - parameter zoteroAnnotations: Annotations to convert.
    /// - returns: Array of PSPDFKit annotations that can be added to document.
    static func annotations(from zoteroAnnotations: [Int: [Annotation]], type: Kind = .zotero, interfaceStyle: UIUserInterfaceStyle) -> [PSPDFKit.Annotation] {
        return zoteroAnnotations.values.flatMap({ $0 }).map({
            return self.annotation(from: $0, type: type, interfaceStyle: interfaceStyle)
        })
    }

    static func annotation(from zoteroAnnotation: Annotation, type: Kind, interfaceStyle: UIUserInterfaceStyle) -> PSPDFKit.Annotation {
        let (color, alpha) = AnnotationColorGenerator.color(from: UIColor(hex: zoteroAnnotation.color), isHighlight: (zoteroAnnotation.type == .highlight), userInterfaceStyle: interfaceStyle)
        let annotation: PSPDFKit.Annotation

        switch zoteroAnnotation.type {
        case .image:
            annotation = self.areaAnnotation(from: zoteroAnnotation, type: type, color: color)
        case .highlight:
            annotation = self.highlightAnnotation(from: zoteroAnnotation, type: type, color: color, alpha: alpha)
        case .note:
            annotation = self.noteAnnotation(from: zoteroAnnotation, type: type, color: color)
        case .ink:
            annotation = self.inkAnnotation(from: zoteroAnnotation, type: type, color: color)
        }

        switch type {
        case .export:
            annotation.key = zoteroAnnotation.key

        case .zotero:
            annotation.customData = [AnnotationsConfig.baseColorKey: zoteroAnnotation.color,
                                     AnnotationsConfig.keyKey: zoteroAnnotation.key,
                                     AnnotationsConfig.syncableKey: true]

            if zoteroAnnotation.editability != .editable {
                annotation.flags.update(with: .locked)
            }
        }

        annotation.pageIndex = UInt(zoteroAnnotation.page)
        annotation.contents = zoteroAnnotation.comment
        annotation.user = zoteroAnnotation.author
        annotation.name = "Zotero-\(zoteroAnnotation.key)"

        return annotation
    }

    /// Creates corresponding `SquareAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private static func areaAnnotation(from annotation: Annotation, type: Kind, color: UIColor) -> PSPDFKit.SquareAnnotation {
        let square: PSPDFKit.SquareAnnotation
        switch type {
        case .export:
            square = PSPDFKit.SquareAnnotation()
        case .zotero:
            square = SquareAnnotation()
        }

        square.boundingBox = annotation.boundingBox.rounded(to: 3)
        square.borderColor = color

        return square
    }

    /// Creates corresponding `HighlightAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private static func highlightAnnotation(from annotation: Annotation, type: Kind, color: UIColor, alpha: CGFloat) -> PSPDFKit.HighlightAnnotation {
        let highlight: PSPDFKit.HighlightAnnotation
        switch type {
        case .export:
            highlight = PSPDFKit.HighlightAnnotation()
        case .zotero:
            highlight = HighlightAnnotation()
        }

        highlight.boundingBox = annotation.boundingBox.rounded(to: 3)
        highlight.rects = annotation.rects.map({ $0.rounded(to: 3) })
        highlight.color = color
        highlight.alpha = alpha

        return highlight
    }

    /// Creates corresponding `NoteAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private static func noteAnnotation(from annotation: Annotation, type: Kind, color: UIColor) -> PSPDFKit.NoteAnnotation {
        let note: PSPDFKit.NoteAnnotation
        switch type {
        case .export:
            note = PSPDFKit.NoteAnnotation(contents: annotation.comment)
        case .zotero:
            note = NoteAnnotation(contents: annotation.comment)
        }

        let boundingBox = annotation.boundingBox.rounded(to: 3)
        note.boundingBox = CGRect(origin: boundingBox.origin, size: AnnotationsConfig.noteAnnotationSize)
        note.borderStyle = .dashed
        note.color = color

        return note
    }

    private static func inkAnnotation(from annotation: Annotation, type: Kind, color: UIColor) -> PSPDFKit.InkAnnotation {
        let lines = annotation.paths.map({ group in
            return group.map({ DrawingPoint(cgPoint: $0) })
        })
        let ink = PSPDFKit.InkAnnotation(lines: lines)
        ink.color = color
        ink.lineWidth = annotation.lineWidth ?? 1
        return ink
    }
}

extension RItem {
    fileprivate func fieldValue(for key: String) -> String? {
        let value = self.fields.filter(.key(key)).first?.value
        if value == nil {
            DDLogError("Annotation: missing value for `\(key)`")
        }
        return value
    }
}

#endif
