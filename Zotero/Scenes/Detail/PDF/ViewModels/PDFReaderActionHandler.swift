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
            self.loadAnnotations(in: viewModel)

        case .searchAnnotations(let term):
            self.searchAnnotations(with: term, in: viewModel)

        case .selectAnnotation(let annotation):
            self.select(annotation: annotation, shouldSelectInDocument: true, in: viewModel)

        case .selectAnnotationFromDocument(let key, let page):
            let annotation = viewModel.state.annotations[page]?.first(where: { $0.key == key })
            self.select(annotation: annotation, shouldSelectInDocument: false, in: viewModel)

        }
    }

    private func searchAnnotations(with term: String, in viewModel: ViewModel<PDFReaderActionHandler>) {
        if term.isEmpty {
            self.removeAnnotationFilter(in: viewModel)
        } else {
            self.filterAnnotations(with: term, in: viewModel)
        }
    }

    private func filterAnnotations(with term: String, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let snapshot = viewModel.state.annotationsSnapshot ?? viewModel.state.annotations
        var annotations = snapshot
        for (page, pageAnnotations) in snapshot {
            annotations[page] = pageAnnotations.filter({ ann in
                return ann.author.localizedCaseInsensitiveContains(term) ||
                       ann.comment.localizedCaseInsensitiveContains(term) ||
                       (ann.text ?? "").localizedCaseInsensitiveContains(term) ||
                       ann.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(term) })
            })
        }

        self.update(viewModel: viewModel) { state in
            if state.annotationsSnapshot == nil {
                state.annotationsSnapshot = state.annotations
            }
            state.annotations = annotations
            state.changes = .annotations
        }
    }

    private func removeAnnotationFilter(in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let snapshot = viewModel.state.annotationsSnapshot else { return }
        self.update(viewModel: viewModel) { state in
            state.annotationsSnapshot = nil
            state.annotations = snapshot
            state.changes = .annotations
        }
    }

    private func select(annotation: Annotation?, shouldSelectInDocument: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.selectedAnnotation = annotation

            if let highlight = state.highlightSelectionAnnotation {
                state.document.remove(annotations: [highlight], options: nil)
            }

            if let annotation = annotation {
                // HighlightAnnotation always needs selection annotation
                if annotation.type == .highlight {
                    let selection = self.createHighlightSelectionAnnotation()
                    selection.pageIndex = UInt(annotation.page)
                    selection.boundingBox = annotation.boundingBox.insetBy(dx: -5, dy: -5)
                    state.highlightSelectionAnnotation = selection
                    state.document.add(annotations: [selection], options: nil)
                }

                if shouldSelectInDocument {
                    state.focusLocation = (annotation.page, annotation.boundingBox)
                }
            }

            state.changes = .annotations
        }
    }

    private func loadAnnotations(in viewModel: ViewModel<PDFReaderActionHandler>) {
        /// TMP/TODO: - Import annotations only when needed/requested by user
        let zoteroAnnotations = self.annotations(from: viewModel.state.document)

        let documentAnnotations = viewModel.state.document.allAnnotations(of: PDFReaderState.supportedAnnotations)
        let annotations = self.annotations(from: zoteroAnnotations)
        self.update(viewModel: viewModel) { state in
            state.annotations = zoteroAnnotations
            state.changes = .annotations

            // Hide external supported annotations
            documentAnnotations.values.flatMap({ $0 }).forEach({ $0.isHidden = true })
            // Add zotero annotations
            state.document.add(annotations: annotations, options: nil)
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
                                  pageLabel: "\(annotation.pageIndex + 1)",
                                  rects: [annotation.boundingBox],
                                  author: "",
                                  isAuthor: true,
                                  color: annotation.color?.hexString ?? "#E1AD01",
                                  comment: (annotation.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                  text: nil,
                                  isLocked: annotation.isLocked,
                                  sortIndex: "",
                                  dateModified: Date(),
                                  tags: [])
            } else if let annotation = annotation as? HighlightAnnotation {
                return Annotation(key: KeyGenerator.newKey,
                                  type: .highlight,
                                  page: Int(annotation.pageIndex),
                                  pageLabel: "\(annotation.pageIndex + 1)",
                                  rects: annotation.rects ?? [annotation.boundingBox],
                                  author: "",
                                  isAuthor: true,
                                  color: annotation.color?.hexString ?? "#E1AD01",
                                  comment: "",
                                  text: annotation.markedUpString.trimmingCharacters(in: .whitespacesAndNewlines),
                                  isLocked: annotation.isLocked,
                                  sortIndex: "",
                                  dateModified: Date(),
                                  tags: [])
            } else if let annotation = annotation as? SquareAnnotation {
                return Annotation(key: KeyGenerator.newKey,
                                  type: .area,
                                  page: Int(annotation.pageIndex),
                                  pageLabel: "\(annotation.pageIndex + 1)",
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
        square.customData = [PDFReaderState.zoteroAnnotationKey: true,
                             PDFReaderState.zoteroKeyKey: annotation.key]
        return square
    }

    private func highlightAnnotation(from annotation: Annotation) -> HighlightAnnotation {
        let highlight = HighlightAnnotation()
        highlight.pageIndex = UInt(annotation.page)
        highlight.boundingBox = annotation.boundingBox
        highlight.rects = annotation.rects
        highlight.color = UIColor(hex: annotation.color)
        highlight.customData = [PDFReaderState.zoteroAnnotationKey: true,
                                PDFReaderState.zoteroKeyKey: annotation.key]
        return highlight
    }

    private func noteAnnotation(from annotation: Annotation) -> NoteAnnotation {
        let note = NoteAnnotation(contents: annotation.comment)
        note.pageIndex = UInt(annotation.page)
        let boundingBox = annotation.boundingBox
        note.boundingBox = CGRect(x: boundingBox.minX, y: boundingBox.minY, width: 32, height: 32)
        note.customData = [PDFReaderState.zoteroAnnotationKey: true,
                           PDFReaderState.zoteroKeyKey: annotation.key]
        note.borderStyle = .dashed
        return note
    }

    private func createHighlightSelectionAnnotation() -> SquareAnnotation {
        let annotation = SquareAnnotation()
        annotation.borderColor = UIColor(hex: "#6495ed")
        annotation.dashArray = [4]
        annotation.borderStyle = .dashed
        annotation.lineWidth = 1.8
        annotation.customData = [PDFReaderState.zoteroAnnotationKey: true,
                                 PDFReaderState.zoteroHighlightKey: true]
        return annotation
    }
}

#endif
