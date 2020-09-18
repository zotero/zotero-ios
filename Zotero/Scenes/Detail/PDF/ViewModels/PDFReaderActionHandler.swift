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

    private unowned let dbStorage: DbStorage
    private unowned let annotationPreviewController: AnnotationPreviewController
    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    private unowned let schemaController: SchemaController
    private let queue: DispatchQueue
    private let disposeBag: DisposeBag

    init(dbStorage: DbStorage, annotationPreviewController: AnnotationPreviewController, htmlAttributedStringConverter: HtmlAttributedStringConverter,
         schemaController: SchemaController) {
        self.dbStorage = dbStorage
        self.annotationPreviewController = annotationPreviewController
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.schemaController = schemaController
        self.queue = DispatchQueue(label: "org.zotero.Zotero.PDFReaderActionHandler.queue", qos: .userInteractive)
        self.disposeBag = DisposeBag()
    }

    func process(action: PDFReaderAction, in viewModel: ViewModel<PDFReaderActionHandler>) {
        switch action {
        case .loadAnnotations(let interfaceStyle):
            self.loadAnnotations(interfaceStyle: interfaceStyle, in: viewModel)

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

        case .annotationChanged(let annotation, let isDark):
            self.update(annotation: annotation, isDark: isDark, in: viewModel)
            
        case .annotationsAdded(let annotations, let isDark):
            self.add(annotations: annotations, isDark: isDark, in: viewModel)

        case .annotationsRemoved(let annotations):
            self.remove(annotations: annotations, in: viewModel)

        case .removeAnnotation(let annotation):
            self.remove(annotation: annotation, in: viewModel)

        case .requestPreviews(let keys, let notify, let isDark):
            self.loadPreviews(for: keys, notify: notify, isDark: isDark, in: viewModel)

        case .setHighlight(let highlight, let indexPath):
            self.update(annotation: { $0.copy(text: highlight) }, reloadComment: false, at: indexPath, in: viewModel)

        case .setComment(let comment, let indexPath):
            self.update(annotation: { $0.copy(comment: comment) }, reloadComment: true, at: indexPath, in: viewModel)

        case .setTags(let tags, let indexPath):
            self.update(annotation: { $0.copy(tags: tags) }, reloadComment: false, at: indexPath, in: viewModel)

        case .userInterfaceStyleChanged(let interfaceStyle):
            self.userInterfaceChanged(interfaceStyle: interfaceStyle, in: viewModel)

        case .updateAnnotationPreviews(let userInterfaceIsDark):
            self.storeAnnotationPreviewsIfNeeded(isDark: userInterfaceIsDark, in: viewModel)

        case .setActiveColor(let hex):
            self.setActiveColor(hex: hex, in: viewModel)

        case .saveChanges:
            self.saveChanges(in: viewModel)
        }
    }

    // MARK: - Dark mode changes

    private func userInterfaceChanged(interfaceStyle: UIUserInterfaceStyle, in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.changes = .darkMode
            state.previewCache.removeAllObjects()
            state.shouldStoreAnnotationPreviewsIfNeeded = true

            state.annotations.forEach { page, _ in
                let annotations = state.document.annotations(at: PageIndex(page))
                annotations.forEach { annotation in
                    annotation.color = AnnotationColorGenerator.color(from: UIColor(hex: annotation.baseColor),
                                                                      isHighlight: (annotation is HighlightAnnotation),
                                                                      userInterfaceStyle: interfaceStyle)
                }
            }
        }
    }

    private func storeAnnotationPreviewsIfNeeded(isDark: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
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
        let libraryId = viewModel.state.libraryId

        var allAnnotations: [Annotation] = []
        viewModel.state.annotations.forEach { _, annotations in
            allAnnotations.append(contentsOf: annotations)
        }

        self.queue.async {
            do {
                let request = StoreChangedAnnotationsDbRequest(attachmentKey: key, libraryId: libraryId, annotations: allAnnotations,
                                                               schemaController: self.schemaController)
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

    private func update(annotation annotationChange: (Annotation) -> Annotation, reloadComment: Bool, at indexPath: IndexPath, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotations[indexPath.section]?[indexPath.row] else { return }
        self.update(viewModel: viewModel) { state in
            let newAnnotation = annotationChange(annotation)
            state.annotations[indexPath.section]?[indexPath.row] = newAnnotation
            state.updatedAnnotationIndexPaths = [indexPath]

            if reloadComment {
                state.comments[newAnnotation.key] = self.htmlAttributedStringConverter.convert(text: newAnnotation.comment, baseFont: state.commentFont)
            }
        }
    }

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
                                                state.loadedPreviewImageAnnotationKeys = [annotationKey]
                                            }
                                        })
                                        .disposed(by: self.disposeBag)
    }

    /// Loads previews for given keys and notifies view about them if needed.
    /// - parameter keys: Keys that should load previews.
    /// - parameter notify: If `true`, index paths for loaded images will be found and view will be notified about changes.
    ///                     If `false`, images are loaded and no notification is sent.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - parameter viewModel: ViewModel.
    private func loadPreviews(for keys: [String], notify: Bool, isDark: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let group = DispatchGroup()

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

    /// Updates annotations based on insertions to PSPDFKit document.
    /// - parameter annotations: Annotations that were added to the document.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - parameter viewModel: ViewModel.
    private func add(annotations: [PSPDFKit.Annotation], isDark: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        var newZoteroAnnotations: [Annotation] = []

        for annotation in annotations {
            if annotation.isZotero {
                guard let annotation = annotation as? SquareAnnotation else { continue }
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, isDark: isDark)
                continue
            }

            guard let zoteroAnnotation = self.zoteroAnnotation(from: annotation, isNew: true) else { continue }

            newZoteroAnnotations.append(zoteroAnnotation)
            annotation.customData = [AnnotationsConfig.isZoteroKey: true,
                                     AnnotationsConfig.keyKey: zoteroAnnotation.key]

            if let annotation = annotation as? SquareAnnotation {
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, isDark: isDark)
            }
        }

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
            state.changes = .annotations
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
            let deletedKeys: Set<String>

            if var snapshot = state.annotationsSnapshot {
                // Search is active, delete annotation from snapshot so that it doesn't re-appear when search is cancelled
                deletedKeys = self.remove(annotations: annotations, from: &snapshot, parentKey: state.key,
                                          annotationPreviewController: self.annotationPreviewController)
                state.annotationsSnapshot = snapshot
                // Remove annotations from search result as well
                self.remove(annotations: annotations, from: &state.annotations, parentKey: state.key,
                            annotationPreviewController: self.annotationPreviewController)
            } else {
                // Search not active, just remove annotations and deselect if needed
                deletedKeys = self.remove(annotations: annotations, from: &state.annotations, parentKey: state.key,
                                          annotationPreviewController: self.annotationPreviewController)
            }

            if let selectedKey = state.selectedAnnotation?.key, deletedKeys.contains(selectedKey) {
                state.selectedAnnotation = nil
                state.changes.insert(.selection)
            }
            state.changes.insert(.annotations)
        }
    }

    @discardableResult
    private func remove(annotations: [PSPDFKit.Annotation], from zoteroAnnotations: inout [Int: [Annotation]], parentKey: String,
                        annotationPreviewController: AnnotationPreviewController) -> Set<String> {
        var toDelete: [(Int, Int)] = []
        var keys: Set<String> = []

        for annotation in annotations {
            guard annotation.isZotero, let key = annotation.key else { continue }

            if let annotation = annotation as? SquareAnnotation {
                annotationPreviewController.delete(for: annotation, parentKey: parentKey)
            }

            let page = Int(annotation.pageIndex)
            if let index = zoteroAnnotations[page]?.firstIndex(where: { $0.key == key }) {
                toDelete.append((index, page))
                keys.insert(key)
            }
        }

        for location in toDelete {
            zoteroAnnotations[location.1]?.remove(at: location.0)
        }

        return keys
    }

    /// Updates corresponding Zotero annotation to updated PSPDFKit annotation in document.
    /// - parameter annotation: Updated PSPDFKit annotation.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - parameter viewModel: ViewModel.
    private func update(annotation: PSPDFKit.Annotation, isDark: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let key = annotation.key else { return }
        guard let indexPath = self.indexPath(for: key, in: viewModel.state.annotations) else {
            // Annotation not found, add it
            self.add(annotations: [annotation], isDark: isDark, in: viewModel)
            return
        }

        let newSection = Int(annotation.pageIndex)

        guard newSection == indexPath.section else { return }

        self.update(viewModel: viewModel) { state in
            guard var zoteroAnnotation = state.annotations[indexPath.section]?[indexPath.row] else {
                DDLogError("PDFReaderActionHandler: annotation not found at index which was found in `findAnnotation`")
                fatalError("PDFReaderActionHandler: annotation not found at index which was found in `findAnnotation`")
            }

            // If it's a `SquareAnnotation`, reload cell if aspect ratio of preview changed
            if annotation is SquareAnnotation &&
               zoteroAnnotation.boundingBox.heightToWidthRatio.rounded(to: 2) != annotation.boundingBox.heightToWidthRatio.rounded(to: 2) {
                state.updatedAnnotationIndexPaths = [indexPath]
            }

            // Update bounding box of annotation
            zoteroAnnotation = zoteroAnnotation.copy(rects: annotation.rects ?? [annotation.boundingBox],
                                                     sortIndex: self.sortIndex(from: annotation))
            state.annotations[indexPath.section]?[indexPath.row] = zoteroAnnotation

            // Remove annotation preview from cache, if `SquareAnnotation` changed, then preview image changed as well
            state.previewCache.removeObject(forKey: (key as NSString))
        }

        if let annotation = annotation as? SquareAnnotation {
            // Load new image for `SquareAnnotation`
            self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, isDark: isDark)
        }
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
    private func loadAnnotations(interfaceStyle: UIUserInterfaceStyle, in viewModel: ViewModel<PDFReaderActionHandler>) {
        do {
            let (zoteroAnnotations, comments) = try self.annotationsAndComments(for: viewModel.state.key,
                                                                                libraryId: viewModel.state.libraryId,
                                                                                baseFont: viewModel.state.commentFont)
            let pspdfkitAnnotations = self.annotations(from: zoteroAnnotations, interfaceStyle: interfaceStyle)

            self.update(viewModel: viewModel) { state in
                state.annotations = zoteroAnnotations
                state.comments = comments
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
    private func annotationsAndComments(for key: String, libraryId: LibraryIdentifier, baseFont: UIFont) throws
                                                                       -> (annotations: [Int: [Annotation]], comments: [String: NSAttributedString]) {
        let items = try self.dbStorage.createCoordinator().perform(request: ReadAnnotationsDbRequest(attachmentKey: key, libraryId: libraryId))

        var annotations: [Int: [Annotation]] = [:]
        var comments: [String: NSAttributedString] = [:]

        for item in items {
            guard let annotation = Annotation(item: item) else { continue }

            if var array = annotations[annotation.page] {
                array.append(annotation)
                annotations[annotation.page] = array
            } else {
                annotations[annotation.page] = [annotation]
            }

            comments[annotation.key] = self.htmlAttributedStringConverter.convert(text: annotation.comment, baseFont: baseFont)
        }

        return (annotations, comments)
    }

    /// Create Zotero annotation from existing PSPDFKit annotation.
    /// - parameter annotation: PSPDFKit annotation.
    /// - parameter isNew: Indicating, whether the annotation has just been created.
    /// - returns: Matching Zotero annotation.
    private func zoteroAnnotation(from annotation: PSPDFKit.Annotation, isNew: Bool) -> Annotation? {
        guard AnnotationsConfig.supported.contains(annotation.type) else { return nil }

        let page = Int(annotation.pageIndex)

        if let annotation = annotation as? NoteAnnotation {
            return Annotation(key: KeyGenerator.newKey,
                              type: .note,
                              page: page,
                              pageLabel: "\(annotation.pageIndex + 1)",
                              rects: [annotation.boundingBox],
                              author: "",
                              isAuthor: true,
                              color: annotation.color?.hexString ?? AnnotationsConfig.defaultActiveColor,
                              comment: (annotation.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                              text: nil,
                              isLocked: false,
                              sortIndex: self.sortIndex(from: annotation),
                              dateModified: Date(),
                              tags: [],
                              didChange: isNew)
        } else if let annotation = annotation as? HighlightAnnotation {
            return Annotation(key: KeyGenerator.newKey,
                              type: .highlight,
                              page: page,
                              pageLabel: "\(annotation.pageIndex + 1)",
                              rects: annotation.rects ?? [annotation.boundingBox],
                              author: "",
                              isAuthor: true,
                              color: annotation.color?.hexString ?? AnnotationsConfig.defaultActiveColor,
                              comment: "",
                              text: annotation.markedUpString.trimmingCharacters(in: .whitespacesAndNewlines),
                              isLocked: false,
                              sortIndex: self.sortIndex(from: annotation),
                              dateModified: Date(),
                              tags: [],
                              didChange: isNew)
        } else if let annotation = annotation as? SquareAnnotation {
            return Annotation(key: KeyGenerator.newKey,
                              type: .image,
                              page: page,
                              pageLabel: "\(annotation.pageIndex + 1)",
                              rects: [annotation.boundingBox],
                              author: "",
                              isAuthor: true,
                              color: annotation.color?.hexString ?? AnnotationsConfig.defaultActiveColor,
                              comment: "",
                              text: nil,
                              isLocked: false,
                              sortIndex: self.sortIndex(from: annotation),
                              dateModified: Date(),
                              tags: [],
                              didChange: isNew)
        }

        return nil
    }

    /// Converts Zotero annotations to actual document (PSPDFKit) annotations with custom flags.
    /// - parameter zoteroAnnotations: Annotations to convert.
    /// - returns: Array of PSPDFKit annotations that can be added to document.
    private func annotations(from zoteroAnnotations: [Int: [Annotation]], interfaceStyle: UIUserInterfaceStyle) -> [PSPDFKit.Annotation] {
        return zoteroAnnotations.values.flatMap({ $0 }).map({
            switch $0.type {
            case .image:
                return self.areaAnnotation(from: $0, interfaceStyle: interfaceStyle)
            case .highlight:
                return self.highlightAnnotation(from: $0, interfaceStyle: interfaceStyle)
            case .note:
                return self.noteAnnotation(from: $0, interfaceStyle: interfaceStyle)
            }
        })
    }

    /// Creates corresponding `SquareAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private func areaAnnotation(from annotation: Annotation, interfaceStyle: UIUserInterfaceStyle) -> SquareAnnotation {
        let square = SquareAnnotation()
        square.pageIndex = UInt(annotation.page)
        square.boundingBox = annotation.boundingBox
        square.borderColor = AnnotationColorGenerator.color(from: UIColor(hex: annotation.color),
                                                            isHighlight: false,
                                                            userInterfaceStyle: interfaceStyle)
        square.isZotero = true
        square.baseColor = annotation.color
        square.key = annotation.key
        return square
    }

    /// Creates corresponding `HighlightAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private func highlightAnnotation(from annotation: Annotation, interfaceStyle: UIUserInterfaceStyle) -> HighlightAnnotation {
        let highlight = HighlightAnnotation()
        highlight.pageIndex = UInt(annotation.page)
        highlight.boundingBox = annotation.boundingBox
        highlight.rects = annotation.rects
        highlight.color = AnnotationColorGenerator.color(from: UIColor(hex: annotation.color), isHighlight: true, userInterfaceStyle: interfaceStyle)
        highlight.isZotero = true
        highlight.baseColor = annotation.color
        highlight.key = annotation.key
        return highlight
    }

    /// Creates corresponding `NoteAnnotation`.
    /// - parameter annotation: Zotero annotation.
    private func noteAnnotation(from annotation: Annotation, interfaceStyle: UIUserInterfaceStyle) -> NoteAnnotation {
        let note = NoteAnnotation(contents: annotation.comment)
        note.pageIndex = UInt(annotation.page)
        let boundingBox = annotation.boundingBox
        note.boundingBox = CGRect(x: boundingBox.minX, y: boundingBox.minY, width: 32, height: 32)
        note.isZotero = true
        note.key = annotation.key
        note.borderStyle = .dashed
        note.color = AnnotationColorGenerator.color(from: UIColor(hex: annotation.color), isHighlight: false, userInterfaceStyle: interfaceStyle)
        note.baseColor = annotation.color
        return note
    }

    private func sortIndex(from annotation: PSPDFKit.Annotation) -> String {
        let yPos = Int(round(annotation.boundingBox.origin.y))
        return String(format: "%05d|%06d|%05d", annotation.pageIndex, 0, yPos)
    }
}

#endif
