//
//  PDFReaderActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import Foundation

import CocoaLumberjack
import PSPDFKit
import RxSwift

struct PDFReaderActionHandler: ViewModelActionHandler {
    typealias Action = PDFReaderAction
    typealias State = PDFReaderState

    private let disposeBag: DisposeBag

    init() {
        self.disposeBag = DisposeBag()
    }

    func process(action: PDFReaderAction, in viewModel: ViewModel<PDFReaderActionHandler>) {
        switch action {
        case .loadAnnotations:
            /// TMP/TODO: - Import annotations only when needed/requested by user
            let zoteroAnnotations = self.annotations(from: viewModel.state.document)

            let documentAnnotations = viewModel.state.document.allAnnotations(of: PDFReaderState.supportedAnnotations)
            let annotations = self.annotations(from: zoteroAnnotations)
            self.update(viewModel: viewModel) { state in
                state.annotations = zoteroAnnotations

                // Hide external supported annotations
                documentAnnotations.values.flatMap({ $0 }).forEach({ $0.isHidden = true })
                // Add zotero annotations
                state.document.add(annotations: annotations, options: nil)
            }

        case .cleanupAnnotations:
            let zoteroAnnotations = viewModel.state.document.allAnnotations(of: PDFReaderState.supportedAnnotations)
                                                            .values
                                                            .flatMap({ $0 })
                                                            .filter({ ($0.customData?[PDFReaderState.zoteroAnnotationKey] as? Bool) == true })
            viewModel.state.document.remove(annotations: zoteroAnnotations, options: nil)
        }
    }

    /// Temporary extraction of original annotations and converting them to zotero annotations. This will actually happen only when the user
    /// imports annotations manually, with some changes.
    private func annotations(from document: Document) -> [Int: [Annotation]] {
        let annotations = document.allAnnotations(of: PDFReaderState.supportedAnnotations)
        var zoteroAnnotations: [Int: [Annotation]] = [:]
        for (page, annotations) in annotations {
            zoteroAnnotations[page.intValue] = self.zoteroAnnotations(from: annotations)
        }
        return zoteroAnnotations
    }

    private func zoteroAnnotations(from annotations: [PSPDFKit.Annotation]) -> [Annotation] {
        return annotations.compactMap { annotation in
            guard PDFReaderState.supportedAnnotations.contains(annotation.type) else { return nil }

            if let annotation = annotation as? NoteAnnotation {
                return Annotation(key: KeyGenerator.newKey,
                                  type: .note,
                                  page: Int(annotation.pageIndex),
                                  pageLabel: "\(annotation.pageIndex)",
                                  rects: [annotation.boundingBox],
                                  author: "",
                                  isAuthor: true,
                                  color: annotation.color?.hexString ?? "#E1AD01",
                                  comment: (annotation.contents ?? ""),
                                  text: nil,
                                  isLocked: annotation.isLocked,
                                  sortIndex: "",
                                  dateModified: Date(),
                                  tags: [])
            } else if let annotation = annotation as? HighlightAnnotation {
                return Annotation(key: KeyGenerator.newKey,
                                  type: .highlight,
                                  page: Int(annotation.pageIndex),
                                  pageLabel: "\(annotation.pageIndex)",
                                  rects: annotation.rects ?? [annotation.boundingBox],
                                  author: "",
                                  isAuthor: true,
                                  color: annotation.color?.hexString ?? "#E1AD01",
                                  comment: "",
                                  text: annotation.markedUpString,
                                  isLocked: annotation.isLocked,
                                  sortIndex: "",
                                  dateModified: Date(),
                                  tags: [])
            } else if let annotation = annotation as? SquareAnnotation {
                return Annotation(key: KeyGenerator.newKey,
                                  type: .area,
                                  page: Int(annotation.pageIndex),
                                  pageLabel: "\(annotation.pageIndex)",
                                  rects: [annotation.boundingBox],
                                  author: "",
                                  isAuthor: true,
                                  color: annotation.color?.hexString ?? "#E1AD01",
                                  comment: "",
                                  text: nil,
                                  isLocked: annotation.isLocked,
                                  sortIndex: "",
                                  dateModified: Date(),
                                  tags: [])
            }

            return nil
        }
    }

    /// Add zotero annotations to Document with custom flag, so that we can recognize them
    private func annotations(from zoteroAnnotations: [Int: [Annotation]]) -> [PSPDFKit.Annotation] {
        return zoteroAnnotations.values.flatMap({ $0 }).map({
            switch $0.type {
            case .area:
                return self.areaAnnotation(from: $0)
            case .highlight:
                return self.highlightAnnotation(from: $0)
            case .note:
                return self.noteAnnotation(from: $0)
            }
        })
    }

    private func areaAnnotation(from annotation: Annotation) -> SquareAnnotation {
        let square = SquareAnnotation()
        square.pageIndex = UInt(annotation.page)
        square.boundingBox = annotation.boundingBox
        square.borderColor = UIColor(hex: annotation.color)
        square.customData = [PDFReaderState.zoteroAnnotationKey: true]
        return square
    }

    private func highlightAnnotation(from annotation: Annotation) -> HighlightAnnotation {
        let highlight = HighlightAnnotation()
        highlight.pageIndex = UInt(annotation.page)
        highlight.boundingBox = annotation.boundingBox
        highlight.rects = annotation.rects
        highlight.color = UIColor(hex: annotation.color)
        highlight.customData = [PDFReaderState.zoteroAnnotationKey: true]
        return highlight
    }

    private func noteAnnotation(from annotation: Annotation) -> NoteAnnotation {
        let note = NoteAnnotation(contents: annotation.comment)
        note.pageIndex = UInt(annotation.page)
        let boundingBox = annotation.boundingBox
        note.boundingBox = CGRect(x: boundingBox.minX, y: boundingBox.minY, width: 32, height: 32)
        note.customData = [PDFReaderState.zoteroAnnotationKey: true]
        return note
    }
}

#endif
