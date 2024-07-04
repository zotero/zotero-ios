//
//  AnnotationConverter.swift
//  Zotero
//
//  Created by Michal Rentka on 25.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import RealmSwift

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
        if minY < 0 {
            DDLogWarn("AnnotationConverter: annotation \(String(describing: annotation.key)) has negative y position \(minY)")
        }
        return self.sortIndex(pageIndex: annotation.pageIndex, textOffset: textOffset, minY: minY)
    }

    static func sortIndex(pageIndex: PageIndex, textOffset: Int, minY: Int) -> String {
        return String(format: "%05d|%06d|%05d", pageIndex, textOffset, max(0, minY))
    }

    // MARK: - PSPDFKit -> Zotero

    /// Create Zotero annotation from existing PSPDFKit annotation.
    /// - parameter annotation: PSPDFKit annotation.
    /// - parameter color: Base color of annotation (can differ from current `PSPDPFKit.Annotation.color`)
    /// - parameter library: Library where annotation is stored.
    /// - parameter username: Username of current user.
    /// - parameter displayName: Display name of current user.
    /// - parameter boundingBoxConverter: Converts rects from pdf coordinate space.
    /// - returns: Matching Zotero annotation.
    static func annotation(
        from annotation: PSPDFKit.Annotation,
        color: String,
        library: Library,
        username: String,
        displayName: String,
        boundingBoxConverter: AnnotationBoundingBoxConverter?
    ) -> PDFDocumentAnnotation? {
        guard let document = annotation.document, AnnotationsConfig.supported.contains(annotation.type) else { return nil }

        let key = annotation.key ?? annotation.uuid
        let page = Int(annotation.pageIndex)
        let pageLabel = document.pageLabelForPage(at: annotation.pageIndex, substituteWithPlainLabel: false) ?? "\(annotation.pageIndex + 1)"
        let isAuthor = annotation.user == displayName || annotation.user == username
        let comment = annotation.contents.flatMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) ?? ""
        let sortIndex = self.sortIndex(from: annotation, boundingBoxConverter: boundingBoxConverter)
        let date = Date()

        let author: String
        if isAuthor {
            author = self.createName(from: displayName, username: username)
        } else {
            author = annotation.user ?? L10n.unknown
        }

        let type: AnnotationType
        let rects: [CGRect]
        var text: String?
        let paths: [[CGPoint]]
        var lineWidth: CGFloat?
        var fontSize: UInt?
        var rotation: UInt?

        if let annotation = annotation as? PSPDFKit.NoteAnnotation {
            type = .note
            rects = self.rects(fromNoteAnnotation: annotation)
            paths = []
        } else if let annotation = annotation as? PSPDFKit.HighlightAnnotation {
            type = .highlight
            rects = self.rects(fromHighlightAndUnderlineAnnotation: annotation)
            text = TextConverter.convertTextForAnnotation(from: annotation.markedUpString)
            paths = []
        } else if let annotation = annotation as? PSPDFKit.SquareAnnotation {
            type = .image
            rects = self.rects(fromSquareAnnotation: annotation)
            paths = []
        } else if let annotation = annotation as? PSPDFKit.InkAnnotation {
            type = .ink
            rects = []
            paths = self.paths(from: annotation)
            lineWidth = annotation.lineWidth
        } else if let annotation = annotation as? PSPDFKit.UnderlineAnnotation {
            type = .underline
            rects = self.rects(fromHighlightAndUnderlineAnnotation: annotation)
            text = TextConverter.convertTextForAnnotation(from: annotation.markedUpString)
            paths = []
        } else if let annotation = annotation as? PSPDFKit.FreeTextAnnotation {
            type = .freeText
            fontSize = UInt(annotation.fontSize)
            rotation = annotation.rotation
            paths = []
            rects = self.rects(fromTextAnnotation: annotation)
        } else {
            return nil
        }

        return PDFDocumentAnnotation(
            key: key,
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
            fontSize: fontSize,
            rotation: rotation,
            sortIndex: sortIndex,
            dateModified: date
        )
    }

    static func paths(from annotation: PSPDFKit.InkAnnotation) -> [[CGPoint]] {
        return annotation.lines.flatMap({ lines -> [[CGPoint]] in
            return lines.map({ group in
                return group.map({ $0.location.rounded(to: 3) })
            })
        }) ?? []
    }

    static func rects(from annotation: PSPDFKit.Annotation) -> [CGRect]? {
        if let annotation = annotation as? PSPDFKit.NoteAnnotation {
            return self.rects(fromNoteAnnotation: annotation)
        }
        if annotation is PSPDFKit.HighlightAnnotation || annotation is PSPDFKit.UnderlineAnnotation {
            return self.rects(fromHighlightAndUnderlineAnnotation: annotation)
        }
        if let annotation = annotation as? PSPDFKit.SquareAnnotation {
            return self.rects(fromSquareAnnotation: annotation)
        }
        if let annotation = annotation as? PSPDFKit.FreeTextAnnotation {
            return self.rects(fromTextAnnotation: annotation)
        }
        return nil
    }

    private static func rects(fromNoteAnnotation annotation: PSPDFKit.NoteAnnotation) -> [CGRect] {
        return [CGRect(origin: annotation.boundingBox.origin.rounded(to: 3), size: AnnotationsConfig.noteAnnotationSize)]
    }

    private static func rects(fromHighlightAndUnderlineAnnotation annotation: PSPDFKit.Annotation) -> [CGRect] {
        return (annotation.rects ?? [annotation.boundingBox]).map({ $0.rounded(to: 3) })
    }

    private static func rects(fromSquareAnnotation annotation: PSPDFKit.SquareAnnotation) -> [CGRect] {
        return [annotation.boundingBox.rounded(to: 3)]
    }

    private static func rects(fromTextAnnotation annotation: PSPDFKit.FreeTextAnnotation) -> [CGRect] {
        guard annotation.rotation > 0 else { return [annotation.boundingBox] }
        let originalRotation = annotation.rotation
        annotation.setRotation(0, updateBoundingBox: true)
        let boundingBox = annotation.boundingBox.rounded(to: 3)
        annotation.setRotation(originalRotation, updateBoundingBox: true)
        return [boundingBox]
    }

    private static func createName(from displayName: String, username: String) -> String {
        if !displayName.isEmpty {
            return displayName
        }
        if !username.isEmpty {
            return username
        }
        return L10n.unknown
    }

    // MARK: - Zotero -> PSPDFKit

    /// Converts Zotero annotations to actual document (PSPDFKit) annotations with custom flags.
    /// - parameter zoteroAnnotations: Annotations to convert.
    /// - returns: Array of PSPDFKit annotations that can be added to document.
    static func annotations(
        from items: Results<RItem>,
        type: Kind = .zotero,
        interfaceStyle: UIUserInterfaceStyle,
        currentUserId: Int,
        library: Library,
        displayName: String,
        username: String,
        documentPageCount: UInt,
        boundingBoxConverter: AnnotationBoundingBoxConverter
    ) -> [PSPDFKit.Annotation] {
        return items.compactMap({ item in
            guard let dbAnnotation = PDFDatabaseAnnotation(item: item) else { return nil }
            guard dbAnnotation.page < documentPageCount else {
                DDLogWarn("AnnotationConverter: annotation \(item.key) for item \(item.parent?.key ?? ""); \(item.parent?.libraryId ?? .custom(.myLibrary)) has incorrect page index - \(dbAnnotation.page) / \(documentPageCount)")
                return nil
            }
            return annotation(
                from: dbAnnotation,
                type: type,
                interfaceStyle: interfaceStyle,
                currentUserId: currentUserId,
                library: library,
                displayName: displayName,
                username: username,
                boundingBoxConverter: boundingBoxConverter
            )
        })
    }

    static func annotation(
        from zoteroAnnotation: PDFDatabaseAnnotation,
        type: Kind,
        interfaceStyle: UIUserInterfaceStyle,
        currentUserId: Int,
        library: Library,
        displayName: String,
        username: String,
        boundingBoxConverter: AnnotationBoundingBoxConverter
    ) -> PSPDFKit.Annotation {
        let (color, alpha, blendMode) = AnnotationColorGenerator.color(
            from: UIColor(hex: zoteroAnnotation.color),
            isHighlight: (zoteroAnnotation.type == .highlight),
            userInterfaceStyle: interfaceStyle
        )
        let annotation: PSPDFKit.Annotation

        switch zoteroAnnotation.type {
        case .image:
            annotation = self.areaAnnotation(from: zoteroAnnotation, type: type, color: color, boundingBoxConverter: boundingBoxConverter)

        case .highlight:
            annotation = self.highlightAnnotation(from: zoteroAnnotation, type: type, color: color, alpha: alpha, boundingBoxConverter: boundingBoxConverter)

        case .note:
            annotation = self.noteAnnotation(from: zoteroAnnotation, type: type, color: color, boundingBoxConverter: boundingBoxConverter)

        case .ink:
            annotation = self.inkAnnotation(from: zoteroAnnotation, type: type, color: color, boundingBoxConverter: boundingBoxConverter)

        case .underline:
            annotation = self.underlineAnnotation(from: zoteroAnnotation, type: type, color: color, alpha: alpha, boundingBoxConverter: boundingBoxConverter)

        case .freeText:
            annotation = self.freeTextAnnotation(from: zoteroAnnotation, color: color, boundingBoxConverter: boundingBoxConverter)
        }

        switch type {
        case .export:
            annotation.customData = nil

        case .zotero:
            annotation.customData = [AnnotationsConfig.keyKey: zoteroAnnotation.key]

            if zoteroAnnotation.editability(currentUserId: currentUserId, library: library) != .editable {
                annotation.flags.update(with: .readOnly)
            }
        }

        if let blendMode {
            annotation.blendMode = blendMode
        }

        annotation.pageIndex = UInt(zoteroAnnotation.page)
        annotation.contents = zoteroAnnotation.comment
        annotation.user = zoteroAnnotation.author(displayName: displayName, username: username)
        annotation.name = "Zotero-\(zoteroAnnotation.key)"

        return annotation
    }

    /// Creates corresponding `SquareAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private static func areaAnnotation(from annotation: PDFAnnotation, type: Kind, color: UIColor, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.SquareAnnotation {
        let square: PSPDFKit.SquareAnnotation
        switch type {
        case .export:
            square = PSPDFKit.SquareAnnotation()

        case .zotero:
            square = SquareAnnotation()
        }

        square.boundingBox = annotation.boundingBox(boundingBoxConverter: boundingBoxConverter)
        square.borderColor = color
        square.lineWidth = AnnotationsConfig.imageAnnotationLineWidth

        return square
    }

    /// Creates corresponding `HighlightAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private static func highlightAnnotation(
        from annotation: PDFAnnotation,
        type: Kind,
        color: UIColor,
        alpha: CGFloat,
        boundingBoxConverter: AnnotationBoundingBoxConverter
    ) -> PSPDFKit.HighlightAnnotation {
        let highlight: PSPDFKit.HighlightAnnotation
        switch type {
        case .export:
            highlight = PSPDFKit.HighlightAnnotation()

        case .zotero:
            highlight = HighlightAnnotation()
        }

        highlight.rects = annotation.rects(boundingBoxConverter: boundingBoxConverter)
        highlight.boundingBox = annotation.boundingBox(rects: highlight.rects!)
        highlight.color = color
        highlight.alpha = alpha

        return highlight
    }

    /// Creates corresponding `NoteAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private static func noteAnnotation(from annotation: PDFAnnotation, type: Kind, color: UIColor, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.NoteAnnotation {
        let note: PSPDFKit.NoteAnnotation
        switch type {
        case .export:
            note = PSPDFKit.NoteAnnotation(contents: annotation.comment)

        case .zotero:
            note = NoteAnnotation(contents: annotation.comment)
        }

        let boundingBox = annotation.boundingBox(boundingBoxConverter: boundingBoxConverter)
        note.boundingBox = CGRect(origin: boundingBox.origin, size: AnnotationsConfig.noteAnnotationSize)
        note.borderStyle = .dashed
        note.color = color

        return note
    }

    private static func inkAnnotation(from annotation: PDFAnnotation, type: Kind, color: UIColor, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.InkAnnotation {
        let lines = annotation.paths(boundingBoxConverter: boundingBoxConverter).map({ group in
            return group.map({ DrawingPoint(cgPoint: $0) })
        })
        let ink = PSPDFKit.InkAnnotation(lines: lines)
        ink.color = color
        ink.lineWidth = annotation.lineWidth ?? 1
        return ink
    }

    private static func underlineAnnotation(
        from annotation: PDFAnnotation,
        type: Kind,
        color: UIColor,
        alpha: CGFloat,
        boundingBoxConverter: AnnotationBoundingBoxConverter
    ) -> PSPDFKit.UnderlineAnnotation {
        let underline: PSPDFKit.UnderlineAnnotation
        switch type {
        case .export:
            underline = PSPDFKit.UnderlineAnnotation()

        case .zotero:
            underline = UnderlineAnnotation()
        }

        underline.rects = annotation.rects(boundingBoxConverter: boundingBoxConverter)
        underline.boundingBox = annotation.boundingBox(rects: underline.rects!)
        underline.color = color
        underline.alpha = alpha

        return underline
    }

    private static func freeTextAnnotation(from annotation: PDFAnnotation, color: UIColor, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.FreeTextAnnotation {
        let text = PSPDFKit.FreeTextAnnotation(contents: annotation.comment)
        text.color = color
        text.fontSize = CGFloat(annotation.fontSize ?? 0)
        text.setBoundingBox(annotation.boundingBox(boundingBoxConverter: boundingBoxConverter), transformSize: true)
        text.setRotation(annotation.rotation ?? 0, updateBoundingBox: true)
        return text
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
