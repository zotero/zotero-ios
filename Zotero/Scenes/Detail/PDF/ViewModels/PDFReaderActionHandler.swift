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

    private let annotationPreviewController: AnnotationPreviewController
    private let disposeBag: DisposeBag

    init(annotationPreviewController: AnnotationPreviewController) {
        self.annotationPreviewController = annotationPreviewController
        self.disposeBag = DisposeBag()
    }

    func process(action: PDFReaderAction, in viewModel: ViewModel<PDFReaderActionHandler>) {
        switch action {
        case .loadAnnotations:
            self.loadAnnotations(in: viewModel)

        case .startObservingAnnotationChanges:
            self.observePreviews(in: viewModel)

        case .searchAnnotations(let term):
            self.searchAnnotations(with: term, in: viewModel)

        case .selectAnnotation(let annotation):
            let index = annotation.flatMap({ annotation in
                viewModel.state.annotations[annotation.page]?.firstIndex(where: { annotation.key == $0.key })
            })
            self.select(annotation: annotation, index: index, didSelectInDocument: false, in: viewModel)

        case .selectAnnotationFromDocument(let key, let page):
            guard let index = viewModel.state.annotations[page]?.firstIndex(where: { $0.key == key }) else { return }
            let annotation = viewModel.state.annotations[page]?[index]
            self.select(annotation: annotation, index: index, didSelectInDocument: true, in: viewModel)

        case .annotationChanged(let annotation):
            self.update(annotation: annotation, in: viewModel)
            
        case .annotationsAdded(let annotations):
            self.add(annotations: annotations, in: viewModel)

        case .annotationsRemoved(let annotations):
            self.remove(annotations: annotations, in: viewModel)

        case .removeAnnotation(let annotation):
            self.remove(annotation: annotation, in: viewModel)

        case .requestPreviews(let keys, let notify):
            self.loadPreviews(for: keys, notify: notify, in: viewModel)
        }
    }

    // MARK: - Annotation actions

    /// Removes Zotero annotation from document.
    /// - parameter annotation: Annotation to remove.
    /// - parameter viewModel: ViewModel.
    private func remove(annotation: Annotation, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let documentAnnotation = viewModel.state.document.annotations(at: UInt(annotation.page))
                                                               .first(where: { $0.key == annotation.key }) else { return }
        viewModel.state.document.remove(annotations: [documentAnnotation], options: nil)
    }

    /// Searches through annotations and updates view with results.
    /// - parameter term: If empty, search filter is removed. Otherwise applies search filter based on value.
    /// - parameter viewModel: ViewModel.
    private func searchAnnotations(with term: String, in viewModel: ViewModel<PDFReaderActionHandler>) {
        if term.isEmpty {
            self.removeAnnotationFilter(in: viewModel)
        } else {
            self.filterAnnotations(with: term, in: viewModel)
        }
    }

    /// Filters annotations based on given term.
    /// - parameter term: Term to filter annotations.
    /// - parameter viewModel: ViewModel.
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

    /// Removes search filter.
    /// - parameter viewModel: ViewModel.
    private func removeAnnotationFilter(in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let snapshot = viewModel.state.annotationsSnapshot else { return }
        self.update(viewModel: viewModel) { state in
            state.annotationsSnapshot = nil
            state.annotations = snapshot
            state.changes = .annotations
        }
    }

    /// Set selected annotation. Also sets `focusSidebarLocation` or `focusDocumentLocation` if needed.
    /// - parameter annotation: Annotation to be selected. Deselects current annotation if `nil`.
    /// - parameter index: Index of annotation in annotations array on given page.
    /// - parameter didSelectInDocument: `true` if annotation was selected in document, false if it was selected in sidebar.
    /// - parameter viewModel: ViewModel.
    private func select(annotation: Annotation?, index: Int?, didSelectInDocument: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if let existing = state.selectedAnnotation,
               let index = state.annotations[existing.page]?.firstIndex(where: { $0.key == existing.key }) {
                state.updatedAnnotationIndexPaths = [IndexPath(row: index, section: existing.page)]
            }

            if let annotation = annotation, let index = index {
                if !didSelectInDocument {
                    state.focusDocumentLocation = (annotation.page, annotation.boundingBox)
                } else {
                    state.focusSidebarLocation = (index, annotation.page)
                }

                var indexPaths = state.updatedAnnotationIndexPaths ?? []
                indexPaths.append(IndexPath(row: index, section: annotation.page))
                state.updatedAnnotationIndexPaths = indexPaths
            }

            state.selectedAnnotation = annotation
            state.changes = .selection
        }
    }

    // MARK: - Annotation previews

    /// Starts observing preview controller. If new preview is stored, it will be cached immediately.
    /// - parameter viewModel: ViewModel.
    private func observePreviews(in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.annotationPreviewController.observable
                                        .observeOn(MainScheduler.instance)
                                        .subscribe(onNext: { [weak viewModel] annotationKey, parentKey, image in
                                            guard let viewModel = viewModel, viewModel.state.key == parentKey else { return }
                                            self.update(viewModel: viewModel) { state in
                                                state.previewCache.setObject(image, forKey: (annotationKey as NSString))
                                                state.changes = .annotations
                                            }
                                        })
                                        .disposed(by: self.disposeBag)
    }

    /// Loads previews for given keys and notifies view about them if needed.
    /// - parameter keys: Keys that should load previews.
    /// - parameter notify: If `true`, index paths for loaded images will be found and view will be notified about changes.
    ///                     If `false`, images are loaded and no notification is sent.
    /// - parameter viewModel: ViewModel.
    private func loadPreviews(for keys: [String], notify: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let group = DispatchGroup()

        var loadedKeys: Set<String> = []

        for key in keys {
            let nsKey = key as NSString
            guard viewModel.state.previewCache.object(forKey: nsKey) == nil else { continue }

            group.enter()
            self.annotationPreviewController.preview(for: key, parentKey: viewModel.state.key) { [weak viewModel] image in
                if let image = image {
                    viewModel?.state.previewCache.setObject(image, forKey: nsKey)
                    loadedKeys.insert(key)
                }
                group.leave()
            }
        }

        guard notify else { return }

        group.notify(queue: .main) { [weak viewModel] in
            guard let viewModel = viewModel else { return }
            self.update(viewModel: viewModel) { state in
                state.updatedAnnotationIndexPaths = self.indexPaths(for: loadedKeys, in: viewModel.state.annotations)
            }
        }
    }

    /// Finds index paths for given keys in annotations.
    /// - parameter keys: Keys for which index paths are needed.
    /// - parameter annotations: All annotations in document.
    /// - returns: Found index paths.
    private func indexPaths(for keys: Set<String>, in annotations: [Int: [Annotation]]) -> [IndexPath] {
        var indexPaths: [IndexPath] = []
        var remainingKeys = keys

        for (page, pageAnnotations) in annotations {
            for (index, annotation) in pageAnnotations.enumerated() {
                guard remainingKeys.contains(annotation.key) else { continue }

                indexPaths.append(IndexPath(row: index, section: page))
                remainingKeys.remove(annotation.key)

                if remainingKeys.isEmpty {
                    break
                }
            }

            if remainingKeys.isEmpty {
                return indexPaths
            }
        }

        return indexPaths
    }

    // MARK: - Annotation management

    /// Updates annotations based on insertions to PSPDFKit document.
    /// - parameter annotations: Annotations that were added to the document.
    /// - parameter viewModel: ViewModel.
    private func add(annotations: [PSPDFKit.Annotation], in viewModel: ViewModel<PDFReaderActionHandler>) {
        var newZoteroAnnotations: [Annotation] = []

        for annotation in annotations {
            if annotation.isZotero {
                guard let annotation = annotation as? SquareAnnotation else { continue }
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key)
                continue
            }

            guard let zoteroAnnotation = self.zoteroAnnotation(from: annotation) else { continue }

            newZoteroAnnotations.append(zoteroAnnotation)
            annotation.customData = [AnnotationsConfig.isZoteroKey: true,
                                     AnnotationsConfig.keyKey: zoteroAnnotation.key]

            if let annotation = annotation as? SquareAnnotation {
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key)
            }
        }

        self.update(viewModel: viewModel) { state in
            var focus: AnnotationSidebarLocation?

            for annotation in newZoteroAnnotations {
                guard let index = state.annotations[annotation.page]?.index(of: annotation, sortedBy: { $0.sortIndex > $1.sortIndex }) else { return }

                state.annotations[annotation.page]?.insert(annotation, at: index)

                if focus == nil {
                    focus = (index, annotation.page)
                }
            }

            state.focusSidebarLocation = focus
            state.changes = .annotations
        }
    }

    /// Updates annotations based on deletions of PSPDFKit annotations in document.
    /// - parameter annotations: Annotations that were deleted in document.
    /// - parameter viewModel: ViewModel.
    private func remove(annotations: [PSPDFKit.Annotation], in viewModel: ViewModel<PDFReaderActionHandler>) {
        var toDelete: [(String, Int, Int)] = []

        for annotation in annotations {
            guard annotation.isZotero,
                  let key = annotation.key else { continue }

            if let annotation = annotation as? SquareAnnotation {
                self.annotationPreviewController.delete(for: annotation, parentKey: viewModel.state.key)
            }

            let page = Int(annotation.pageIndex)
            if let index = viewModel.state.annotations[page]?.firstIndex(where: { $0.key == key }) {
                toDelete.append((key, index, page))
            }
        }

        self.update(viewModel: viewModel) { state in
            for location in toDelete {
                state.annotations[location.2]?.remove(at: location.1)
                if state.selectedAnnotation?.key == location.0 {
                    state.selectedAnnotation = nil
                    state.changes.insert(.selection)
                }
            }
            state.changes.insert(.annotations)
        }
    }

    /// Updates corresponding Zotero annotation to updated PSPDFKit annotation in document.
    /// - parameter annotation: Updated PSPDFKit annotation.
    /// - parameter viewModel: ViewModel.
    private func update(annotation: PSPDFKit.Annotation, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = annotation as? SquareAnnotation,
              annotation.isZotero else { return }
        // TODO: - check if order changed
        self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key)
    }

    /// Loads annotations from DB (TODO), converts them to Zotero annotations and adds matching PSPDFKit annotations to document.
    private func loadAnnotations(in viewModel: ViewModel<PDFReaderActionHandler>) {
        /// TMP/TODO: - Import annotations only when needed/requested by user
        let zoteroAnnotations = self.annotations(from: viewModel.state.document)

        let documentAnnotations = viewModel.state.document.allAnnotations(of: AnnotationsConfig.supported)
        let annotations = self.annotations(from: zoteroAnnotations)

        self.update(viewModel: viewModel) { state in
            state.annotations = zoteroAnnotations
            state.changes = .annotations

            UndoController.performWithoutUndo(undoController: state.document.undoController) {
                // Hide external supported annotations
                documentAnnotations.values.flatMap({ $0 }).forEach({ $0.isHidden = true })
                // Add zotero annotations
                state.document.add(annotations: annotations, options: nil)
            }
        }
    }

    /// Temporary extraction of original annotations and converting them to zotero annotations. This will actually happen only when the user
    /// imports annotations manually, with some changes.
    private func annotations(from document: Document) -> [Int: [Annotation]] {
        let annotations = document.allAnnotations(of: AnnotationsConfig.supported)
        var zoteroAnnotations: [Int: [Annotation]] = [:]
        for (page, annotations) in annotations {
            zoteroAnnotations[page.intValue] = annotations.compactMap { self.zoteroAnnotation(from: $0) }.sorted(by: { $0.sortIndex > $1.sortIndex })
        }
        return zoteroAnnotations
    }

    /// Create Zotero annotation from existing PSPDFKit annotation.
    /// - parameter annotation: PSPDFKit annotation.
    /// - returns: Matching Zotero annotation.
    private func zoteroAnnotation(from annotation: PSPDFKit.Annotation) -> Annotation? {
        guard AnnotationsConfig.supported.contains(annotation.type) else { return nil }

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

    /// Converts Zotero annotations to actual document (PSPDFKit) annotations with custom flags.
    /// - parameter zoteroAnnotations: Annotations to convert.
    /// - returns: Array of PSPDFKit annotations that can be added to document.
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

    /// Creates corresponding `SquareAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private func areaAnnotation(from annotation: Annotation) -> SquareAnnotation {
        let square = SquareAnnotation()
        square.pageIndex = UInt(annotation.page)
        square.boundingBox = annotation.boundingBox
        square.borderColor = UIColor(hex: annotation.color)
        square.isZotero = true
        square.key = annotation.key
        return square
    }

    /// Creates corresponding `HighlightAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private func highlightAnnotation(from annotation: Annotation) -> HighlightAnnotation {
        let highlight = HighlightAnnotation()
        highlight.pageIndex = UInt(annotation.page)
        highlight.boundingBox = annotation.boundingBox
        highlight.rects = annotation.rects
        highlight.color = UIColor(hex: annotation.color)
        highlight.isZotero = true
        highlight.key = annotation.key
        return highlight
    }

    /// Creates corresponding `NoteAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private func noteAnnotation(from annotation: Annotation) -> NoteAnnotation {
        let note = NoteAnnotation(contents: annotation.comment)
        note.pageIndex = UInt(annotation.page)
        let boundingBox = annotation.boundingBox
        note.boundingBox = CGRect(x: boundingBox.minX, y: boundingBox.minY, width: 32, height: 32)
        note.isZotero = true
        note.key = annotation.key
        note.borderStyle = .dashed
        return note
    }
}

#endif
