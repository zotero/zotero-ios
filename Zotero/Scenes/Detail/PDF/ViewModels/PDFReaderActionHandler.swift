//
//  PDFReaderActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import RxSwift

struct PDFReaderActionHandler: ViewModelActionHandler {
    typealias Action = PDFReaderAction
    typealias State = PDFReaderState

    fileprivate struct PdfAnnotationChanges: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let color = PdfAnnotationChanges(rawValue: 1 << 0)
        static let comment = PdfAnnotationChanges(rawValue: 1 << 1)

        static func stringValues(from changes: PdfAnnotationChanges) -> [String] {
            switch changes {
            case .color: return ["alpha", "color"]
            case .comment: return ["contents"]
            default: return []
            }
        }
    }

    private unowned let dbStorage: DbStorage
    private unowned let annotationPreviewController: AnnotationPreviewController
    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    private unowned let schemaController: SchemaController
    private unowned let fileStorage: FileStorage
    private let queue: DispatchQueue
    private let disposeBag: DisposeBag

    init(dbStorage: DbStorage, annotationPreviewController: AnnotationPreviewController, htmlAttributedStringConverter: HtmlAttributedStringConverter,
         schemaController: SchemaController, fileStorage: FileStorage) {
        self.dbStorage = dbStorage
        self.annotationPreviewController = annotationPreviewController
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.schemaController = schemaController
        self.fileStorage = fileStorage
        self.queue = DispatchQueue(label: "org.zotero.Zotero.PDFReaderActionHandler.queue", qos: .userInteractive)
        self.disposeBag = DisposeBag()
    }

    func process(action: PDFReaderAction, in viewModel: ViewModel<PDFReaderActionHandler>) {
        switch action {
        case .loadDocumentData:
            self.loadDocumentData(in: viewModel)

        case .startObservingAnnotationChanges:
            self.observePreviews(in: viewModel)

        case .searchAnnotations(let term):
            self.searchAnnotations(with: term, in: viewModel)

        case .selectAnnotation(let annotation):
            guard annotation?.key != viewModel.state.selectedAnnotation?.key else { return }
            let index = annotation.flatMap({ annotation in
                viewModel.state.annotations[annotation.page]?.firstIndex(where: { annotation.key == $0.key })
            })
            self.select(annotation: annotation, index: index, didSelectInDocument: false, in: viewModel)

        case .selectAnnotationFromDocument(let key, let page):
            guard key != viewModel.state.selectedAnnotation?.key else { return }
            guard let index = viewModel.state.annotations[page]?.firstIndex(where: { $0.key == key }) else { return }
            let annotation = viewModel.state.annotations[page]?[index]
            self.select(annotation: annotation, index: index, didSelectInDocument: true, in: viewModel)
            
        case .annotationsAdded(let annotations):
            self.add(annotations: annotations, in: viewModel)

        case .annotationsRemoved(let annotations):
            self.remove(annotations: annotations, in: viewModel)

        case .removeAnnotation(let annotation):
            self.remove(annotation: annotation, in: viewModel)

        case .requestPreviews(let keys, let notify):
            self.loadPreviews(for: keys, notify: notify, in: viewModel)

        case .setHighlight(let highlight, let key):
            self.updateAnnotation(with: key, transformAnnotation: { ($0.copy(text: highlight), []) }, in: viewModel)

        case .setComment(let key, let comment):
            let convertedComment = self.htmlAttributedStringConverter.convert(attributedString: comment)
            self.updateAnnotation(with: key,
                                  transformAnnotation: { ($0.copy(comment: convertedComment), .comment) },
                                  shouldReload: { _, _ in false }, // doesn't need reload, text is already written in textView in cell
                                  additionalStateChange: { $0.comments[key] = comment },
                                  in: viewModel)

        case .setCommentActive(let isActive):
            guard let annotation = viewModel.state.selectedAnnotation else { return }
            self.update(viewModel: viewModel) { state in
                state.selectedAnnotationCommentActive = isActive
                if let index = state.annotations[annotation.page]?.firstIndex(where: { annotation.key == $0.key }) {
                    state.updatedAnnotationIndexPaths = [IndexPath(row: index, section: annotation.page)]
                }
                state.changes = .activeComment
            }

        case .setTags(let tags, let key):
            self.updateAnnotation(with: key, transformAnnotation: { ($0.copy(tags: tags), []) }, in: viewModel)

        case .setBoundingBox(let pdfAnnotation):
            self.updateBoundingBoxAndRects(for: pdfAnnotation, in: viewModel)

        case .updateAnnotationProperties(let annotation):
            self.updateAnnotation(with: annotation.key,
                                  transformAnnotation: { originalAnnotation in
                                    let changes: PdfAnnotationChanges = originalAnnotation.color != annotation.color ? .color : []
                                    return (annotation, changes)
                                  },
                                  in: viewModel)

        case .userInterfaceStyleChanged(let interfaceStyle):
            self.userInterfaceChanged(interfaceStyle: interfaceStyle, in: viewModel)

        case .updateAnnotationPreviews:
            self.storeAnnotationPreviewsIfNeeded(in: viewModel)

        case .setActiveColor(let hex):
            self.setActiveColor(hex: hex, in: viewModel)

        case .saveChanges:
            self.saveChanges(in: viewModel)

        case .create(let annotation, let pageIndex, let origin):
            self.add(annotationType: annotation, pageIndex: pageIndex, origin: origin, in: viewModel)

        case .setVisiblePage(let page):
            self.set(page: page, in: viewModel)

        case .export:
            self.export(viewModel: viewModel)
        }
    }

    private func set(page: Int, in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.visiblePage = page
        }

        let request = StorePageForItemDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, page: page)

        self.queue.async {
            do {
                try self.dbStorage.createCoordinator().perform(request: request)
            } catch let error {
                // TODO: - handle error
                DDLogError("PDFReaderActionHandler: can't store page - \(error)")
            }
        }
    }

    private func export(viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let url = viewModel.state.document.fileURL else { return }

        self.update(viewModel: viewModel) { state in
            state.exportState = .preparing
        }

        let annotations = AnnotationConverter.annotations(from: viewModel.state.annotations, interfaceStyle: .light)
        PdfDocumentExporter.export(annotations: annotations, key: viewModel.state.key, libraryId: viewModel.state.library.identifier, url: url, fileStorage: self.fileStorage, dbStorage: self.dbStorage,
                                   completed: { [weak viewModel] result in
                                       guard let viewModel = viewModel else { return }
                                       self.finishExport(result: result, viewModel: viewModel)
                                   })
    }

    private func finishExport(result: Result<File, PdfDocumentExporter.Error>, viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            switch result {
            case .success(let file):
                state.exportState = .exported(file)
            case .failure(let error):
                state.exportState = .failed(error)
            }
        }
    }

    // MARK: - Dark mode changes

    private func userInterfaceChanged(interfaceStyle: UIUserInterfaceStyle, in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.changes = .interfaceStyle
            state.interfaceStyle = interfaceStyle
            state.previewCache.removeAllObjects()
            state.shouldStoreAnnotationPreviewsIfNeeded = true

            state.annotations.forEach { page, _ in
                let annotations = state.document.annotations(at: PageIndex(page))
                annotations.forEach { annotation in
                    let (color, alpha) = AnnotationColorGenerator.color(from: UIColor(hex: annotation.baseColor),
                                                                        isHighlight: (annotation is HighlightAnnotation),
                                                                        userInterfaceStyle: interfaceStyle)
                    annotation.color = color
                    annotation.alpha = alpha
                }
            }
        }
    }

    private func storeAnnotationPreviewsIfNeeded(in viewModel: ViewModel<PDFReaderActionHandler>) {
        let isDark = viewModel.state.interfaceStyle == .dark

        // Load area annotations if needed.
        for (_, annotations) in viewModel.state.document.allAnnotations(of: .square) {
            for annotation in annotations {
                guard let annotation = annotation as? SquareAnnotation,
                      let key = annotation.key,
                      !self.annotationPreviewController.hasPreview(for: key, parentKey: viewModel.state.key, isDark: isDark) else { continue }
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, isDark: isDark)
            }
        }

        self.update(viewModel: viewModel) { state in
            state.shouldStoreAnnotationPreviewsIfNeeded = false
        }
    }

    // MARK: - Annotation actions

    private func saveChanges(in viewModel: ViewModel<PDFReaderActionHandler>) {
        let key = viewModel.state.key
        let libraryId = viewModel.state.library.identifier

        var groupedAnnotations: [Int: [Annotation]] = viewModel.state.annotations
        var allAnnotations: [Annotation] = []

        for (page, annotations) in viewModel.state.annotations {
            allAnnotations.append(contentsOf: annotations)
            for (idx, annotation) in annotations.enumerated() {
                guard annotation.didChange else { continue }
                groupedAnnotations[page]?[idx] = annotation.copy(didChange: false)
            }
        }

        self.update(viewModel: viewModel) { state in
            state.annotations = groupedAnnotations
        }

        self.queue.async {
            do {
                let request = StoreChangedAnnotationsDbRequest(attachmentKey: key, libraryId: libraryId, annotations: allAnnotations, schemaController: self.schemaController)
                try self.dbStorage.createCoordinator().perform(request: request)
            } catch let error {
                // TODO: - Show error
            }
        }
    }

    private func setActiveColor(hex: String, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let color = UIColor(hex: hex)

        UserDefaults.standard.set(hex, forKey: PDFReaderState.activeColorKey)

        self.update(viewModel: viewModel) { state in
            state.activeColor = color
            state.changes = .activeColor
        }
    }

    private func updateAnnotation(with key: String,
                                  transformAnnotation: (Annotation) -> (Annotation, PdfAnnotationChanges),
                                  shouldReload: ((Annotation, Annotation) -> Bool)? = nil,
                                  additionalStateChange: ((inout PDFReaderState) -> Void)? = nil,
                                  in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let indexPath = self.indexPath(for: key, in: viewModel.state.annotations),
              let annotation = viewModel.state.annotations[indexPath.section]?[indexPath.row] else { return }

        let (newAnnotation, changes) = transformAnnotation(annotation)
        let shouldReload = shouldReload?(annotation, newAnnotation) ?? true

        self.update(viewModel: viewModel) { state in
            self.update(state: &state, with: newAnnotation, from: annotation, at: indexPath, shouldReload: shouldReload)
            additionalStateChange?(&state)
        }

        self.updatePdfAnnotation(to: newAnnotation, changes: changes, state: viewModel.state)
    }

    private func update(state: inout PDFReaderState, with annotation: Annotation, from oldAnnotation: Annotation, at indexPath: IndexPath, shouldReload: Bool) {
        // Update selected annotation if needed
        if annotation.key == state.selectedAnnotation?.key {
            state.selectedAnnotation = annotation
        }

        state.changes.insert(.save)

        // If sort index didn't change, reload in place
        if annotation.sortIndex == oldAnnotation.sortIndex {
            state.annotations[indexPath.section]?[indexPath.row] = annotation
            if shouldReload {
                state.updatedAnnotationIndexPaths = [indexPath]
                state.changes.insert(.annotations)
            }
            return
        }

        // Otherwise move the annotation to appropriate position
        var annotations = state.annotations[indexPath.section] ?? []
        annotations.remove(at: indexPath.row)
        let newIndex = annotations.index(of: annotation, sortedBy: { $0.sortIndex > $1.sortIndex })
        annotations.insert(annotation, at: newIndex)

        state.annotations[indexPath.section] = annotations
        state.changes.insert(.annotations)

        if indexPath.row == newIndex {
            state.updatedAnnotationIndexPaths = [indexPath]
        } else {
            state.removedAnnotationIndexPaths = [indexPath]
            state.insertedAnnotationIndexPaths = [IndexPath(row: newIndex, section: indexPath.section)]
        }
    }

    private func updatePdfAnnotation(to annotation: Annotation, changes: PdfAnnotationChanges, state: PDFReaderState) {
        guard !changes.isEmpty, let pdfAnnotation = state.document.annotations(at: UInt(annotation.page)).first(where: { $0.key == annotation.key }) else { return }

        if changes.contains(.color) {
            let (color, alpha) = AnnotationColorGenerator.color(from: UIColor(hex: annotation.color),
                                                                isHighlight: (annotation.type == .highlight),
                                                                userInterfaceStyle: state.interfaceStyle)
            pdfAnnotation.baseColor = annotation.color
            pdfAnnotation.color = color
            pdfAnnotation.alpha = alpha
        }

        if changes.contains(.comment) {
            pdfAnnotation.contents = annotation.comment
        }

        NotificationCenter.default.post(name: NSNotification.Name.PSPDFAnnotationChanged, object: pdfAnnotation,
                                        userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: PdfAnnotationChanges.stringValues(from: changes)])
    }

    /// Updates corresponding Zotero annotation to updated PSPDFKit annotation in document.
    /// - parameter annotation: Updated PSPDFKit annotation.
    /// - parameter viewModel: ViewModel.
    private func updateBoundingBoxAndRects(for pdfAnnotation: PSPDFKit.Annotation, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let key = pdfAnnotation.key else { return }

        let sortIndex = AnnotationConverter.sortIndex(from: pdfAnnotation)
        let rects = pdfAnnotation.rects ?? [pdfAnnotation.boundingBox]

        self.updateAnnotation(with: key,
                              transformAnnotation: { ($0.copy(rects: rects, sortIndex: sortIndex), []) },
                              shouldReload: { original, new in
                                  // Reload only if aspect ratio changed.
                                  return original.boundingBox.heightToWidthRatio.rounded(to: 2) != new.boundingBox.heightToWidthRatio.rounded(to: 2)
                              },
                              in: viewModel)

        if let pdfAnnotation = pdfAnnotation as? SquareAnnotation {
            // Remove cached annotation preview.
            viewModel.state.previewCache.removeObject(forKey: (key as NSString))
            // Cache new preview.
            let isDark = viewModel.state.interfaceStyle == .dark
            self.annotationPreviewController.store(for: pdfAnnotation, parentKey: viewModel.state.key, isDark: isDark)
        }
    }

    /// Removes Zotero annotation from document.
    /// - parameter annotation: Annotation to remove.
    /// - parameter viewModel: ViewModel.
    private func remove(annotation: Annotation, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let documentAnnotation = viewModel.state.document.annotations(at: UInt(annotation.page))
                                                               .first(where: { $0.key == annotation.key }) else { return }
        documentAnnotation.isEditable = true
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
            annotations[page] = pageAnnotations.filter({ self.filter(annotation: $0, with: term) })
        }

        self.update(viewModel: viewModel) { state in
            if state.annotationsSnapshot == nil {
                state.annotationsSnapshot = state.annotations
            }
            state.annotations = annotations
            state.currentFilter = term
            state.changes = .annotations
        }
    }

    private func filter(annotation: Annotation, with term: String) -> Bool {
        return annotation.author.localizedCaseInsensitiveContains(term) ||
               annotation.comment.localizedCaseInsensitiveContains(term) ||
               (annotation.text ?? "").localizedCaseInsensitiveContains(term) ||
               annotation.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(term) })
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

    /// Set selected annotation. Also sets `focusSidebarIndexPath` or `focusDocumentLocation` if needed.
    /// - parameter annotation: Annotation to be selected. Deselects current annotation if `nil`.
    /// - parameter index: Index of annotation in annotations array on given page.
    /// - parameter didSelectInDocument: `true` if annotation was selected in document, false if it was selected in sidebar.
    /// - parameter viewModel: ViewModel.
    private func select(annotation: Annotation?, index: Int?, didSelectInDocument: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if let existing = state.selectedAnnotation,
               let index = state.annotations[existing.page]?.firstIndex(where: { $0.key == existing.key }) {
                state.updatedAnnotationIndexPaths = [IndexPath(row: index, section: existing.page)]
                state.selectedAnnotationCommentActive = false
                state.changes.insert(.activeComment)
            }

            if let annotation = annotation, let index = index {
                if !didSelectInDocument {
                    state.focusDocumentLocation = (annotation.page, annotation.boundingBox)
                } else {
                    state.focusSidebarIndexPath = IndexPath(row: index, section: annotation.page)
                }

                var indexPaths = state.updatedAnnotationIndexPaths ?? []
                indexPaths.append(IndexPath(row: index, section: annotation.page))
                state.updatedAnnotationIndexPaths = indexPaths
            }

            state.selectedAnnotation = annotation
            state.changes.insert(.selection)
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
                                                state.loadedPreviewImageAnnotationKeys = [annotationKey]
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
        let isDark = viewModel.state.interfaceStyle == .dark

        var loadedKeys: Set<String> = []

        for key in keys {
            let nsKey = key as NSString
            guard viewModel.state.previewCache.object(forKey: nsKey) == nil else { continue }

            group.enter()
            self.annotationPreviewController.preview(for: key, parentKey: viewModel.state.key, isDark: isDark) { [weak viewModel] image in
                if let image = image {
                    viewModel?.state.previewCache.setObject(image, forKey: nsKey)
                    loadedKeys.insert(key)
                }
                group.leave()
            }
        }

        guard notify else { return }

        group.notify(queue: .main) { [weak viewModel] in
            guard !loadedKeys.isEmpty, let viewModel = viewModel else { return }
            self.update(viewModel: viewModel) { state in
                state.loadedPreviewImageAnnotationKeys = loadedKeys
            }
        }
    }

    // MARK: - Annotation management

    private func add(annotationType: AnnotationType, pageIndex: PageIndex, origin: CGPoint, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let color = AnnotationColorGenerator.color(from: viewModel.state.activeColor, isHighlight: false, userInterfaceStyle: viewModel.state.interfaceStyle).color
        let pdfAnnotation: PSPDFKit.Annotation

        switch annotationType {
        case .highlight: return
        case .image:
            let rect = CGRect(origin: origin, size: CGSize(width: 50, height: 50))
            let square = SquareAnnotation()
            square.pageIndex = pageIndex
            square.boundingBox = rect
            square.borderColor = color
            pdfAnnotation = square
        case .note:
            let rect = CGRect(origin: origin, size: PDFReaderLayout.noteAnnotationSize)
            let note = NoteAnnotation(contents: "")
            note.pageIndex = pageIndex
            note.boundingBox = rect
            note.borderStyle = .dashed
            note.color = color
            pdfAnnotation = note
        }

        viewModel.state.document.add(annotations: [pdfAnnotation], options: nil)
    }

    /// Updates annotations based on insertions to PSPDFKit document.
    /// - parameter annotations: Annotations that were added to the document.
    /// - parameter viewModel: ViewModel.
    private func add(annotations: [PSPDFKit.Annotation], in viewModel: ViewModel<PDFReaderActionHandler>) {
        var newZoteroAnnotations: [Annotation] = []

        let isDark = viewModel.state.interfaceStyle == .dark
        for annotation in annotations {
            if annotation.isZotero {
                guard let annotation = annotation as? SquareAnnotation else { continue }
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, isDark: isDark)
                continue
            }

            guard let zoteroAnnotation = AnnotationConverter.annotation(from: annotation, isNew: true, username: viewModel.state.username) else { continue }

            newZoteroAnnotations.append(zoteroAnnotation)
            annotation.customData = [AnnotationsConfig.isZoteroKey: true,
                                     AnnotationsConfig.keyKey: zoteroAnnotation.key,
                                     AnnotationsConfig.baseColorKey: zoteroAnnotation.color]

            if let annotation = annotation as? SquareAnnotation {
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, isDark: isDark)
            }
        }

        guard !newZoteroAnnotations.isEmpty else { return }

        self.update(viewModel: viewModel) { state in
            var focus: IndexPath?

            for annotation in newZoteroAnnotations {
                if var snapshot = state.annotationsSnapshot {
                    // Search is active, add new annotation to snapshot so that it's visible when search is cancelled
                    self.add(annotation: annotation, to: &snapshot)
                    state.annotationsSnapshot = snapshot

                    // If new annotation passes filter, add it to current filtered list as well
                    if let filter = state.currentFilter, self.filter(annotation: annotation, with: filter) {
                        let index = self.add(annotation: annotation, to: &state.annotations)

                        if focus == nil {
                            focus = IndexPath(row: index, section: annotation.page)
                        }
                    }
                } else {
                    // Search not active, just insert it to the list and focus
                    let index = self.add(annotation: annotation, to: &state.annotations)

                    if focus == nil {
                        focus = IndexPath(row: index, section: annotation.page)
                    }
                }
            }

            state.focusSidebarIndexPath = focus
            state.changes = [.annotations, .save]
        }
    }

    @discardableResult
    private func add(annotation: Annotation, to allAnnotations: inout [Int: [Annotation]]) -> Int {
        let index: Int
        if let annotations = allAnnotations[annotation.page] {
            index = annotations.index(of: annotation, sortedBy: { $0.sortIndex > $1.sortIndex })
            allAnnotations[annotation.page]?.insert(annotation, at: index)
        } else {
            index = 0
            allAnnotations[annotation.page] = [annotation]
        }
        return index
    }

    /// Updates annotations based on deletions of PSPDFKit annotations in document.
    /// - parameter annotations: Annotations that were deleted in document.
    /// - parameter viewModel: ViewModel.
    private func remove(annotations: [PSPDFKit.Annotation], in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            let shouldRemoveSelection: Bool
            let toRemove: [IndexPath]

            if var snapshot = state.annotationsSnapshot {
                // Search is active, delete annotation from snapshot so that it doesn't re-appear when search is cancelled
                let (removedSelection, indexPaths) = self.remove(annotations: annotations, from: &snapshot, parentKey: state.key, selectedKey: state.selectedAnnotation?.key,
                                                                      annotationPreviewController: self.annotationPreviewController)
                shouldRemoveSelection = removedSelection
                toRemove = indexPaths
                state.annotationsSnapshot = snapshot

                // Remove annotations from search result as well
                self.remove(annotations: annotations, from: &state.annotations, parentKey: state.key, selectedKey: nil,
                            annotationPreviewController: self.annotationPreviewController)
            } else {
                // Search not active, just remove annotations and deselect if needed
                let (removedSelection, indexPaths) = self.remove(annotations: annotations, from: &state.annotations, parentKey: state.key, selectedKey: state.selectedAnnotation?.key,
                                                                      annotationPreviewController: self.annotationPreviewController)
                shouldRemoveSelection = removedSelection
                toRemove = indexPaths
            }

            if shouldRemoveSelection {
                state.selectedAnnotation = nil
                state.selectedAnnotationCommentActive = false
                state.changes.insert(.selection)
                state.changes.insert(.activeComment)
            }

            state.removedAnnotationIndexPaths = toRemove
            state.changes.insert(.annotations)
            state.changes.insert(.save)
        }
    }

    @discardableResult
    private func remove(annotations: [PSPDFKit.Annotation], from zoteroAnnotations: inout [Int: [Annotation]], parentKey: String, selectedKey: String?,
                        annotationPreviewController: AnnotationPreviewController) -> (removedSelection: Bool, indexPaths: [IndexPath]) {
        var toRemove: [IndexPath] = []
        var removedSelection = false

        for annotation in annotations {
            guard annotation.isZotero, let key = annotation.key else { continue }

            if let annotation = annotation as? SquareAnnotation {
                annotationPreviewController.delete(for: annotation, parentKey: parentKey)
            }

            if selectedKey == key {
                removedSelection = true
            }

            let page = Int(annotation.pageIndex)
            if let index = zoteroAnnotations[page]?.firstIndex(where: { $0.key == key }) {
                toRemove.append(IndexPath(row: index, section: page))
            }
        }

        for indexPath in toRemove {
            zoteroAnnotations[indexPath.section]?.remove(at: indexPath.row)
        }

        return (removedSelection, toRemove)
    }

    private func indexPath(for key: String, in annotations: [Int: [Annotation]]) -> IndexPath? {
        for (page, annotations) in annotations {
            if let index = annotations.firstIndex(where: { $0.key == key }) {
                return IndexPath(row: index, section: page)
            }
        }
        return nil
    }

    /// Loads annotations from DB, converts them to Zotero annotations and adds matching PSPDFKit annotations to document.
    private func loadDocumentData(in viewModel: ViewModel<PDFReaderActionHandler>) {
        do {
            let (zoteroAnnotations, comments, page) = try self.documentData(for: viewModel.state.key, libraryId: viewModel.state.library.identifier,
                                                                            baseFont: viewModel.state.commentFont, userId: viewModel.state.userId, username: viewModel.state.username)
            let pspdfkitAnnotations = AnnotationConverter.annotations(from: zoteroAnnotations, interfaceStyle: viewModel.state.interfaceStyle)

            self.update(viewModel: viewModel) { state in
                state.annotations = zoteroAnnotations
                state.comments = comments
                state.visiblePage = page
                state.changes = .annotations

                UndoController.performWithoutUndo(undoController: state.document.undoController) {
                    // Hide external supported annotations
                    state.document.allAnnotations(of: AnnotationsConfig.supported).values.flatMap({ $0 }).forEach({ $0.isHidden = true })
                    // Add zotero annotations
                    state.document.add(annotations: pspdfkitAnnotations, options: nil)
                }
            }
        } catch let error {
            // TODO: - show error
        }
    }

    /// Loads annotations from database, groups them by page and converts comment `String`s to `NSAttributedString`s.
    /// - parameter key: Item key for which annotations are loaded.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter baseFont: Font to be used as base for `NSAttributedString`.
    /// - returns: Tuple of grouped annotations and comments.
    private func documentData(for key: String, libraryId: LibraryIdentifier, baseFont: UIFont, userId: Int, username: String) throws
                                                            -> (annotations: [Int: [Annotation]], comments: [String: NSAttributedString], page: Int) {
        let coordinator = try self.dbStorage.createCoordinator()

        let page = try coordinator.perform(request: ReadDocumentDataDbRequest(attachmentKey: key, libraryId: libraryId))
        let items = try coordinator.perform(request: ReadAnnotationsDbRequest(attachmentKey: key, libraryId: libraryId))

        var annotations: [Int: [Annotation]] = [:]
        var comments: [String: NSAttributedString] = [:]

        for item in items {
            guard let annotation = Annotation(item: item, currentUserId: userId, username: username) else { continue }

            if var array = annotations[annotation.page] {
                array.append(annotation)
                annotations[annotation.page] = array
            } else {
                annotations[annotation.page] = [annotation]
            }

            comments[annotation.key] = self.htmlAttributedStringConverter.convert(text: annotation.comment, baseFont: baseFont)
        }

        return (annotations, comments, page)
    }
}

#endif
