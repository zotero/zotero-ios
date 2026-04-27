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

    // MARK: - PSPDFKit -> Zotero

    /// Create Zotero annotation from existing PSPDFKit annotation.
    /// - parameter annotation: PSPDFKit annotation.
    /// - parameter color: Base color of annotation (can differ from current `PSPDPFKit.Annotation.color`)
    /// - parameter username: Username of current user.
    /// - parameter displayName: Display name of current user.
    /// - parameter boundingBoxConverter: Converts rects from pdf coordinate space.
    /// - returns: Matching Zotero annotation.
    static func annotation(
        from annotation: PSPDFKit.Annotation,
        color: String,
        username: String,
        displayName: String,
        defaultPageLabel: PDFReaderState.DefaultAnnotationPageLabel?,
        boundingBoxConverter: AnnotationBoundingBoxConverter?
    ) -> PDFDocumentAnnotation? {
        guard let document = annotation.document, AnnotationsConfig.supported.contains(annotation.type) else { return nil }

        let key = annotation.key ?? annotation.uuid
        let page = Int(annotation.pageIndex)
        let pageLabel = defaultPageLabel?.label(for: Int(annotation.pageIndex)) ?? document.pageLabelForPage(at: annotation.pageIndex, substituteWithPlainLabel: false) ?? "\(annotation.pageIndex + 1)"
        let isAuthor = annotation.user == displayName || annotation.user == username
        let comment = annotation.contents.flatMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) ?? ""
        let sortIndex = sortIndex(from: annotation, boundingBoxConverter: boundingBoxConverter)
        let date = Date()
        let dateAdded = annotation.creationDate ?? date
        let dateModified = annotation.lastModified ?? date

        let author = isAuthor ? createName(from: displayName, username: username) : (annotation.user ?? L10n.unknown)

        let type: AnnotationType
        let rects: [CGRect]
        var text: String?
        let paths: [[CGPoint]]
        var lineWidth: CGFloat?
        var fontSize: CGFloat?
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
            let roundedFontSize = AnnotationsConfig.roundFreeTextAnnotationFontSize(annotation.fontSize)
            fontSize = roundedFontSize
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
            dateAdded: dateAdded,
            dateModified: dateModified
        )

        /// Creates sort index from annotation and bounding box.
        /// - parameter annotation: PSPDFKit annotation from which sort index is created
        /// - parameter boundingBox; Bounding box converted to screen coordinates.
        /// - returns: Sort index (5 places for page, 6 places for character offset, 5 places for y position)
        func sortIndex(from annotation: PSPDFKit.Annotation, boundingBoxConverter: AnnotationBoundingBoxConverter?) -> String {
            let rect: CGRect
            if annotation is PSPDFKit.HighlightAnnotation || annotation is PSPDFKit.UnderlineAnnotation {
                rect = annotation.rects?.first ?? annotation.boundingBox
            } else {
                rect = annotation.boundingBox
            }

            let textOffset = boundingBoxConverter?.textOffset(rect: rect, page: annotation.pageIndex) ?? 0
            let minY = boundingBoxConverter?.sortIndexMinY(rect: rect, page: annotation.pageIndex).flatMap({ Int(round($0)) }) ?? 0
            if minY < 0 {
                DDLogWarn("AnnotationConverter: annotation \(String(describing: annotation.key)) has negative y position \(minY)")
            }
            return String(format: "%05d|%06d|%05d", annotation.pageIndex, textOffset, max(0, minY))
        }

        func createName(from displayName: String, username: String) -> String {
            if !displayName.isEmpty {
                return displayName
            } else if !username.isEmpty {
                return username
            }
            return L10n.unknown
        }
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
            return rects(fromNoteAnnotation: annotation)
        } else if annotation is PSPDFKit.HighlightAnnotation || annotation is PSPDFKit.UnderlineAnnotation {
            return rects(fromHighlightAndUnderlineAnnotation: annotation)
        } else if let annotation = annotation as? PSPDFKit.SquareAnnotation {
            return rects(fromSquareAnnotation: annotation)
        } else if let annotation = annotation as? PSPDFKit.FreeTextAnnotation {
            return rects(fromTextAnnotation: annotation)
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

    // MARK: - Zotero -> PSPDFKit

    /// Converts Zotero annotations to actual document (PSPDFKit) annotations with custom flags.
    /// - parameter zoteroAnnotations: Annotations to convert.
    /// - returns: Array of PSPDFKit annotations that can be added to document.
    static func annotations(
        from items: Results<RItem>,
        type: Kind = .zotero,
        appearance: Appearance,
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
                appearance: appearance,
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
        appearance: Appearance,
        currentUserId: Int,
        library: Library,
        displayName: String,
        username: String,
        boundingBoxConverter: AnnotationBoundingBoxConverter
    ) -> PSPDFKit.Annotation {
        let (color, alpha, blendMode) = AnnotationColorGenerator.color(from: UIColor(hex: zoteroAnnotation.color), type: zoteroAnnotation.type, appearance: appearance)
        let annotation: PSPDFKit.Annotation
        switch zoteroAnnotation.type {
        case .image:
            annotation = areaAnnotation(from: zoteroAnnotation, type: type, color: color, boundingBoxConverter: boundingBoxConverter)

        case .highlight:
            annotation = highlightAnnotation(from: zoteroAnnotation, type: type, color: color, alpha: alpha, boundingBoxConverter: boundingBoxConverter)

        case .note:
            annotation = noteAnnotation(from: zoteroAnnotation, type: type, color: color, boundingBoxConverter: boundingBoxConverter)

        case .ink:
            annotation = inkAnnotation(from: zoteroAnnotation, type: type, color: color, boundingBoxConverter: boundingBoxConverter)

        case .underline:
            annotation = underlineAnnotation(from: zoteroAnnotation, type: type, color: color, alpha: alpha, boundingBoxConverter: boundingBoxConverter)

        case .freeText:
            annotation = freeTextAnnotation(from: zoteroAnnotation, color: color, boundingBoxConverter: boundingBoxConverter)
        }

        switch type {
        case .export:
            annotation.customData = nil

        case .zotero:
            annotation.customData = [
                AnnotationsConfig.keyKey: zoteroAnnotation.key,
                AnnotationsConfig.baseColorKey: zoteroAnnotation.color
            ]

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

        func areaAnnotation(from annotation: PDFAnnotation, type: Kind, color: UIColor, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.SquareAnnotation {
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

        func highlightAnnotation(from annotation: PDFAnnotation, type: Kind, color: UIColor, alpha: CGFloat, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.HighlightAnnotation {
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

        func noteAnnotation(from annotation: PDFAnnotation, type: Kind, color: UIColor, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.NoteAnnotation {
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

        func inkAnnotation(from annotation: PDFAnnotation, type: Kind, color: UIColor, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.InkAnnotation {
            let lines = annotation.paths(boundingBoxConverter: boundingBoxConverter).map({ group in
                return group.map({ DrawingPoint(cgPoint: $0) })
            })
            let ink = PSPDFKit.InkAnnotation(lines: lines)
            ink.color = color
            ink.lineWidth = annotation.lineWidth ?? 1
            return ink
        }

        func underlineAnnotation(from annotation: PDFAnnotation, type: Kind, color: UIColor, alpha: CGFloat, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.UnderlineAnnotation {
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

        func freeTextAnnotation(from annotation: PDFAnnotation, color: UIColor, boundingBoxConverter: AnnotationBoundingBoxConverter) -> PSPDFKit.FreeTextAnnotation {
            let text = PSPDFKit.FreeTextAnnotation(contents: annotation.comment)
            text.color = color
            text.fontSize = CGFloat(annotation.fontSize ?? 0)
            text.setBoundingBox(annotation.boundingBox(boundingBoxConverter: boundingBoxConverter), transformSize: true)
            text.setRotation(annotation.rotation ?? 0, updateBoundingBox: true)
            return text
        }
    }

    static func annotation(
        from documentAnnotation: PDFDocumentAnnotation,
        appearance: Appearance,
        displayName: String,
        username: String
    ) -> PSPDFKit.Annotation {
        let (color, alpha, blendMode) = AnnotationColorGenerator.color(from: UIColor(hex: documentAnnotation.color), type: documentAnnotation.type, appearance: appearance)
        let annotation: PSPDFKit.Annotation

        switch documentAnnotation.type {
        case .image:
            let square = SquareAnnotation()
            square.boundingBox = documentAnnotation.boundingBox(rects: documentAnnotation.rects)
            square.borderColor = color
            square.lineWidth = AnnotationsConfig.imageAnnotationLineWidth
            annotation = square

        case .highlight:
            let highlight = HighlightAnnotation()
            highlight.rects = documentAnnotation.rects
            highlight.boundingBox = documentAnnotation.boundingBox(rects: documentAnnotation.rects)
            highlight.color = color
            highlight.alpha = alpha
            annotation = highlight

        case .note:
            let note = NoteAnnotation(contents: documentAnnotation.comment)
            let boundingBox = documentAnnotation.boundingBox(rects: documentAnnotation.rects)
            note.boundingBox = CGRect(origin: boundingBox.origin, size: AnnotationsConfig.noteAnnotationSize)
            note.borderStyle = .dashed
            note.color = color
            annotation = note

        case .ink:
            let lines = documentAnnotation.paths.map({ group in
                return group.map({ DrawingPoint(cgPoint: $0) })
            })
            let ink = PSPDFKit.InkAnnotation(lines: lines)
            ink.color = color
            ink.lineWidth = documentAnnotation.lineWidth ?? 1
            annotation = ink

        case .underline:
            let underline = UnderlineAnnotation()
            underline.rects = documentAnnotation.rects
            underline.boundingBox = documentAnnotation.boundingBox(rects: documentAnnotation.rects)
            underline.color = color
            underline.alpha = alpha
            annotation = underline

        case .freeText:
            let text = PSPDFKit.FreeTextAnnotation(contents: documentAnnotation.comment)
            text.color = color
            text.fontSize = CGFloat(documentAnnotation.fontSize ?? 0)
            text.setBoundingBox(documentAnnotation.boundingBox(rects: documentAnnotation.rects), transformSize: true)
            text.setRotation(documentAnnotation.rotation ?? 0, updateBoundingBox: true)
            annotation = text
        }

        if let blendMode {
            annotation.blendMode = blendMode
        }

        annotation.pageIndex = UInt(documentAnnotation.page)
        annotation.contents = documentAnnotation.comment
        annotation.user = documentAnnotation.author(displayName: displayName, username: username)
        annotation.customData = [
            AnnotationsConfig.keyKey: documentAnnotation.key,
            AnnotationsConfig.baseColorKey: documentAnnotation.color
        ]
        annotation.name = "Zotero-\(documentAnnotation.key)"

        return annotation
    }
}
