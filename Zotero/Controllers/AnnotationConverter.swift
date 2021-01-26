//
//  AnnotationConverter.swift
//  Zotero
//
//  Created by Michal Rentka on 25.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

#if PDFENABLED

import PSPDFKit

struct AnnotationConverter {
    enum Style {
        case `default`
        case zotero
    }

    // MARK: - Helpers

    static func sortIndex(from annotation: PSPDFKit.Annotation) -> String {
        return self.sortIndex(for: annotation.boundingBox, pageIndex: annotation.pageIndex)
    }

    static func sortIndex(for rect: CGRect, pageIndex: PageIndex) -> String {
        let yPos = Int(round(rect.origin.y))
        return String(format: "%05d|%06d|%05d", pageIndex, 0, yPos)
    }

    // MARK: - PSPDFKit -> Zotero

    /// Create Zotero annotation from existing PSPDFKit annotation.
    /// - parameter annotation: PSPDFKit annotation.
    /// - parameter isNew: Indicating, whether the annotation has just been created.
    /// - returns: Matching Zotero annotation.
    static func annotation(from annotation: PSPDFKit.Annotation, isNew: Bool, username: String) -> Annotation? {
        guard let document = annotation.document, AnnotationsConfig.supported.contains(annotation.type) else { return nil }

        let page = Int(annotation.pageIndex)
        let pageLabel = document.pageLabelForPage(at: annotation.pageIndex, substituteWithPlainLabel: false) ?? "\(annotation.pageIndex + 1)"
        let author = isNew ? username : (annotation.user ?? "")
        let isAuthor = isNew ? true : (annotation.user == username)
        let comment = annotation.contents.flatMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) ?? ""
        let color = annotation.color?.hexString ?? AnnotationsConfig.defaultActiveColor
        let sortIndex = self.sortIndex(from: annotation)
        let date = Date()

        if let annotation = annotation as? NoteAnnotation {
            return Annotation(key: KeyGenerator.newKey, type: .note, page: page, pageLabel: pageLabel, rects: [annotation.boundingBox], author: author, isAuthor: isAuthor, color: color,
                              comment: comment, text: nil, isLocked: false, sortIndex: sortIndex, dateModified: date, tags: [], didChange: isNew, editableInDocument: true)
        }

        if let annotation = annotation as? HighlightAnnotation {
            return Annotation(key: KeyGenerator.newKey, type: .highlight, page: page, pageLabel: pageLabel, rects: (annotation.rects ?? [annotation.boundingBox]), author: author, isAuthor: isAuthor,
                              color: color, comment: comment, text: annotation.markedUpString.trimmingCharacters(in: .whitespacesAndNewlines), isLocked: false, sortIndex: sortIndex,
                              dateModified: date, tags: [], didChange: isNew, editableInDocument: true)
        }

        if let annotation = annotation as? SquareAnnotation {
            return Annotation(key: KeyGenerator.newKey, type: .image, page: page, pageLabel: pageLabel, rects: [annotation.boundingBox], author: author, isAuthor: isAuthor, color: color,
                              comment: comment, text: nil, isLocked: false, sortIndex: sortIndex, dateModified: date, tags: [], didChange: isNew, editableInDocument: true)
        }

        return nil
    }

    // MARK: - Zotero -> PSPDFKit

    /// Converts Zotero annotations to actual document (PSPDFKit) annotations with custom flags.
    /// - parameter zoteroAnnotations: Annotations to convert.
    /// - returns: Array of PSPDFKit annotations that can be added to document.
    static func annotations(from zoteroAnnotations: [Int: [Annotation]], style: Style = .zotero, interfaceStyle: UIUserInterfaceStyle) -> [PSPDFKit.Annotation] {
        return zoteroAnnotations.values.flatMap({ $0 }).map({
            return self.annotation(from: $0, style: style, interfaceStyle: interfaceStyle)
        })
    }

    static func annotation(from zoteroAnnotation: Annotation, style: Style, interfaceStyle: UIUserInterfaceStyle) -> PSPDFKit.Annotation {
        switch zoteroAnnotation.type {
        case .image:
            return self.areaAnnotation(from: zoteroAnnotation, style: style, interfaceStyle: interfaceStyle)
        case .highlight:
            return self.highlightAnnotation(from: zoteroAnnotation, style: style, interfaceStyle: interfaceStyle)
        case .note:
            return self.noteAnnotation(from: zoteroAnnotation, style: style, interfaceStyle: interfaceStyle)
        }
    }

    /// Creates corresponding `SquareAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private static func areaAnnotation(from annotation: Annotation, style: Style, interfaceStyle: UIUserInterfaceStyle) -> PSPDFKit.SquareAnnotation {
        let square: PSPDFKit.SquareAnnotation

        switch style {
        case .default:
            square = PSPDFKit.SquareAnnotation()
        case .zotero:
            square = SquareAnnotation()
        }

        square.pageIndex = UInt(annotation.page)
        square.boundingBox = annotation.boundingBox
        square.borderColor = AnnotationColorGenerator.color(from: UIColor(hex: annotation.color), isHighlight: false, userInterfaceStyle: interfaceStyle).color
        square.contents = annotation.comment
        square.isZotero = true
        square.isEditable = annotation.editableInDocument
        square.baseColor = annotation.color
        square.key = annotation.key
        square.user = annotation.author
        square.name = "Zotero-\(annotation.key)"
        return square
    }

    /// Creates corresponding `HighlightAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private static func highlightAnnotation(from annotation: Annotation, style: Style, interfaceStyle: UIUserInterfaceStyle) -> PSPDFKit.HighlightAnnotation {
        let (color, alpha) = AnnotationColorGenerator.color(from: UIColor(hex: annotation.color), isHighlight: true, userInterfaceStyle: interfaceStyle)
        let highlight: PSPDFKit.HighlightAnnotation

        switch style {
        case .default:
            highlight = PSPDFKit.HighlightAnnotation()
        case .zotero:
            highlight = HighlightAnnotation()
        }

        highlight.pageIndex = UInt(annotation.page)
        highlight.boundingBox = annotation.boundingBox
        highlight.rects = annotation.rects
        highlight.color = color
        highlight.alpha = alpha
        highlight.contents = annotation.comment
        highlight.isZotero = true
        highlight.isEditable = annotation.editableInDocument
        highlight.baseColor = annotation.color
        highlight.key = annotation.key
        highlight.user = annotation.author
        highlight.name = "Zotero-\(annotation.key)"
        return highlight
    }

    /// Creates corresponding `NoteAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private static func noteAnnotation(from annotation: Annotation, style: Style, interfaceStyle: UIUserInterfaceStyle) -> PSPDFKit.NoteAnnotation {
        let note: PSPDFKit.NoteAnnotation

        switch style {
        case .default:
            note = PSPDFKit.NoteAnnotation(contents: annotation.comment)
        case .zotero:
            note = NoteAnnotation(contents: annotation.comment)
        }

        note.pageIndex = UInt(annotation.page)
        let boundingBox = annotation.boundingBox
        note.boundingBox = CGRect(origin: boundingBox.origin, size: PDFReaderLayout.noteAnnotationSize)
        note.contents = annotation.comment
        note.isZotero = true
        note.isEditable = annotation.editableInDocument
        note.key = annotation.key
        note.borderStyle = .dashed
        note.color = AnnotationColorGenerator.color(from: UIColor(hex: annotation.color), isHighlight: false, userInterfaceStyle: interfaceStyle).color
        note.baseColor = annotation.color
        note.user = annotation.author
        note.name = "Zotero-\(annotation.key)"
        return note
    }
}

#endif
