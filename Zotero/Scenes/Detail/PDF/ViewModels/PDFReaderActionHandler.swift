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
import RealmSwift
import RxSwift

protocol AnnotationBoundingBoxConverter: class {
    func convertToDb(rect: CGRect, page: PageIndex) -> CGRect?
    func convertFromDb(rect: CGRect, page: PageIndex) -> CGRect?
    func sortIndexMinY(rect: CGRect, page: PageIndex) -> CGFloat?
    func textOffset(rect: CGRect, page: PageIndex) -> Int?
}

final class PDFReaderActionHandler: ViewModelActionHandler {
    typealias Action = PDFReaderAction
    typealias State = PDFReaderState

    fileprivate struct PdfAnnotationChanges: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let color = PdfAnnotationChanges(rawValue: 1 << 0)
        static let comment = PdfAnnotationChanges(rawValue: 1 << 1)
        static let boundingBox = PdfAnnotationChanges(rawValue: 1 << 2)
        static let rects = PdfAnnotationChanges(rawValue: 1 << 2)

        static func stringValues(from changes: PdfAnnotationChanges) -> [String] {
            switch changes {
            case .color: return ["alpha", "color"]
            case .comment: return ["contents"]
            case .rects: return ["rects"]
            case .boundingBox: return ["boundingBox"]
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

    var boundingBoxConverter: AnnotationBoundingBoxConverter?

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
            
        case .annotationsAdded(let annotations, let selectFirst):
            self.add(annotations: annotations, selectFirst: selectFirst, in: viewModel)

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

        case .clearTmpAnnotationPreviews:
            self.clearTmpAnnotationPreviews(in: viewModel)

        case .itemsChange(let objects, let deletions, let insertions, let modifications):
            self.syncItems(results: objects, deletions: deletions, insertions: insertions, modifications: modifications, in: viewModel)

        case .updateDbPositions(let objects, let deletions, let insertions):
            self.updateDbPositions(objects: objects, deletions: deletions, insertions: insertions, in: viewModel)

        case .notificationReceived(let name):
            self.update(viewModel: viewModel) { state in
                state.ignoreNotifications[name] = nil
            }

        case .annotationChangeNotificationReceived(let key):
            self.update(viewModel: viewModel) { state in
                state.ignoreNotifications[.PSPDFAnnotationChanged]?.remove(key)
            }
        }
    }

    private func updateDbPositions(objects: Results<RItem>, deletions: [Int], insertions: [Int], in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard !deletions.isEmpty || !insertions.isEmpty else { return }

        self.update(viewModel: viewModel) { state in
            deletions.reversed().forEach({ state.dbPositions.remove(at: $0) })
            if !deletions.isEmpty {
                DDLogInfo("PDFReaderActionHandler: removed dbPositions (\(state.dbPositions.count))")
            }
            for idx in insertions {
                let item = objects[idx]
                guard let page = item.fields.filter(.key(FieldKeys.Item.Annotation.pageIndex)).first.flatMap({ Int($0.value) }) else { continue }
                state.dbPositions.insert(AnnotationPosition(page: page, key: item.key), at: idx)
            }
            if !insertions.isEmpty {
                DDLogInfo("PDFReaderActionHandler: inserted dbPositions (\(state.dbPositions.count))")
            }
        }
    }

    private func syncItems(results: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int], in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard !deletions.isEmpty || !insertions.isEmpty || !modifications.isEmpty else { return }

        // TODO: - group editability temporarily disabled
        let editability: Annotation.Editability // = library.metadataEditable ? .editable : .notEditable
        switch viewModel.state.library.identifier {
        case .custom:
            editability = .editable
        case .group:
            editability = .notEditable
        }

        var deletedAnnotations: [PSPDFKit.Annotation] = []
        var addedAnnotations: [Annotation] = []
        var modifiedAnnotations: [(PSPDFKit.Annotation, Annotation, PdfAnnotationChanges)] = []

        var modifiedKeys: Set<String> = []
        self.update(viewModel: viewModel) { state in
            // Modify existing annotations
            for idx in Database.correctedModifications(from: modifications, insertions: insertions, deletions: deletions) {
                let item = results[idx]
                guard !state.deletedKeys.contains(item.key), // If annotation was deleted, it'll be stored as deleted anyway or CR will happen
                      let boundingBoxConverter = self.boundingBoxConverter,
                      let annotation = AnnotationConverter.annotation(from: item, editability: editability, currentUserId: state.userId,
                                                                      username: state.username, boundingBoxConverter: boundingBoxConverter) else { continue }

                var changes: PdfAnnotationChanges = []

                if var snapshot = state.annotationsSnapshot {
                    // If search is active, try updating snapshot
                    guard let _changes = self.modify(annotation: annotation, in: &snapshot) else { continue }
                    changes = _changes
                    state.annotationsSnapshot = snapshot
                    // If annotation was found in snapshot and was different, update visible results as well
                    self.modify(annotation: annotation, in: &state.annotations)
                } else {
                    // If search is not active, modify annotation in all annotations
                    guard let _changes = self.modify(annotation: annotation, in: &state.annotations) else { continue }
                    changes = _changes
                }

                if !changes.isEmpty, let pdfAnnotation = state.document.annotations(at: PageIndex(annotation.page)).first(where: { $0.key == annotation.key }) {
                    modifiedAnnotations.append((pdfAnnotation, annotation, changes))
                    modifiedKeys.insert(annotation.key)
                }

                state.comments[annotation.key] = self.htmlAttributedStringConverter.convert(text: annotation.comment, baseFont: state.commentFont)
            }
            state.ignoreNotifications[.PSPDFAnnotationChanged] = modifiedKeys

            // Delete annotations
            var deletedKeys: Set<String> = []
            for idx in deletions {
                let position = state.dbPositions[idx]

                if let annotation = state.document.annotations(at: PageIndex(position.page)).first(where: { $0.key == position.key }) {
                    deletedAnnotations.append(annotation)
                    deletedKeys.insert(position.key)
                }

                state.comments[position.key] = nil
                state.deletedKeys.remove(position.key)

                if state.selectedAnnotation?.key == position.key {
                    state.selectedAnnotation = nil
                    state.changes.insert(.selection)

                    if state.selectedAnnotationCommentActive {
                        state.selectedAnnotationCommentActive = false
                        state.changes.insert(.activeComment)
                    }
                }

                if var snapshot = state.annotationsSnapshot {
                    // If search is active, try removing in snapshot
                    guard self.remove(at: position, from: &snapshot) else { continue }
                    state.annotationsSnapshot = snapshot
                    // If annotation was found in snapshot, try removing in search results as well
                    self.remove(at: position, from: &state.annotations)
                } else {
                    // If search is not active, remove index path from all annotations
                    guard self.remove(at: position, from: &state.annotations) else { continue }
                }
            }

            state.ignoreNotifications[.PSPDFAnnotationsRemoved] = deletedKeys

            // Add new annotations
            var insertedKeys: Set<String> = []
            for idx in insertions {
                guard let boundingBoxConverter = self.boundingBoxConverter,
                      let annotation = AnnotationConverter.annotation(from: results[idx], editability: editability, currentUserId: state.userId,
                                                                      username: state.username, boundingBoxConverter: boundingBoxConverter) else { continue }
                addedAnnotations.append(annotation)
                insertedKeys.insert(annotation.key)
            }
            self.add(annotations: addedAnnotations, to: &state, selectFirst: false)
            state.ignoreNotifications[.PSPDFAnnotationsAdded] = insertedKeys

            state.changes.insert(.annotations)
        }

        // Update the document

        UndoController.performWithoutUndo(undoController: viewModel.state.document.undoController) {
            if !modifiedAnnotations.isEmpty {
                for (pdfAnnotation, annotation, changes) in modifiedAnnotations {
                    self.update(pdfAnnotation: pdfAnnotation, with: annotation, changes: changes, state: viewModel.state)
                }
            }

            if !deletedAnnotations.isEmpty {
                viewModel.state.document.remove(annotations: deletedAnnotations, options: nil)
            }

            if !addedAnnotations.isEmpty {
                // Convert Zotero annotations to PSPDFKit annotations
                let annotations = addedAnnotations.map({ AnnotationConverter.annotation(from: $0, type: .zotero, interfaceStyle: viewModel.state.interfaceStyle) })
                // Add them to document, suppress notifications
                viewModel.state.document.add(annotations: annotations, options: nil)
                // Store preview for image annotations
                annotations.compactMap({ $0 as? PSPDFKit.SquareAnnotation }).forEach { annotation in
                    self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key,
                                                           libraryId: viewModel.state.library.identifier,
                                                           isDark: (viewModel.state.interfaceStyle == .dark))
                }
            }
        }
    }

    /// Modifies dictionary of annotations if given annotation can be found and differs from existing annotation.
    /// - parameter annotation: Modified annotation.
    /// - parameter annotations: Dictionary of existing annotations.
    /// - returns: Index path of annotation if it was found and was different from existing annotation.
    @discardableResult
    private func modify(annotation: Annotation, in annotations: inout [Int: [Annotation]]) -> PdfAnnotationChanges? {
        guard var pageAnnotations = annotations[annotation.page],
              let pageIdx = pageAnnotations.firstIndex(where: { $0.key == annotation.key }),
              pageAnnotations[pageIdx] != annotation else { return nil }

        let oldAnnotation = pageAnnotations[pageIdx]
        pageAnnotations[pageIdx] = annotation
        annotations[annotation.page] = pageAnnotations

        var changes: PdfAnnotationChanges = []
        if oldAnnotation.color != annotation.color {
            changes.insert(.color)
        }
        if oldAnnotation.comment != annotation.comment {
            changes.insert(.comment)
        }
        if oldAnnotation.boundingBox != annotation.boundingBox {
            changes.insert(.boundingBox)
        }
        if oldAnnotation.rects != annotation.rects {
            changes.insert(.rects)
        }

        return changes
    }

    @discardableResult
    private func remove(at position: AnnotationPosition, from annotations: inout [Int: [Annotation]]) -> Bool {
        guard var pageAnnotations = annotations[position.page],
              let pageIdx = pageAnnotations.firstIndex(where: { $0.key == position.key }) else { return false }
        pageAnnotations.remove(at: pageIdx)
        annotations[position.page] = pageAnnotations
        return true
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

        let annotations = AnnotationConverter.annotations(from: viewModel.state.annotations, type: .export, interfaceStyle: .light)
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
                                                                        isHighlight: (annotation is PSPDFKit.HighlightAnnotation),
                                                                        userInterfaceStyle: interfaceStyle)
                    annotation.color = color
                    annotation.alpha = alpha
                }
            }
        }
    }

    private func storeAnnotationPreviewsIfNeeded(in viewModel: ViewModel<PDFReaderActionHandler>) {
        let isDark = viewModel.state.interfaceStyle == .dark
        let libraryId = viewModel.state.library.identifier

        // Load area annotations if needed.
        for (_, annotations) in viewModel.state.document.allAnnotations(of: .square) {
            for annotation in annotations {
                guard let annotation = annotation as? PSPDFKit.SquareAnnotation,
                      annotation.isImageAnnotation &&
                      !self.annotationPreviewController.hasPreview(for: (annotation.key ?? annotation.uuid), parentKey: viewModel.state.key, libraryId: libraryId, isDark: isDark) else { continue }
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: libraryId, isDark: isDark)
            }
        }

        self.update(viewModel: viewModel) { state in
            state.shouldStoreAnnotationPreviewsIfNeeded = false
        }
    }

    // MARK: - Annotation actions

    private func saveChanges(in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let boundingBoxConverter = self.boundingBoxConverter else { return }

        let key = viewModel.state.key
        let libraryId = viewModel.state.library.identifier
        let deletedKeys = viewModel.state.deletedKeys

        var groupedAnnotations: [Int: [Annotation]] = viewModel.state.annotations
        var allAnnotations: [Annotation] = []

        for (page, annotations) in viewModel.state.annotations {
            for (idx, annotation) in annotations.enumerated() {
                if annotation.isSyncable {
                    allAnnotations.append(annotation)
                }

                if annotation.didChange {
                    groupedAnnotations[page]?[idx] = annotation.copy(didChange: false)
                }
            }
        }

        self.update(viewModel: viewModel) { state in
            state.annotations = groupedAnnotations
            state.deletedKeys = []
            state.insertedKeys = []
            state.modifiedKeys = []
        }

        self.queue.async {
            do {
                let request = StoreChangedAnnotationsDbRequest(attachmentKey: key, libraryId: libraryId, annotations: allAnnotations, deletedKeys: deletedKeys,
                                                               schemaController: self.schemaController, boundingBoxConverter: boundingBoxConverter)
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

        if let pdfAnnotation = viewModel.state.document.annotations(at: UInt(annotation.page)).first(where: { $0.syncable && $0.key == annotation.key }) {
            self.update(pdfAnnotation: pdfAnnotation, with: newAnnotation, changes: changes, state: viewModel.state)
        }
    }

    private func update(state: inout PDFReaderState, with annotation: Annotation, from oldAnnotation: Annotation, at indexPath: IndexPath, shouldReload: Bool) {
        // Update selected annotation if needed
        if annotation.key == state.selectedAnnotation?.key {
            state.selectedAnnotation = annotation
        }

        if !state.insertedKeys.contains(annotation.key) {
            state.modifiedKeys.insert(annotation.key)
        }
        state.changes.insert(.save)

        // If sort index didn't change, reload in place
        if annotation.sortIndex == oldAnnotation.sortIndex {
            state.annotations[indexPath.section]?[indexPath.row] = annotation
            if shouldReload {
                state.changes.insert(.annotations)
            }
            return
        }

        // Otherwise move the annotation to appropriate position
        var annotations = state.annotations[indexPath.section] ?? []
        annotations.remove(at: indexPath.row)
        let newIndex = annotations.index(of: annotation, sortedBy: { $0.sortIndex < $1.sortIndex })
        annotations.insert(annotation, at: newIndex)

        state.annotations[indexPath.section] = annotations
        state.changes.insert(.annotations)
    }

    private func update(pdfAnnotation: PSPDFKit.Annotation, with annotation: Annotation, changes: PdfAnnotationChanges, state: PDFReaderState) {
        guard !changes.isEmpty else { return }

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

        if changes.contains(.boundingBox) {
            pdfAnnotation.boundingBox = annotation.boundingBox
            if let annotation = pdfAnnotation as? PSPDFKit.SquareAnnotation {
                self.annotationPreviewController.store(for: annotation, parentKey: state.key, libraryId: state.library.identifier, isDark: (state.interfaceStyle == .dark))
            }
        }

        if changes.contains(.rects) {
            pdfAnnotation.rects = annotation.rects
        }

        NotificationCenter.default.post(name: NSNotification.Name.PSPDFAnnotationChanged, object: pdfAnnotation,
                                        userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: PdfAnnotationChanges.stringValues(from: changes)])
    }

    /// Updates corresponding Zotero annotation to updated PSPDFKit annotation in document.
    /// - parameter annotation: Updated PSPDFKit annotation.
    /// - parameter viewModel: ViewModel.
    private func updateBoundingBoxAndRects(for pdfAnnotation: PSPDFKit.Annotation, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard pdfAnnotation.syncable, let key = pdfAnnotation.key else { return }

        let sortIndex = AnnotationConverter.sortIndex(from: pdfAnnotation, boundingBoxConverter: self.boundingBoxConverter)
        let rects = pdfAnnotation.rects ?? [pdfAnnotation.boundingBox]

        self.updateAnnotation(with: key,
                              transformAnnotation: { ($0.copy(rects: rects, sortIndex: sortIndex), []) },
                              shouldReload: { original, new in
                                  // Reload only if aspect ratio changed.
                                  return original.boundingBox.heightToWidthRatio.rounded(to: 2) != new.boundingBox.heightToWidthRatio.rounded(to: 2)
                              },
                              in: viewModel)

        if let pdfAnnotation = pdfAnnotation as? PSPDFKit.SquareAnnotation {
            // Remove cached annotation preview.
            viewModel.state.previewCache.removeObject(forKey: (key as NSString))
            // Cache new preview.
            let isDark = viewModel.state.interfaceStyle == .dark
            self.annotationPreviewController.store(for: pdfAnnotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, isDark: isDark)
        }
    }

    /// Removes Zotero annotation from document.
    /// - parameter annotation: Annotation to remove.
    /// - parameter viewModel: ViewModel.
    private func remove(annotation: Annotation, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let documentAnnotation = viewModel.state.document.annotations(at: UInt(annotation.page)).first(where: { $0.syncable && $0.key == annotation.key }) else { return }
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

    /// Annotations which originate from document and are not synced generate their previews based on annotation UUID, which is in-memory and is not stored in PDF. So these previews are only
    /// temporary and should be cleared when user closes the document.
    private func clearTmpAnnotationPreviews(in viewModel: ViewModel<PDFReaderActionHandler>) {
        let libraryId = viewModel.state.library.identifier
        let unsyncableAnnotations = viewModel.state.annotations.flatMap({ $1.filter({ !$0.isSyncable }) })

        for annotation in unsyncableAnnotations {
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: annotation.key, pdfKey: viewModel.state.key, libraryId: libraryId, isDark: false))
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: annotation.key, pdfKey: viewModel.state.key, libraryId: libraryId, isDark: true))
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
        let libraryId = viewModel.state.library.identifier

        var loadedKeys: Set<String> = []

        for key in keys {
            let nsKey = key as NSString
            guard viewModel.state.previewCache.object(forKey: nsKey) == nil else { continue }

            group.enter()
            self.annotationPreviewController.preview(for: key, parentKey: viewModel.state.key, libraryId: libraryId, isDark: isDark) { [weak viewModel] image in
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
            let rect = CGRect(origin: origin, size: AnnotationsConfig.noteAnnotationSize)
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
    private func add(annotations: [PSPDFKit.Annotation], selectFirst: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        var newZoteroAnnotations: [Annotation] = []

        let isDark = viewModel.state.interfaceStyle == .dark
        let libraryId = viewModel.state.library.identifier
        // TODO: - group editability temporarily disabled
        let editability: Annotation.Editability //= viewModel.state.library.metadataEditable ? .editable : .notEditable
        switch libraryId {
        case .custom:
            editability = .editable
        case .group:
            editability = .notEditable
        }
        let activeColor = viewModel.state.activeColor.hexString

        for annotation in annotations {
            guard !annotation.syncable,
                  let zoteroAnnotation = AnnotationConverter.annotation(from: annotation, color: activeColor, editability: editability, isNew: true, isSyncable: true,
                                                                        username: viewModel.state.username, boundingBoxConverter: self.boundingBoxConverter) else { continue }

            newZoteroAnnotations.append(zoteroAnnotation)
            annotation.customData = [AnnotationsConfig.keyKey: zoteroAnnotation.key,
                                     AnnotationsConfig.baseColorKey: activeColor,
                                     AnnotationsConfig.syncableKey: true]

            if let annotation = annotation as? PSPDFKit.SquareAnnotation {
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: libraryId, isDark: isDark)
            }
        }

        guard !newZoteroAnnotations.isEmpty else { return }

        self.update(viewModel: viewModel) { state in
            self.add(annotations: newZoteroAnnotations, to: &state, selectFirst: selectFirst)
            let keys = newZoteroAnnotations.map({ $0.key })
            state.insertedKeys = state.insertedKeys.union(keys)
            state.deletedKeys = state.deletedKeys.subtracting(keys)
            state.changes.insert(.save)
        }
    }

    private func add(annotations: [Annotation], to state: inout PDFReaderState, selectFirst: Bool) {
        guard !annotations.isEmpty else { return }

        var focus: IndexPath?
        var selectedAnnotation: Annotation?

        for annotation in annotations {
            if var snapshot = state.annotationsSnapshot {
                // Search is active, add new annotation to snapshot so that it's visible when search is cancelled
                self.add(annotation: annotation, to: &snapshot)
                state.annotationsSnapshot = snapshot

                // If new annotation passes filter, add it to current filtered list as well
                if let filter = state.currentFilter, self.filter(annotation: annotation, with: filter) {
                    let index = self.add(annotation: annotation, to: &state.annotations)

                    if selectFirst && focus == nil {
                        focus = IndexPath(row: index, section: annotation.page)
                        selectedAnnotation = annotation
                    }
                }
            } else {
                // Search not active, just insert it to the list and focus
                let index = self.add(annotation: annotation, to: &state.annotations)

                if selectFirst && focus == nil {
                    focus = IndexPath(row: index, section: annotation.page)
                    selectedAnnotation = annotation
                }
            }
        }

        state.focusSidebarIndexPath = focus
        state.selectedAnnotation = selectedAnnotation
        state.changes.insert(.annotations)

        if selectedAnnotation != nil {
            state.changes.insert(.selection)
        }
    }

    @discardableResult
    private func add(annotation: Annotation, to allAnnotations: inout [Int: [Annotation]]) -> Int {
        let index: Int
        if let annotations = allAnnotations[annotation.page] {
            if let existingId = annotations.firstIndex(where: { $0.key == annotation.key }) {
                return existingId
            }

            index = annotations.index(of: annotation, sortedBy: { $0.sortIndex < $1.sortIndex })
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
            let keys: Set<String>

            if var snapshot = state.annotationsSnapshot {
                // Search is active, delete annotation from snapshot so that it doesn't re-appear when search is cancelled
                keys = self.remove(annotations: annotations, from: &snapshot)
                state.annotationsSnapshot = snapshot
                // Remove annotations from search result as well
                self.remove(annotations: annotations, from: &state.annotations)
            } else {
                // Search not active, remove from all annotations
                keys = self.remove(annotations: annotations, from: &state.annotations)
            }

            if let selectedKey = state.selectedAnnotation?.key, keys.contains(selectedKey) {
                state.selectedAnnotation = nil
                state.changes.insert(.selection)

                if state.selectedAnnotationCommentActive {
                    state.selectedAnnotationCommentActive = false
                    state.changes.insert(.activeComment)
                }
            }

            keys.forEach({ state.comments[$0] = nil })
            state.deletedKeys = state.deletedKeys.union(keys)
            state.insertedKeys = state.insertedKeys.subtracting(keys)
            state.modifiedKeys = state.modifiedKeys.subtracting(keys)
            state.changes.insert(.annotations)
            state.changes.insert(.save)
        }
    }

    @discardableResult
    private func remove(annotations: [PSPDFKit.Annotation], from zoteroAnnotations: inout [Int: [Annotation]]) -> Set<String> {
        var keys: Set<String> = []
        for annotation in annotations {
            guard annotation.syncable, let key = annotation.key else { continue }
            let page = Int(annotation.pageIndex)
            if let index = zoteroAnnotations[page]?.firstIndex(where: { $0.key == key }) {
                zoteroAnnotations[page]?.remove(at: index)
                keys.insert(key)
            }
        }
        return keys
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
        guard let boundingBoxConverter = self.boundingBoxConverter else { return }

        do {
            let isDark = viewModel.state.interfaceStyle == .dark
            // Load Zotero annotations from DB
            var (zoteroAnnotations, positions, comments, page, items) = try self.documentData(for: viewModel.state.key, library: viewModel.state.library, baseFont: viewModel.state.commentFont,
                                                                                              userId: viewModel.state.userId, username: viewModel.state.username,
                                                                                              boundingBoxConverter: boundingBoxConverter)
            // Create PSPDFKit annotations from Zotero annotations
            let pspdfkitAnnotations = AnnotationConverter.annotations(from: zoteroAnnotations, interfaceStyle: viewModel.state.interfaceStyle)
            // Create Zotero non-editable annotations from supported document annotations
            self.loadAnnotations(from: viewModel.state.document, username: viewModel.state.username, font: viewModel.state.commentFont, addTo: &zoteroAnnotations, comments: &comments)

            self.update(viewModel: viewModel) { state in
                state.annotations = zoteroAnnotations
                DDLogInfo("PDFReaderActionHandler: loaded dbPositions (\(positions.count))")
                state.dbPositions = positions
                state.comments = comments
                state.visiblePage = page
                state.dbItems = items
                state.changes = [.annotations, .itemObserving]

                UndoController.performWithoutUndo(undoController: state.document.undoController) {
                    // Disable all non-zotero annotations, store previews if needed
                    let allAnnotations = state.document.allAnnotations(of: PSPDFKit.Annotation.Kind.all)
                    for (_, annotations) in allAnnotations {
                        annotations.forEach({ annotation in
                            annotation.flags.update(with: .locked)

                            if let annotation = annotation as? PSPDFKit.SquareAnnotation {
                                self.annotationPreviewController.store(for: annotation, parentKey: state.key, libraryId: viewModel.state.library.identifier, isDark: isDark)
                            }
                        })
                    }
                    // Add zotero annotations to document
                    state.document.add(annotations: pspdfkitAnnotations, options: nil)
                    // Store previews
                    pspdfkitAnnotations.forEach { annotation in
                        if let annotation = annotation as? PSPDFKit.SquareAnnotation {
                            self.annotationPreviewController.store(for: annotation, parentKey: state.key, libraryId: viewModel.state.library.identifier, isDark: isDark)
                        }
                    }
                }
            }
        } catch let error {
            // TODO: - show error
        }
    }

    private func loadAnnotations(from document: Document, username: String, font: UIFont, addTo allAnnotations: inout [Int: [Annotation]], comments: inout [String: NSAttributedString]) {
        for (_, pdfAnnotations) in document.allAnnotations(of: AnnotationsConfig.supported) {
            for pdfAnnotation in pdfAnnotations {
                // Check whether square annotation was previously created by Zotero. If it's just "normal" square (instead of our image) annotation, don't convert it to Zotero annotation.
                if let square = pdfAnnotation as? PSPDFKit.SquareAnnotation, !square.isImageAnnotation {
                    continue
                }

                let color = pdfAnnotation.color?.hexString ?? "#000000"
                guard let annotation = AnnotationConverter.annotation(from: pdfAnnotation, color: color, editability: .notEditable, isNew: false, isSyncable: false, username: username,
                                                                      boundingBoxConverter: self.boundingBoxConverter) else { continue }

                var annotations = allAnnotations[annotation.page] ?? []
                let index = annotations.index(of: annotation, sortedBy: { $0.sortIndex < $1.sortIndex })
                annotations.insert(annotation, at: index)
                allAnnotations[annotation.page] = annotations

                comments[annotation.key] = NSAttributedString(string: annotation.comment, attributes: [.font: font])
            }
        }
    }

    /// Loads annotations from database, groups them by page and converts comment `String`s to `NSAttributedString`s.
    /// - parameter key: Item key for which annotations are loaded.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter baseFont: Font to be used as base for `NSAttributedString`.
    /// - returns: Tuple of grouped annotations and comments.
    private func documentData(for key: String, library: Library, baseFont: UIFont, userId: Int, username: String, boundingBoxConverter: AnnotationBoundingBoxConverter) throws
                                                    -> (annotations: [Int: [Annotation]], positions: [AnnotationPosition], comments: [String: NSAttributedString], page: Int, items: Results<RItem>) {
        let coordinator = try self.dbStorage.createCoordinator()

        let page = try coordinator.perform(request: ReadDocumentDataDbRequest(attachmentKey: key, libraryId: library.identifier))
        let items = try coordinator.perform(request: ReadAnnotationsDbRequest(attachmentKey: key, libraryId: library.identifier))
        // TODO: - group editability temporarily disabled
        let editability: Annotation.Editability // = library.metadataEditable ? .editable : .notEditable
        switch library.identifier {
        case .custom:
            editability = .editable
        case .group:
            editability = .notEditable
        }

        var annotations: [Int: [Annotation]] = [:]
        var comments: [String: NSAttributedString] = [:]
        var positions: [AnnotationPosition] = []

        for item in items {
            guard let annotation = AnnotationConverter.annotation(from: item, editability: editability, currentUserId: userId,
                                                                  username: username, boundingBoxConverter: boundingBoxConverter) else { continue }

            positions.append(AnnotationPosition(page: annotation.page, key: annotation.key))

            if var array = annotations[annotation.page] {
                array.append(annotation)
                annotations[annotation.page] = array
            } else {
                annotations[annotation.page] = [annotation]
            }

            comments[annotation.key] = self.htmlAttributedStringConverter.convert(text: annotation.comment, baseFont: baseFont)
        }

        return (annotations, positions, comments, page, items)
    }
}

#endif
