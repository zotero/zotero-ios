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

extension DrawingPoint: SplittablePathPoint {
    var x: Double {
        return self.location.x
    }

    var y: Double {
        return self.location.y
    }
}

protocol AnnotationBoundingBoxConverter: AnyObject {
    func convertToDb(rect: CGRect, page: PageIndex) -> CGRect?
    func convertFromDb(rect: CGRect, page: PageIndex) -> CGRect?
    func convertToDb(point: CGPoint, page: PageIndex) -> CGPoint?
    func convertFromDb(point: CGPoint, page: PageIndex) -> CGPoint?
    func sortIndexMinY(rect: CGRect, page: PageIndex) -> CGFloat?
    func textOffset(rect: CGRect, page: PageIndex) -> Int?
}

final class PDFReaderActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = PDFReaderAction
    typealias State = PDFReaderState

    fileprivate struct PdfAnnotationChanges: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let color = PdfAnnotationChanges(rawValue: 1 << 0)
        static let comment = PdfAnnotationChanges(rawValue: 1 << 1)
        static let boundingBox = PdfAnnotationChanges(rawValue: 1 << 2)
        static let rects = PdfAnnotationChanges(rawValue: 1 << 3)
        static let lineWidth = PdfAnnotationChanges(rawValue: 1 << 4)
        static let paths = PdfAnnotationChanges(rawValue: 1 << 5)

        static func stringValues(from changes: PdfAnnotationChanges) -> [String] {
            switch changes {
            case .color: return ["alpha", "color"]
            case .comment: return ["contents"]
            case .rects: return ["rects"]
            case .boundingBox: return ["boundingBox"]
            case .lineWidth: return ["lineWidth"]
            case .paths: return ["lines"]
            default: return []
            }
        }
    }

    unowned let dbStorage: DbStorage
    private unowned let annotationPreviewController: AnnotationPreviewController
    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    private unowned let schemaController: SchemaController
    private unowned let fileStorage: FileStorage
    private unowned let idleTimerController: IdleTimerController
    let backgroundQueue: DispatchQueue
    private let disposeBag: DisposeBag

    weak var boundingBoxConverter: AnnotationBoundingBoxConverter?

    init(dbStorage: DbStorage, annotationPreviewController: AnnotationPreviewController, htmlAttributedStringConverter: HtmlAttributedStringConverter, schemaController: SchemaController,
         fileStorage: FileStorage, idleTimerController: IdleTimerController) {
        self.dbStorage = dbStorage
        self.annotationPreviewController = annotationPreviewController
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.schemaController = schemaController
        self.fileStorage = fileStorage
        self.idleTimerController = idleTimerController
        self.backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.PDFReaderActionHandler.queue", qos: .userInteractive)
        self.disposeBag = DisposeBag()
    }

    func process(action: PDFReaderAction, in viewModel: ViewModel<PDFReaderActionHandler>) {
        switch action {
        case .loadDocumentData(let boundingBoxConverter):
            self.loadDocumentData(boundingBoxConverter: boundingBoxConverter, in: viewModel)

        case .startObservingAnnotationPreviewChanges:
            self.observePreviews(in: viewModel)

        case .searchAnnotations(let term):
            self.search(for: term, in: viewModel)

        case .selectAnnotation(let key):
            guard !viewModel.state.sidebarEditingEnabled && key != viewModel.state.selectedAnnotationKey else { return }
            self.select(key: key, didSelectInDocument: false, in: viewModel)

        case .selectAnnotationFromDocument(let key):
            guard !viewModel.state.sidebarEditingEnabled && key != viewModel.state.selectedAnnotationKey else { return }
            self.select(key: key, didSelectInDocument: true, in: viewModel)

        case .deselectSelectedAnnotation:
            self.select(key: nil, didSelectInDocument: false, in: viewModel)

        case .selectAnnotationDuringEditing(let key):
            self.selectDuringEditing(key: key, in: viewModel)

        case .deselectAnnotationDuringEditing(let key):
            self.deselectDuringEditing(key: key, in: viewModel)
            
        case .annotationsAdded(let annotations, let selectFirst): break
//            self.add(annotations: annotations, selectFirst: selectFirst, in: viewModel)

        case .removeAnnotation(let position): break
//            self.remove(at: position, in: viewModel)

        case .removeSelectedAnnotations: break
//            guard viewModel.state.sidebarEditingEnabled else { return }
//            self.removeSelectedAnnotations(in: viewModel)

        case .mergeSelectedAnnotations: break
//            guard viewModel.state.sidebarEditingEnabled else { return }
//            self.mergeSelectedAnnotations(in: viewModel)

        case .requestPreviews(let keys, let notify):
            self.loadPreviews(for: keys, notify: notify, in: viewModel)

        case .setHighlight(let key, let highlight): break
//            self.updateAnnotation(with: key, transformAnnotation: { ($0.copy(text: highlight), []) }, in: viewModel)

        case .setComment(let key, let comment): break
//            let convertedComment = self.htmlAttributedStringConverter.convert(attributedString: comment)
//            self.updateAnnotation(with: key,
//                                  transformAnnotation: { ($0.copy(comment: convertedComment), .comment) },
//                                  shouldReload: { _, _ in false }, // doesn't need reload, text is already written in textView in cell
//                                  additionalStateChange: { $0.comments[key] = comment },
//                                  in: viewModel)

        case .setColor(let key, let color): break
//            self.updateAnnotation(with: key,
//                                  transformAnnotation: { originalAnnotation in
//                                      let changes: PdfAnnotationChanges = originalAnnotation.color != color ? .color : []
//                                      return (originalAnnotation.copy(color: color), changes)
//                                  },
//                                  in: viewModel)

        case .setLineWidth(let key, let width): break
//            self.updateAnnotation(with: key,
//                                  transformAnnotation: { originalAnnotation in
//                                      let changes: PdfAnnotationChanges = originalAnnotation.lineWidth != width ? .lineWidth : []
//                                      return (originalAnnotation.copy(lineWidth: width), changes)
//                                  },
//                                  in: viewModel)

        case .setCommentActive(let isActive): break
//            guard viewModel.state.selectedAnnotation != nil else { return }
//            self.update(viewModel: viewModel) { state in
//                state.selectedAnnotationCommentActive = isActive
//                state.changes = .activeComment
//            }

        case .setTags(let key, let tags): break
//            self.updateAnnotation(with: key, transformAnnotation: { ($0.copy(tags: tags), []) }, in: viewModel)

        case .updateAnnotationProperties(let annotation): break
//            self.updateAnnotation(with: annotation.key,
//                                  transformAnnotation: { originalAnnotation in
//                                    var changes: PdfAnnotationChanges = []
//                                    if originalAnnotation.color != annotation.color {
//                                        changes.insert(.color)
//                                    }
//                                    if originalAnnotation.lineWidth != annotation.lineWidth {
//                                        changes.insert(.lineWidth)
//                                    }
//                                    return (annotation, changes)
//                                  },
//                                  in: viewModel)

        case .userInterfaceStyleChanged(let interfaceStyle):
            self.userInterfaceChanged(interfaceStyle: interfaceStyle, in: viewModel)

        case .updateAnnotationPreviews:
            self.storeAnnotationPreviewsIfNeeded(in: viewModel)

        case .setActiveColor(let hex):
            self.setActiveColor(hex: hex, in: viewModel)

        case .setActiveLineWidth(let lineWidth):
            self.setActive(lineWidth: lineWidth, in: viewModel)

        case .setActiveEraserSize(let size):
            self.setActive(eraserSize: size, in: viewModel)

        case .create(let annotation, let pageIndex, let origin): break
            self.add(annotationType: annotation, pageIndex: pageIndex, origin: origin, in: viewModel)

        case .setVisiblePage(let page):
            self.set(page: page, in: viewModel)

        case .export:
            self.export(viewModel: viewModel)

        case .clearTmpAnnotationPreviews:
            self.clearTmpAnnotationPreviews(in: viewModel)

        case .setSettings(let settings):
            self.update(settings: settings, in: viewModel)

        case .changeIdleTimerDisabled(let disabled):
            var settings = viewModel.state.settings
            settings.idleTimerDisabled = disabled
            self.update(settings: settings, in: viewModel)

        case .setSidebarEditingEnabled(let enabled):
            self.setSidebar(editing: enabled, in: viewModel)

        case .changeFilter(let filter):
            self.set(filter: filter, in: viewModel)
        }
    }

    private func selectDuringEditing(key: PDFReaderState.AnnotationKey, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: key) else { return }

        let annotationDeletable = annotation.isSyncable && annotation.editability(currentUserId: viewModel.state.userId, library: viewModel.state.library) != .notEditable

        self.update(viewModel: viewModel) { state in
            if state.selectedAnnotationsDuringEditing.isEmpty {
                state.deletionEnabled = annotationDeletable
            } else {
                state.deletionEnabled = state.deletionEnabled && annotationDeletable
            }

            state.selectedAnnotationsDuringEditing.insert(key)

            if state.selectedAnnotationsDuringEditing.count == 1 {
                state.mergingEnabled = false
            } else {
                state.mergingEnabled = self.selectedAnnotationsMergeable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)
            }

            state.changes = .sidebarEditingSelection
        }
    }

    private func deselectDuringEditing(key: PDFReaderState.AnnotationKey, in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.selectedAnnotationsDuringEditing.remove(key)

            if state.selectedAnnotationsDuringEditing.isEmpty {
                if state.deletionEnabled {
                    state.deletionEnabled = false
                    state.changes = .sidebarEditingSelection
                }

                if state.mergingEnabled {
                    state.mergingEnabled = false
                    state.changes = .sidebarEditingSelection
                }
            } else {
                // Check whether deletion state changed after removing this annotation
                let deletionEnabled = self.selectedAnnotationsDeletable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)

                if state.deletionEnabled != deletionEnabled {
                    state.deletionEnabled = deletionEnabled
                    state.changes = .sidebarEditingSelection
                }

                if state.selectedAnnotationsDuringEditing.count == 1 {
                    if state.mergingEnabled {
                        state.mergingEnabled = false
                        state.changes = .sidebarEditingSelection
                    }
                } else {
                    state.mergingEnabled = self.selectedAnnotationsMergeable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)
                    state.changes = .sidebarEditingSelection
                }
            }
        }
    }

    private func selectedAnnotationsMergeable(selected: Set<PDFReaderState.AnnotationKey>, in viewModel: ViewModel<PDFReaderActionHandler>) -> Bool {
        var page: Int? = nil
        var type: AnnotationType?
        var color: String?
//        var rects: [CGRect]?

        let hasSameProperties: (Annotation) -> Bool = { annotation in
            // Check whether annotations of one type are selected
            if let type = type {
                if type != annotation.type {
                    return false
                }
            } else {
                type = annotation.type
            }
            // Check whether annotations of one color are selected
            if let color = color {
                if color != annotation.color {
                    return false
                }
            } else {
                color = annotation.color
            }
            return true
        }

        for key in selected {
            guard let annotation = viewModel.state.annotation(for: key) else { continue }
            guard annotation.isSyncable else { return false }

            if let page = page {
                // Only 1 page can be selected
                if page != annotation.page {
                    return false
                }
            } else {
                page = annotation.page
            }

            switch annotation.type {
            case .ink:
                if !hasSameProperties(annotation) {
                    return false
                }

            case .highlight:
                return false
//                if !hasSameProperties(annotation) {
//                    return false
//                }
//                // Check whether rects are overlapping
//                if let rects = rects {
//                    if !self.rects(rects: rects, hasIntersectionWith: annotation.rects) {
//                        return false
//                    }
//                } else {
//                    rects = annotation.rects
//                }

            case .note, .image:
                return false
            }
        }

        return true
    }
//
//    private func rects(rects lRects: [CGRect], hasIntersectionWith rRects: [CGRect]) -> Bool {
//        for rect in lRects {
//            if rRects.contains(where: { $0.intersects(rect) }) {
//                return true
//            }
//        }
//        return false
//    }
//
    private func selectedAnnotationsDeletable(selected: Set<PDFReaderState.AnnotationKey>, in viewModel: ViewModel<PDFReaderActionHandler>) -> Bool {
        return selected.first(where: { key in
            guard let annotation = viewModel.state.annotation(for: key) else { return false }
            return !annotation.isSyncable || annotation.editability(currentUserId: viewModel.state.userId, library: viewModel.state.library) == .notEditable
        }) == nil
    }

    private func setSidebar(editing enabled: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.sidebarEditingEnabled = enabled
            state.changes = .sidebarEditing

            if enabled {
                // Deselect selected annotation before editing
                self._select(key: nil, didSelectInDocument: false, state: &state)
            } else {
                // Deselect selected annotations during editing
                state.selectedAnnotationsDuringEditing = []
                state.deletionEnabled = false
            }
        }
    }

    private func update(settings: PDFSettings, in viewModel: ViewModel<PDFReaderActionHandler>) {
        if viewModel.state.settings.idleTimerDisabled != settings.idleTimerDisabled {
            if settings.idleTimerDisabled {
                self.idleTimerController.disable()
            } else {
                self.idleTimerController.enable()
            }
        }

        // Update local state
        self.update(viewModel: viewModel) { state in
            state.settings = settings
            state.changes = .settings
        }
        // Store new settings to defaults
        Defaults.shared.pdfSettings = settings
    }

//    private func updateDbPositions(objects: Results<RItem>, deletions: [Int], insertions: [Int], in viewModel: ViewModel<PDFReaderActionHandler>) {
//        guard !deletions.isEmpty || !insertions.isEmpty else { return }
//
//        self.update(viewModel: viewModel) { state in
//            deletions.reversed().forEach({ state.dbPositions.remove(at: $0) })
//            if !deletions.isEmpty {
//                DDLogInfo("PDFReaderActionHandler: removed dbPositions (\(state.dbPositions.count))")
//            }
//            for idx in insertions {
//                let item = objects[idx]
//                guard let page = item.fields.filter(.key(FieldKeys.Item.Annotation.Position.pageIndex)).first.flatMap({ Int($0.value) }) else { continue }
//                state.dbPositions.insert(AnnotationPosition(page: page, key: item.key), at: idx)
//            }
//            if !insertions.isEmpty {
//                DDLogInfo("PDFReaderActionHandler: inserted dbPositions (\(state.dbPositions.count))")
//            }
//        }
//    }
//
//    private func syncItems(from results: Results<RItem>, to viewModel: ViewModel<PDFReaderActionHandler>, modifications: [Int], insertions: [Int], deletions: [Int]) {
//        guard let boundingBoxConverter = self.boundingBoxConverter else { return }
//
//        let originalAnnotationKeys = viewModel.state.annotationKeys.values.flatMap({ $0 })
//        let originalAnnotations = originalAnnotationKeys.compactMap({ viewModel.state.annotations[$0] })
//
//        // Check whether anything changed or the db is just catching up to in-memory state.
//        guard self.annotations(originalAnnotations, didChangeFrom: results, withReportedModifications: modifications, insertions: insertions, deletions: deletions,
//                               boundingBoxConverter: boundingBoxConverter, viewModel: viewModel) else { return }
//
//
//
////        var insertedAnnotations: [String: Annotation] = [:]
////        var removedAnnotations: [Int: [String]] = [:]
////        var dbKeys: [Int: [String]] = []
////
////        if hasInsertionOrDeletion {
////            let memoryKeys = viewModel.state.annotationKeys
////
////            // Created key arrays grouped by page which we can diff to memory state. Cache created annotations for later use
////            for item in results {
////                let annotation: Annotation
////
////                if let _annotation = viewModel.state.annotations[item.key] {
////                    annotation = _annotation
////                } else if let _annotation = AnnotationConverter.annotation(from: item, library: viewModel.state.library, currentUserId: viewModel.state.userId, username: viewModel.state.username,
////                                                                          displayName: viewModel.state.displayName, boundingBoxConverter: boundingBoxConverter) {
////                    insertedAnnotations[_annotation.key] = _annotation
////                    annotation = _annotation
////                } else {
////                    continue
////                }
////
////                if var annotations = dbKeys[annotation.page] {
////                    annotations.append(annotation)
////                } else {
////                    dbKeys[annotation.page] = [annotation]
////                }
////            }
////
////            for element in dbKeys {
////                let diff = dbKeys.difference(from: memoryKeys)
////
////                for transaction in diff {
////                    switch transaction {
////                    case .insert(let offset, let element, _):
////                        removedAnnotations[element] = nil
////
////                    case .remove(let offset, let element, _):
////                        guard let annotation = viewModel.state.annotations[element] else { continue }
////                        removedAnnotations[element] = annotation
////                    }
////                }
////            }
////        }
//
////        var deletedAnnotations: [PSPDFKit.Annotation] = []
////        var addedAnnotations: [Annotation] = []
////        var modifiedAnnotations: [(PSPDFKit.Annotation, Annotation, PdfAnnotationChanges)] = []
////        var modifiedKeys: Set<String> = []
////
////        self.update(viewModel: viewModel) { state in
////            // Modify existing annotations
////            for idx in Database.correctedModifications(from: modifications, insertions: insertions, deletions: deletions) {
////                let item = results[idx]
////                guard !state.deletedKeys.contains(item.key), // If annotation was deleted, it'll be stored as deleted anyway or CR will happen
////                      let boundingBoxConverter = self.boundingBoxConverter,
////                      let annotation = AnnotationConverter.annotation(from: item, library: viewModel.state.library, currentUserId: state.userId,
////                                                                      username: state.username, displayName: state.displayName, boundingBoxConverter: boundingBoxConverter) else { continue }
////
////                // Modify annotation in all annotations
////                guard let changes = self.modify(annotation: annotation, in: &state.annotations) else { continue }
////
////                if !changes.isEmpty, let pdfAnnotation = state.document.annotations(at: PageIndex(annotation.page)).first(where: { $0.key == annotation.key }) {
////                    modifiedAnnotations.append((pdfAnnotation, annotation, changes))
////                    modifiedKeys.insert(annotation.key)
////                }
////
////                state.comments[annotation.key] = self.htmlAttributedStringConverter.convert(text: annotation.comment, baseAttributes: [.font: state.commentFont])
////            }
////            state.ignoreNotifications[.PSPDFAnnotationChanged] = modifiedKeys
////
////            // Delete annotations
////            var deletedKeys: Set<String> = []
////            for idx in deletions {
////                let position = state.dbPositions[idx]
////
////                if let annotation = state.document.annotations(at: PageIndex(position.page)).first(where: { $0.key == position.key }) {
////                    deletedAnnotations.append(annotation)
////                    deletedKeys.insert(position.key)
////                }
////
////                state.comments[position.key] = nil
////                state.deletedKeys.remove(position.key)
////
////                if state.selectedAnnotationKey == position.key {
////                    state.selectedAnnotationKey = nil
////                    state.changes.insert(.selection)
////
////                    if state.selectedAnnotationCommentActive {
////                        state.selectedAnnotationCommentActive = false
////                        state.changes.insert(.activeComment)
////                    }
////                }
////
////                if var snapshot = state.annotationKeysSnapshot {
////                    // If search is active, try removing in snapshot
////                    guard self.remove(at: position, from: &snapshot, annotations: &state.annotations) else { continue }
////                    state.annotationKeysSnapshot = snapshot
////                    // If annotation was found in snapshot, try removing in search results as well
////                    self.remove(at: position, from: &state.annotationKeys, annotations: &state.annotations)
////                } else {
////                    // If search is not active, remove index path from all annotations
////                    guard self.remove(at: position, from: &state.annotationKeys, annotations: &state.annotations) else { continue }
////                }
////            }
////
////            state.ignoreNotifications[.PSPDFAnnotationsRemoved] = deletedKeys
////
////            // Add new annotations
////            var insertedKeys: Set<String> = []
////            for idx in insertions {
////                guard let boundingBoxConverter = self.boundingBoxConverter,
////                      let annotation = AnnotationConverter.annotation(from: results[idx], library: viewModel.state.library, currentUserId: state.userId,
////                                                                      username: state.username, displayName: state.displayName, boundingBoxConverter: boundingBoxConverter) else { continue }
////                addedAnnotations.append(annotation)
////                insertedKeys.insert(annotation.key)
////            }
////            self.add(annotations: addedAnnotations, to: &state, selectFirst: false)
////            state.ignoreNotifications[.PSPDFAnnotationsAdded] = insertedKeys
////
////            if !modifiedKeys.isEmpty || !deletedKeys.isEmpty || !insertedKeys.isEmpty {
////                state.changes.insert(.annotations)
////            }
////        }
////
////        // Update the document
////
////        if !modifiedAnnotations.isEmpty {
////            for (pdfAnnotation, annotation, changes) in modifiedAnnotations {
////                self.update(pdfAnnotation: pdfAnnotation, with: annotation, changes: changes, state: viewModel.state)
////            }
////        }
////
////        if !deletedAnnotations.isEmpty {
////            viewModel.state.document.remove(annotations: deletedAnnotations, options: nil)
////        }
////
////        if !addedAnnotations.isEmpty {
////            // Convert Zotero annotations to PSPDFKit annotations
////            let annotations = addedAnnotations.map({ AnnotationConverter.annotation(from: $0, type: .zotero, interfaceStyle: viewModel.state.interfaceStyle) })
////            // Add them to document, suppress notifications
////            viewModel.state.document.add(annotations: annotations, options: nil)
////            // Store preview for image annotations
////            let isDark = viewModel.state.interfaceStyle == .dark
////            annotations.forEach { annotation in
////                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, isDark: isDark)
////            }
////        }
//    }
//
//    private func annotations(_ originalAnnotations: [Annotation], didChangeFrom results: Results<RItem>, withReportedModifications modifications: [Int], insertions: [Int], deletions: [Int],
//                                boundingBoxConverter: AnnotationBoundingBoxConverter, viewModel: ViewModel<PDFReaderActionHandler>) -> Bool {
//        if insertions.isEmpty && deletions.isEmpty {
//            // If there are no insertions and deletions, check whether modified objects actually changed.
//            for idx in modifications {
//                guard let dbAnnotation = AnnotationConverter.annotation(from: results[idx], library: viewModel.state.library, currentUserId: viewModel.state.userId, username: viewModel.state.username,
//                                                                        displayName: viewModel.state.displayName, boundingBoxConverter: boundingBoxConverter) else {
//                    // If annotation can't be created and it existed before, report a change.
//                    return true
//                }
//                let memoryAnnotation = originalAnnotations[idx]
//
//                if memoryAnnotation.dateModified != dbAnnotation.dateModified {
//                    return true
//                }
//            }
//
//            return false
//        }
//
//        // If there are insertions or deletions reported by db, check whether keys changed between db and memory.
//        var idx = 0
//        for item in results {
//            if idx >= originalAnnotations.count - 1 {
//                // Db has more annotations than memory, found a change.
//                return true
//            }
//            if item.key != originalAnnotations[idx].key {
//                // Found a change.
//                return true
//            }
//            idx += 1
//        }
//
//        // There are more keys in memory than in db, found a change.
//        if idx != originalAnnotations.count {
//            return true
//        }
//
//        return false
//    }
//
//    /// Modifies dictionary of annotations if given annotation can be found and differs from existing annotation.
//    /// - parameter annotation: Modified annotation.
//    /// - parameter annotations: Dictionary of existing annotations.
//    /// - returns: Index path of annotation if it was found and was different from existing annotation.
//    @discardableResult
//    private func modify(annotation: Annotation, in annotations: inout [String: Annotation]) -> PdfAnnotationChanges? {
//        guard let oldAnnotation = annotations[annotation.key], oldAnnotation != annotation else { return nil }
//
//        annotations[annotation.key] = annotation
//
//        var changes: PdfAnnotationChanges = []
//
//        if oldAnnotation.color != annotation.color {
//            changes.insert(.color)
//        }
//
//        if oldAnnotation.comment != annotation.comment {
//            changes.insert(.comment)
//        }
//
//        switch annotation.type {
//        case .highlight:
//            if oldAnnotation.boundingBox != annotation.boundingBox || oldAnnotation.rects != annotation.rects {
//                changes.insert(.boundingBox)
//                changes.insert(.rects)
//            }
//
//        case .ink:
//            if oldAnnotation.paths != annotation.paths {
//                changes.insert(.paths)
//            }
//
//            if oldAnnotation.lineWidth != annotation.lineWidth {
//                changes.insert(.lineWidth)
//            }
//
//        case .image, .note:
//            if oldAnnotation.boundingBox != annotation.boundingBox {
//                changes.insert(.boundingBox)
//            }
//        }
//
//        return changes
//    }
//
//    @discardableResult
//    private func remove(at position: AnnotationPosition, from annotationKeys: inout [Int: [String]], annotations: inout [String: Annotation]) -> Bool {
//        guard var pageKeys = annotationKeys[position.page],
//              let pageIdx = pageKeys.firstIndex(where: { $0 == position.key }) else { return false }
//        pageKeys.remove(at: pageIdx)
//        annotationKeys[position.page] = pageKeys
//        annotations[position.key] = nil
//        return true
//    }

    private func set(page: Int, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard viewModel.state.visiblePage != page else { return }

        self.update(viewModel: viewModel) { state in
            state.visiblePage = page
        }

        let request = StorePageForItemDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, page: page)
        self.perform(request: request) { error in
            guard let error = error else { return }
            // TODO: - handle error
            DDLogError("PDFReaderActionHandler: can't store page - \(error)")
        }
    }

    private func export(viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let boundingBoxConverter = self.boundingBoxConverter, let url = viewModel.state.document.fileURL else { return }

        self.update(viewModel: viewModel) { state in
            state.exportState = .preparing
            state.changes.insert(.export)
        }

        let annotations = AnnotationConverter.annotations(from: viewModel.state.databaseAnnotations, type: .export, interfaceStyle: .light, currentUserId: viewModel.state.userId,
                                                          library: viewModel.state.library, displayName: viewModel.state.displayName, username: viewModel.state.username, boundingBoxConverter: boundingBoxConverter)
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
                state.changes.insert(.export)
            case .failure(let error):
                state.exportState = .failed(error)
                state.changes.insert(.export)
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

            for (_, annotations) in state.document.allAnnotations(of: AnnotationsConfig.supported) {
                for annotation in annotations {
                    let (color, alpha, blendMode) = AnnotationColorGenerator.color(from: UIColor(hex: annotation.baseColor), isHighlight: (annotation is PSPDFKit.HighlightAnnotation), userInterfaceStyle: interfaceStyle)
                    annotation.color = color
                    annotation.alpha = alpha
                    if let blendMode = blendMode {
                        annotation.blendMode = blendMode
                    }
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
                guard annotation.shouldRenderPreview && annotation.isZoteroAnnotation &&
                      !self.annotationPreviewController.hasPreview(for: annotation.previewId, parentKey: viewModel.state.key, libraryId: libraryId, isDark: isDark) else { continue }
                self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: libraryId, isDark: isDark)
            }
        }

        self.update(viewModel: viewModel) { state in
            state.shouldStoreAnnotationPreviewsIfNeeded = false
        }
    }

//    // MARK: - Annotation actions
//
//    private func saveChanges(in viewModel: ViewModel<PDFReaderActionHandler>) {
//        guard let boundingBoxConverter = self.boundingBoxConverter else { return }
//
//        let key = viewModel.state.key
//        let libraryId = viewModel.state.library.identifier
//        let deletedKeys = viewModel.state.deletedKeys
//
//        var resetAnnotations: [String: Annotation] = viewModel.state.annotations
//        var annotationsToSubmit: [Annotation] = []
//
//        for (key, annotation) in viewModel.state.annotations {
//            if annotation.isSyncable {
//                annotationsToSubmit.append(annotation)
//            }
//
//            if annotation.didChange {
//                resetAnnotations[key] = annotation.copy(didChange: false)
//            }
//        }
//
//        self.update(viewModel: viewModel) { state in
//            state.annotations = resetAnnotations
//            state.deletedKeys = []
//            state.insertedKeys = []
//            state.modifiedKeys = []
//        }
//
//        let request = StoreChangedAnnotationsDbRequest(attachmentKey: key, libraryId: libraryId, annotations: annotationsToSubmit, deletedKeys: deletedKeys,
//                                                       schemaController: self.schemaController, boundingBoxConverter: boundingBoxConverter)
//        self.perform(request: request) { error in
//            guard let error = error else { return }
//            // TODO: - Show error
//            DDLogError("PDFReaderActionHandler: can't store changed annotations - \(error)")
//        }
//    }

    private func setActiveColor(hex: String, in viewModel: ViewModel<PDFReaderActionHandler>) {
        Defaults.shared.activeColorHex = hex

        self.update(viewModel: viewModel) { state in
            state.activeColor = UIColor(hex: hex)
            state.changes = .activeColor
        }
    }

    private func setActive(lineWidth: CGFloat, in viewModel: ViewModel<PDFReaderActionHandler>) {
        Defaults.shared.activeLineWidth = Float(lineWidth)

        self.update(viewModel: viewModel) { state in
            state.activeLineWidth = lineWidth
            state.changes = .activeLineWidth
        }
    }

    private func setActive(eraserSize: CGFloat, in viewModel: ViewModel<PDFReaderActionHandler>) {
        Defaults.shared.activeEraserSize = Float(eraserSize)

        self.update(viewModel: viewModel) { state in
            state.activeEraserSize = eraserSize
            state.changes = .activeEraserSize
        }
    }

//    private func updateAnnotation(with key: String,
//                                  transformAnnotation: (Annotation) -> (Annotation, PdfAnnotationChanges),
//                                  shouldReload: ((Annotation, Annotation) -> Bool)? = nil,
//                                  additionalStateChange: ((inout PDFReaderState) -> Void)? = nil,
//                                  in viewModel: ViewModel<PDFReaderActionHandler>) {
//        guard let annotation = viewModel.state.annotations[key] else { return }
//
//        let (newAnnotation, changes) = transformAnnotation(annotation)
//        let shouldReload = shouldReload?(annotation, newAnnotation) ?? true
//
//        self.update(viewModel: viewModel) { state in
//            self.update(state: &state, with: newAnnotation, from: annotation, shouldReload: shouldReload)
//            additionalStateChange?(&state)
//        }
//
//        if let pdfAnnotation = viewModel.state.document.annotations(at: UInt(annotation.page)).first(where: { $0.syncable && $0.key == annotation.key }) {
//            viewModel.state.document.undoController.recordCommand(named: nil, changing: [pdfAnnotation]) {
//                self.update(pdfAnnotation: pdfAnnotation, with: newAnnotation, changes: changes, state: viewModel.state)
//            }
//        }
//    }
//
//    private func update(state: inout PDFReaderState, with annotation: Annotation, from oldAnnotation: Annotation, shouldReload: Bool) {
//        if !state.insertedKeys.contains(annotation.key) {
//            state.modifiedKeys.insert(annotation.key)
//        }
//
//        state.annotations[oldAnnotation.key] = annotation
//        state.changes.insert(.save)
//
//        // If sort index didn't change, reload in place
//        if annotation.sortIndex == oldAnnotation.sortIndex {
//            if shouldReload {
//                var updated = state.updatedAnnotationKeys ?? []
//                updated.append(annotation.key)
//                state.updatedAnnotationKeys = updated
//                state.changes.insert(.annotations)
//            }
//            return
//        }
//
//        // Otherwise move the annotation to appropriate position
//        var keys = state.annotationKeys[oldAnnotation.page] ?? []
//        if let index = keys.firstIndex(of: oldAnnotation.key) {
//            keys.remove(at: index)
//        }
//        let newIndex = keys.index(of: annotation.key, sortedBy: { lKey, rKey in
//            guard let lAnnotation = state.annotations[lKey], let rAnnotation = state.annotations[rKey] else { return false }
//            return lAnnotation.sortIndex < rAnnotation.sortIndex
//        })
//        keys.insert(annotation.key, at: newIndex)
//        state.annotationKeys[oldAnnotation.page] = keys
//
//        state.focusSidebarKey = annotation.key
//        state.changes.insert(.annotations)
//    }
//
//
//    /// Updates corresponding Zotero annotation to updated PSPDFKit annotation in document.
//    /// - parameter annotation: Updated PSPDFKit annotation.
//    /// - parameter viewModel: ViewModel.
//    private func update(annotation pdfAnnotation: PSPDFKit.Annotation, in viewModel: ViewModel<PDFReaderActionHandler>) {
//        guard pdfAnnotation.syncable, let key = pdfAnnotation.key else { return }
//
//        let sortIndex = AnnotationConverter.sortIndex(from: pdfAnnotation, boundingBoxConverter: self.boundingBoxConverter)
//        let rects = (pdfAnnotation.rects ?? [pdfAnnotation.boundingBox]).map({ $0.rounded(to: 3) })
//        let highlightText = ((pdfAnnotation as? PSPDFKit.HighlightAnnotation)?.markedUpString).flatMap({ AnnotationConverter.removeNewlines(from: $0) })
//        var paths: [[CGPoint]] = []
//        var lineWidth: CGFloat?
//        if let inkAnnotation = pdfAnnotation as? PSPDFKit.InkAnnotation {
//            paths = inkAnnotation.lines.flatMap({ paths in return paths.map({ path in return path.map({ $0.location.rounded(to: 3) }) }) }) ?? []
//            lineWidth = inkAnnotation.lineWidth
//        }
//
//        self.updateAnnotation(with: key,
//                              transformAnnotation: { original in
//                                var new = original
//                                if rects != original.rects {
//                                    new = new.copy(rects: rects, sortIndex: sortIndex)
//                                }
//                                if paths != original.paths {
//                                    new = new.copy(paths: paths)
//                                }
//                                if lineWidth != original.lineWidth {
//                                    new = new.copy(lineWidth: lineWidth)
//                                }
//                                if original.text != highlightText {
//                                    new = new.copy(text: highlightText)
//                                }
//                                return (new, [])
//                              },
//                              shouldReload: { original, new in
//                                  // Reload only if aspect ratio or text changed.
//                                  return Decimal(original.boundingBox.heightToWidthRatio).rounded(to: 2) != Decimal(new.boundingBox.heightToWidthRatio).rounded(to: 2) || original.text != new.text
//                              },
//                              in: viewModel)
//
//        if pdfAnnotation.shouldRenderPreview {
//            // Remove cached annotation preview.
//            viewModel.state.previewCache.removeObject(forKey: (key as NSString))
//            // Cache new preview.
//            self.annotationPreviewController.store(for: pdfAnnotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, isDark: (viewModel.state.interfaceStyle == .dark))
//        }
//    }
//
//    /// Removes Zotero annotation from document.
//    /// - parameter position: Annotation position (key and page) to remove.
//    /// - parameter viewModel: ViewModel.
//    private func remove(at position: AnnotationPosition, in viewModel: ViewModel<PDFReaderActionHandler>) {
//        guard let documentAnnotation = viewModel.state.document.annotations(at: UInt(position.page)).first(where: { $0.syncable && $0.key == position.key }) else { return }
//
//        viewModel.state.document.undoController.recordCommand(named: nil, removing: [documentAnnotation]) {
//            if documentAnnotation.flags.contains(.readOnly) {
//                documentAnnotation.flags.remove(.readOnly)
//            }
//            viewModel.state.document.remove(annotations: [documentAnnotation], options: nil)
//        }
//    }
//
//    private func removeSelectedAnnotations(in viewModel: ViewModel<PDFReaderActionHandler>) {
//        let toDelete = self.syncableDocumentAnnotations(from: viewModel.state.selectedAnnotationsDuringEditing, all: viewModel.state.annotations, document: viewModel.state.document)
//
//        guard !toDelete.isEmpty else { return }
//
//        viewModel.state.document.undoController.recordCommand(named: nil, removing: toDelete) {
//            for annotation in toDelete {
//                if annotation.flags.contains(.readOnly) {
//                    annotation.flags.remove(.readOnly)
//                }
//            }
//            viewModel.state.document.remove(annotations: toDelete, options: nil)
//        }
//
//        self.update(viewModel: viewModel) { state in
//            state.mergingEnabled = false
//            state.deletionEnabled = false
//            state.selectedAnnotationsDuringEditing = []
//            state.changes = .sidebarEditingSelection
//        }
//    }
//
//    private func mergeSelectedAnnotations(in viewModel: ViewModel<PDFReaderActionHandler>) {
//        guard self.selectedAnnotationsMergeable(selected: viewModel.state.selectedAnnotationsDuringEditing, all: viewModel.state.annotations) else { return }
//
//        let toMerge = self.sortedSyncableAnnotationsAndDocumentAnnotations(from: viewModel.state.selectedAnnotationsDuringEditing, all: viewModel.state.annotations, document: viewModel.state.document)
//
//        guard toMerge.count > 1, let oldest = toMerge.first else { return }
//
//        switch oldest.0.type {
//        case .ink:
//            self.merge(inkAnnotations: toMerge, in: viewModel)
//        case .highlight: break
////            self.merge(highlightAnnotations: toMerge, in: viewModel)
//        default: break
//        }
//
//        self.update(viewModel: viewModel) { state in
//            state.mergingEnabled = false
//            state.deletionEnabled = false
//            state.selectedAnnotationsDuringEditing = []
//            state.changes = .sidebarEditingSelection
//        }
//    }
//
//    typealias InkAnnotatationsData = (oldestAnnotation: Annotation, oldestDocumentAnnotation: PSPDFKit.InkAnnotation, lines: [[DrawingPoint]], lineWidth: CGFloat, tags: [Tag])
//
//    private func merge(inkAnnotations annotations: [(Annotation, PSPDFKit.Annotation)], in viewModel: ViewModel<PDFReaderActionHandler>) {
//        guard let (oldestAnnotation, oldestInkAnnotation, lines, lineWidth, tags) = self.collectInkAnnotationData(from: annotations, in: viewModel) else { return }
//
//        let toDeleteDocumentAnnotations = annotations.dropFirst().map({ $0.1 })
//        let toDeleteKeys = toDeleteDocumentAnnotations.compactMap({ $0.key })
//
//        self.update(viewModel: viewModel) { state in
//            state.ignoreNotifications[.PSPDFAnnotationsRemoved] = Set(toDeleteKeys)
//            state.ignoreNotifications[.PSPDFAnnotationChanged] = [oldestAnnotation.key]
//        }
//
//        viewModel.state.document.undoController.recordCommand(named: nil, in: { recorder in
//            recorder.record(changing: [oldestInkAnnotation]) {
//                oldestInkAnnotation.lines = lines
//                oldestInkAnnotation.lineWidth = lineWidth
//            }
//
//            recorder.record(removing: toDeleteDocumentAnnotations) {
//                viewModel.state.document.remove(annotations: toDeleteDocumentAnnotations)
//            }
//        })
//
//        let paths = lines.map({ group in return group.map({ CGPoint(x: $0.location.x, y: $0.location.y) }) })
//        let updatedAnnotation = oldestAnnotation.copy(tags: tags).copy(paths: paths).copy(lineWidth: lineWidth)//.copy(comment: comment)
////        let attributedComment = self.htmlAttributedStringConverter.convert(text: comment, baseAttributes: [.font: viewModel.state.commentFont])
//
//        self.update(viewModel: viewModel) { state in
//            self.update(state: &state, with: updatedAnnotation, from: oldestAnnotation, shouldReload: true)
////            state.comments[updatedAnnotation.key] = attributedComment
//            self.remove(annotations: toDeleteDocumentAnnotations, from: &state)
//            state.previewCache.removeObject(forKey: (updatedAnnotation.key as NSString))
//            for key in toDeleteKeys {
//                state.previewCache.removeObject(forKey: (key as NSString))
//            }
//        }
//
//        let isDark = viewModel.state.interfaceStyle == .dark
//        self.annotationPreviewController.store(for: oldestInkAnnotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, isDark: isDark)
//    }
//
//    private func collectInkAnnotationData(from annotations: [(Annotation, PSPDFKit.Annotation)], in viewModel: ViewModel<PDFReaderActionHandler>) -> InkAnnotatationsData? {
//        guard let (oldestAnnotation, oldestDocumentAnnotation) = annotations.first, let oldestInkAnnotation = oldestDocumentAnnotation as? PSPDFKit.InkAnnotation else { return nil }
//
//        var lines: [[DrawingPoint]] = oldestInkAnnotation.lines ?? []
//        var lineWidthData: [CGFloat: (Int, Date)] = [oldestInkAnnotation.lineWidth: (1, (oldestInkAnnotation.creationDate ?? Date(timeIntervalSince1970: 0)))]
//        // TODO: - enable comment merging when ink annotations support commenting
////        var comment = oldestAnnotation.comment
//        var tags: [Tag] = oldestAnnotation.tags
//
//        for (annotation, documentAnnotation) in annotations.dropFirst() {
//            guard let inkAnnotation = documentAnnotation as? PSPDFKit.InkAnnotation else { continue }
//
//            if let _lines = inkAnnotation.lines {
//                lines.append(contentsOf: _lines)
//            }
//
//            if let (count, date) = lineWidthData[documentAnnotation.lineWidth] {
//                var newDate = date
//                if let annotationDate = documentAnnotation.creationDate, annotationDate.compare(date) == .orderedAscending {
//                    newDate = annotationDate
//                }
//                lineWidthData[documentAnnotation.lineWidth] = ((count + 1), newDate)
//            } else {
//                lineWidthData[documentAnnotation.lineWidth] = (1, (documentAnnotation.creationDate ?? Date(timeIntervalSince1970: 0)))
//            }
//
////            comment += "\n\n" + annotation.comment
//
//            for tag in annotation.tags {
//                if !tags.contains(tag) {
//                    tags.append(tag)
//                }
//            }
//        }
//
//        return (oldestAnnotation, oldestInkAnnotation, lines, self.chooseMergedLineWidth(from: lineWidthData), tags)
//    }
//
//    /// Choose line width based on 2 properties. 1. Choose line width which was used the most times. If multiple line widths were used the same amount of time, pick line width with oldest annotation.
//    /// - parameter lineWidthData: Line widths data collected from annotations. It contains count of usage and date of oldest annotation grouped by lineWidth.
//    /// - returns: Best line width based on above properties.
//    private func chooseMergedLineWidth(from lineWidthData: [CGFloat: (Int, Date)]) -> CGFloat {
//        if lineWidthData.count == 0 {
//            // Should never happen
//            return 1
//        }
//        if lineWidthData.keys.count == 1, let width = lineWidthData.keys.first {
//            return width
//        }
//
//        var data: [(CGFloat, Int, Date)] = []
//        for (key, value) in lineWidthData {
//            data.append((key, value.0, value.1))
//        }
//
//        data.sort { lData, rData in
//            if lData.1 != rData.1 {
//                // If counts differ, sort in descending order.
//                return lData.1 > rData.1
//            }
//
//            // Otherwise sort by date in ascending order.
//
//            if lData.2 == rData.2 {
//                // If dates are the same, just pick one
//                return true
//            }
//
//            return lData.2.compare(rData.2) == .orderedAscending
//        }
//
//        return data[0].0
//    }
//
////    private func merge(highlightAnnotations annotations: [(Annotation, PSPDFKit.Annotation)], in viewModel: ViewModel<PDFReaderActionHandler>) {
////        guard let (oldestAnnotation, oldestDocumentAnnotation) = annotations.first, let oldestHighlightAnnotation = oldestDocumentAnnotation as? PSPDFKit.HighlightAnnotation,
////              let indexPath = self.indexPath(for: oldestAnnotation.key, in: viewModel.state.annotations) else { return }
////
////        var rects: [CGRect] = oldestHighlightAnnotation.rects ?? []
////        var comment = oldestAnnotation.comment
////        var tags: [Tag] = oldestAnnotation.tags
////
////        for (annotation, documentAnnotation) in annotations.dropFirst() {
////            guard let highlightAnnotation = documentAnnotation as? PSPDFKit.HighlightAnnotation else { continue }
////            if let _rects = highlightAnnotation.rects {
////                self.merge(rects: &rects, with: _rects)
////            }
////            comment += "\n\n" + annotation.comment
////            for tag in annotation.tags {
////                if !tags.contains(tag) {
////                    tags.append(tag)
////                }
////            }
////        }
////
////        let toDeleteDocumentAnnotations = annotations.dropFirst().map({ $0.1 })
////        let toDeleteKeys = toDeleteDocumentAnnotations.compactMap({ $0.key })
////
////        self.update(viewModel: viewModel) { state in
////            state.ignoreNotifications[.PSPDFAnnotationsRemoved] = Set(toDeleteKeys)
////            state.ignoreNotifications[.PSPDFAnnotationChanged] = [oldestAnnotation.key]
////        }
////
////        viewModel.state.document.undoController.recordCommand(named: nil, in: { recorder in
////            recorder.record(changing: [oldestHighlightAnnotation]) {
////                oldestHighlightAnnotation.rects = rects
////                NotificationCenter.default.post(name: NSNotification.Name.PSPDFAnnotationChanged, object: oldestHighlightAnnotation,
////                                                userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: ["rects", "boundingBox"]])
////            }
////
////            recorder.record(removing: toDeleteDocumentAnnotations) {
////                viewModel.state.document.remove(annotations: toDeleteDocumentAnnotations)
////            }
////        })
////
////        let sortIndex = AnnotationConverter.sortIndex(from: oldestHighlightAnnotation, boundingBoxConverter: self.boundingBoxConverter)
////        let updatedAnnotation = oldestAnnotation.copy(tags: tags).copy(comment: comment).copy(rects: rects, sortIndex: sortIndex)
////        let attributedComment = self.htmlAttributedStringConverter.convert(text: comment, baseAttributes: [.font: viewModel.state.commentFont])
////
////        self.update(viewModel: viewModel) { state in
////            self.update(state: &state, with: updatedAnnotation, from: oldestAnnotation, at: indexPath, shouldReload: true)
////            state.comments[updatedAnnotation.key] = attributedComment
////            self.remove(annotations: toDeleteDocumentAnnotations, from: &state)
////        }
////    }
//
//    private func merge(rects: inout [CGRect], with rects2: [CGRect]) {
//        for rect2 in rects2 {
//            var didMerge: Bool = false
//
//            for (idx, rect) in rects.enumerated() {
//                guard rect.intersects(rect2) else { continue }
//
//                let newRect = rect.union(rect2)
//                rects[idx] = newRect
//
//                didMerge = true
//                break
//            }
//
//            if !didMerge {
//                rects.append(rect2)
//            }
//        }
//    }
//
//    private func syncableDocumentAnnotations(from selected: Set<String>, all: [String: Annotation], document: PSPDFKit.Document) -> [PSPDFKit.Annotation] {
//        var annotations: [PSPDFKit.Annotation] = []
//        for (page, keys) in self.groupedKeysByPage(from: selected, annotations: all) {
//            let documentAnotations = document.annotations(at: UInt(page))
//                                             .filter({ annotation in
//                                                 guard let key = annotation.key else { return false }
//                                                 return annotation.syncable && keys.contains(key)
//                                             })
//            annotations.append(contentsOf: documentAnotations)
//        }
//        return annotations
//    }
//
//    private func groupedKeysByPage(from keys: Set<String>, annotations: [String: Annotation]) -> [Int: Set<String>] {
//        var groupedKeys: [Int: Set<String>] = [:]
//        for key in keys {
//            guard let annotation = annotations[key] else { continue }
//
//            if var keys = groupedKeys[annotation.page] {
//                keys.insert(key)
//                groupedKeys[annotation.page] = keys
//            } else {
//                groupedKeys[annotation.page] = [key]
//            }
//        }
//        return groupedKeys
//    }
//
//    private func sortedSyncableAnnotationsAndDocumentAnnotations(from selected: Set<String>, all: [String: Annotation], document: PSPDFKit.Document) -> [(Annotation, PSPDFKit.Annotation)] {
//        var tuples: [(Annotation, PSPDFKit.Annotation)] = []
//
//        for (page, keys) in self.groupedKeysByPage(from: selected, annotations: all) {
//            let documentAnnotations = document.annotations(at: UInt(page))
//
//            for key in keys {
//                guard let annotation = all[key],
//                      let documentAnnotation = documentAnnotations.first(where: { $0.syncable && $0.key == key }) else { continue }
//                tuples.append((annotation, documentAnnotation))
//            }
//        }
//
//        return tuples.sorted(by: { lTuple, rTuple in
//            return (lTuple.1.creationDate ?? Date()).compare(rTuple.1.creationDate ?? Date()) == .orderedAscending
//        })
//    }

    private func set(filter: AnnotationsFilter?, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard filter != viewModel.state.filter else { return }
        self.filterAnnotations(with: viewModel.state.searchTerm, filter: filter, in: viewModel)
    }

    private func search(for term: String, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTerm = trimmedTerm.isEmpty ? nil : trimmedTerm
        guard newTerm != viewModel.state.searchTerm else { return }
        self.filterAnnotations(with: newTerm, filter: viewModel.state.filter, in: viewModel)
    }

    /// Filters annotations based on given term and filer parameters.
    /// - parameter term: Term to filter annotations.
    /// - parameter viewModel: ViewModel.
    private func filterAnnotations(with term: String?, filter: AnnotationsFilter?, in viewModel: ViewModel<PDFReaderActionHandler>) {
        if term == nil && filter == nil {
            guard let snapshot = viewModel.state.snapshotKeys else { return }

            self.update(viewModel: viewModel) { state in
                state.snapshotKeys = nil
                state.sortedKeys = snapshot
                state.changes = .annotations

                if state.filter != nil {
                    state.changes.insert(.filter)
                }

                state.searchTerm = nil
                state.filter = nil
            }
            return
        }

        let snapshot = viewModel.state.snapshotKeys ?? viewModel.state.sortedKeys
        let filteredKeys = snapshot.filter({ key in
            guard let annotation = viewModel.state.annotation(for: key) else { return false }
            return self.filter(annotation: annotation, with: term, viewModel: viewModel) && self.filter(annotation: annotation, with: filter)
        })

        self.update(viewModel: viewModel) { state in
            if state.snapshotKeys == nil {
                state.snapshotKeys = state.sortedKeys
            }
            state.sortedKeys = filteredKeys
            state.changes = .annotations

            if filter != state.filter {
                state.changes.insert(.filter)
            }

            state.searchTerm = term
            state.filter = filter
        }
    }

    private func filter(annotation: Annotation, with term: String?, viewModel: ViewModel<PDFReaderActionHandler>) -> Bool {
        guard let term = term else { return true }
        return annotation.key.lowercased() == term.lowercased() ||
               annotation.author(displayName: viewModel.state.displayName, username: viewModel.state.username).localizedCaseInsensitiveContains(term) ||
               annotation.comment.localizedCaseInsensitiveContains(term) ||
               (annotation.text ?? "").localizedCaseInsensitiveContains(term) ||
               annotation.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(term) })
    }

    private func filter(annotation: Annotation, with filter: AnnotationsFilter?) -> Bool {
        guard let filter = filter else { return true }
        let hasTag = filter.tags.isEmpty ? true : annotation.tags.first(where: { filter.tags.contains($0.name) }) != nil
        let hasColor = filter.colors.isEmpty ? true : filter.colors.contains(annotation.color)
        return hasTag && hasColor
    }

    /// Set selected annotation. Also sets `focusSidebarIndexPath` or `focusDocumentLocation` if needed.
    /// - parameter key: Annotation key to be selected. Deselects current annotation if `nil`.
    /// - parameter didSelectInDocument: `true` if annotation was selected in document, false if it was selected in sidebar.
    /// - parameter viewModel: ViewModel.
    private func select(key: PDFReaderState.AnnotationKey?, didSelectInDocument: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.update(viewModel: viewModel) { state in
            self._select(key: key, didSelectInDocument: didSelectInDocument, state: &state)
        }
    }

    private func _select(key: PDFReaderState.AnnotationKey?, didSelectInDocument: Bool, state: inout PDFReaderState) {
        guard key != state.selectedAnnotationKey else { return }

        if let existing = state.selectedAnnotationKey {
            state.updatedAnnotationKeys = [existing]
            state.selectedAnnotationCommentActive = false
            state.changes.insert(.activeComment)
        }

        state.changes.insert(.selection)

        guard let key = key else {
            state.selectedAnnotationKey = nil
            return
        }

        state.selectedAnnotationKey = key

        if !didSelectInDocument {
            if let boundingBoxConverter = self.boundingBoxConverter, let annotation = state.annotation(for: key) {
                state.focusDocumentLocation = (annotation.page, annotation.boundingBox(boundingBoxConverter: boundingBoxConverter))
            }
        } else {
            state.focusSidebarKey = key
        }

        var updatedAnnotationKeys = state.updatedAnnotationKeys ?? []
        updatedAnnotationKeys.append(key)
        state.updatedAnnotationKeys = updatedAnnotationKeys
    }

    /// Annotations which originate from document and are not synced generate their previews based on annotation UUID, which is in-memory and is not stored in PDF. So these previews are only
    /// temporary and should be cleared when user closes the document.
    private func clearTmpAnnotationPreviews(in viewModel: ViewModel<PDFReaderActionHandler>) {
        let libraryId = viewModel.state.library.identifier

        for annotation in viewModel.state.documentAnnotations {
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: annotation.key, pdfKey: viewModel.state.key, libraryId: libraryId, isDark: false))
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: annotation.key, pdfKey: viewModel.state.key, libraryId: libraryId, isDark: true))
        }
    }

    // MARK: - Annotation previews

    /// Starts observing preview controller. If new preview is stored, it will be cached immediately.
    /// - parameter viewModel: ViewModel.
    private func observePreviews(in viewModel: ViewModel<PDFReaderActionHandler>) {
        self.annotationPreviewController.observable
                                        .observe(on: MainScheduler.instance)
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
        guard !keys.isEmpty else { return }

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
        case .highlight, .ink: return
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

        viewModel.state.document.undoController.recordCommand(named: nil, adding: [pdfAnnotation]) {
            viewModel.state.document.add(annotations: [pdfAnnotation], options: nil)
        }
    }

//    /// Updates annotations based on insertions to PSPDFKit document.
//    /// - parameter annotations: Annotations that were added to the document.
//    /// - parameter viewModel: ViewModel.
//    private func add(annotations: [PSPDFKit.Annotation], selectFirst: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
//        DDLogInfo("PDFReaderActionHandler: add annotations - \(annotations.map({ "\(type(of: $0));syncable=\($0.syncable);" }))")
//
//        let activeColor = viewModel.state.activeColor.hexString
//        var newZoteroAnnotations: [Annotation] = []
//
//        for annotation in annotations {
//            // Either annotation is new (not syncable) or the user used undo/redo and we check whether the annotation exists
//            guard !annotation.syncable || viewModel.state.annotations[annotation.key ?? ""] == nil else { continue }
//
//            let splitAnnotations = self.splitIfNeeded(annotation: annotation, activeColor: activeColor, in: viewModel)
//
//            if splitAnnotations.count > 1 {
//                DDLogInfo("PDFReaderActionHandler: did split annotations into \(splitAnnotations.count)")
//
//                viewModel.state.document.undoController.recordCommand(named: nil, in: { recorder in
//                    recorder.record(removing: [annotation]) {
//                        viewModel.state.document.remove(annotations: [annotation], options: [.suppressNotifications: true])
//                    }
//
//                    recorder.record(adding: splitAnnotations) {
//                        viewModel.state.document.add(annotations: splitAnnotations, options: [.suppressNotifications: true])
//                    }
//                })
//            }
//
//            for annotation in splitAnnotations {
//                guard let zoteroAnnotation = self.processCreation(of: annotation, activeColor: activeColor, in: viewModel) else { continue }
//                newZoteroAnnotations.append(zoteroAnnotation)
//            }
//        }
//
//        guard !newZoteroAnnotations.isEmpty else { return }
//
//        self.update(viewModel: viewModel) { state in
//            self.add(annotations: newZoteroAnnotations, to: &state, selectFirst: selectFirst)
//            let keys = newZoteroAnnotations.map({ $0.key })
//            state.insertedKeys = state.insertedKeys.union(keys)
//            state.deletedKeys = state.deletedKeys.subtracting(keys)
//            state.changes.insert(.save)
//        }
//    }
//
//    private func processCreation(of annotation: PSPDFKit.Annotation, activeColor: String, in viewModel: ViewModel<PDFReaderActionHandler>) -> Annotation? {
//        guard let zoteroAnnotation = AnnotationConverter.annotation(from: annotation, color: activeColor, library: viewModel.state.library, isNew: true, isSyncable: true,
//                                                                    username: viewModel.state.username, displayName: viewModel.state.displayName, boundingBoxConverter: self.boundingBoxConverter) else { return nil }
//
//        if !annotation.syncable {
//            if let blendMode = AnnotationColorGenerator.blendMode(for: viewModel.state.interfaceStyle, isHighlight: (zoteroAnnotation.type == .highlight)) {
//                annotation.blendMode = blendMode
//            }
//            annotation.customData = [AnnotationsConfig.keyKey: zoteroAnnotation.key,
//                                     AnnotationsConfig.baseColorKey: activeColor,
//                                     AnnotationsConfig.syncableKey: true]
//        }
//
//        self.annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, isDark: (viewModel.state.interfaceStyle == .dark))
//
//        return zoteroAnnotation
//    }
//
//    /// Splits annotation if it exceedes position limit. If it is within limit, it returs original annotation.
//    /// - parameter annotation: Annotation to split
//    /// - parameter activeColor: Currently active color
//    /// - parameter viewModel: View model
//    /// - returns: Array with original annotation if limit was not exceeded. Otherwise array of new split annotations.
//    private func splitIfNeeded(annotation: PSPDFKit.Annotation, activeColor: String, in viewModel: ViewModel<PDFReaderActionHandler>) -> [PSPDFKit.Annotation] {
//        if let annotation = annotation as? HighlightAnnotation {
//            if let rects = annotation.rects, let splitRects = AnnotationSplitter.splitRectsIfNeeded(rects: rects) {
//                return self.createAnnotations(from: splitRects, original: annotation)
//            }
//            return [annotation]
//        }
//
//        if let annotation = annotation as? InkAnnotation {
//            if let paths = annotation.lines, let splitPaths = AnnotationSplitter.splitPathsIfNeeded(paths: paths) {
//                return self.createAnnotations(from: splitPaths, original: annotation)
//            }
//            return [annotation]
//        }
//
//        return [annotation]
//    }
//
//    private func splitRectsIfNeeded(of annotation: HighlightAnnotation) -> [[CGRect]]? {
//        guard var rects = annotation.rects, !rects.isEmpty else { return nil }
//
//        rects.sort { lRect, rRect in
//            if lRect.minY == rRect.minY {
//                return lRect.minX < rRect.minX
//            }
//            return lRect.minY > rRect.minY
//        }
//
//        var count = 2 // 2 for starting and ending brackets of array
//        var splitRects: [[CGRect]] = []
//        var currentRects: [CGRect] = []
//
//        for rect in rects {
//            let size = "\(Decimal(rect.minX).rounded(to: 3))".count + "\(Decimal(rect.minY).rounded(to: 3))".count +
//                       "\(Decimal(rect.maxX).rounded(to: 3))".count + "\(Decimal(rect.maxY).rounded(to: 3))".count + 6 // 4 commas (3 inbetween numbers, 1 after brackets) and 2 brackets for array
//
//            if count + size > AnnotationsConfig.positionSizeLimit {
//                if !currentRects.isEmpty {
//                    splitRects.append(currentRects)
//                    currentRects = []
//                }
//                count = 2
//            }
//
//            currentRects.append(rect)
//            count += size
//        }
//
//        if !currentRects.isEmpty {
//            splitRects.append(currentRects)
//        }
//
//        if splitRects.count == 1 {
//            return nil
//        }
//        return splitRects
//    }
//
//    private func createAnnotations(from splitRects: [[CGRect]], original: HighlightAnnotation) -> [HighlightAnnotation] {
//        guard splitRects.count > 1 else { return [original] }
//        return splitRects.map { rects -> HighlightAnnotation in
//            let new = HighlightAnnotation()
//            new.rects = rects
//            new.boundingBox = AnnotationBoundingBoxCalculator.boundingBox(from: rects)
//            new.alpha = original.alpha
//            new.color = original.color
//            new.blendMode = original.blendMode
//            new.contents = original.contents
//            new.pageIndex = original.pageIndex
//            new.customData = original.customData
//            return new
//        }
//    }
//
//    private func splitPathsIfNeeded(of annotation: InkAnnotation) -> [[[DrawingPoint]]]? {
//        guard let paths = annotation.lines, !paths.isEmpty else { return [] }
//
//        var count = 2 // 2 for starting and ending brackets of array
//        var splitPaths: [[[DrawingPoint]]] = []
//        var currentLines: [[DrawingPoint]] = []
//        var currentPoints: [DrawingPoint] = []
//
//        for subpaths in paths {
//            if count + 3 > AnnotationsConfig.positionSizeLimit {
//                if !currentPoints.isEmpty {
//                    currentLines.append(currentPoints)
//                    currentPoints = []
//                }
//                if !currentLines.isEmpty {
//                    splitPaths.append(currentLines)
//                    currentLines = []
//                }
//                count = 2
//            }
//
//            count += 3 // brackets for this group of points + comma
//
//            for point in subpaths {
//                let location = point.location
//                let size = "\(Decimal(location.x).rounded(to: 3))".count + "\(Decimal(location.y).rounded(to: 3))".count + 2 // 2 commas (1 inbetween numbers, 1 after tuple)
//
//                if count + size > AnnotationsConfig.positionSizeLimit {
//                    if !currentPoints.isEmpty {
//                        currentLines.append(currentPoints)
//                        currentPoints = []
//                    }
//                    if !currentLines.isEmpty {
//                        splitPaths.append(currentLines)
//                        currentLines = []
//                    }
//                    count = 5
//                }
//
//                count += size
//                currentPoints.append(point)
//            }
//
//            currentLines.append(currentPoints)
//            currentPoints = []
//        }
//
//        if !currentPoints.isEmpty {
//            currentLines.append(currentPoints)
//        }
//        if !currentLines.isEmpty {
//            splitPaths.append(currentLines)
//        }
//
//        if splitPaths.count == 1 {
//            return nil
//        }
//        return splitPaths
//    }
//
//    private func createAnnotations(from splitPaths: [[[DrawingPoint]]], original: InkAnnotation) -> [InkAnnotation] {
//        guard splitPaths.count > 1 else { return [original] }
//        return splitPaths.map { paths in
//            let new = InkAnnotation(lines: paths)
//            new.lineWidth = original.lineWidth
//            new.alpha = original.alpha
//            new.color = original.color
//            new.blendMode = original.blendMode
//            new.contents = original.contents
//            new.pageIndex = original.pageIndex
//            new.customData = original.customData
//            return new
//        }
//    }
//
//    private func add(annotations: [Annotation], to state: inout PDFReaderState, selectFirst: Bool) {
//        guard !annotations.isEmpty else { return }
//
//        var selectedAnnotationKey: String?
//
//        let selectAnnotation: (Annotation) -> Void = { annotation in
//            guard selectFirst && selectedAnnotationKey == nil else { return }
//            selectedAnnotationKey = annotation.key
//        }
//
//        for annotation in annotations {
//            if var snapshot = state.annotationKeysSnapshot {
//                // Search is active, add new annotation to snapshot so that it's visible when search is cancelled
//                self.add(annotation: annotation, to: &snapshot, allAnnotations: &state.annotations)
//                state.annotationKeysSnapshot = snapshot
//
//                // If new annotation passes filters, add it to current filtered list as well
//                if self.filter(annotation: annotation, with: state.searchTerm) && self.filter(annotation: annotation, with: state.filter) {
//                    self.add(annotation: annotation, to: &state.annotationKeys, allAnnotations: &state.annotations)
//                    selectAnnotation(annotation)
//                }
//            } else {
//                // Search not active, just insert it to the list and focus
//                self.add(annotation: annotation, to: &state.annotationKeys, allAnnotations: &state.annotations)
//                selectAnnotation(annotation)
//            }
//        }
//
//        state.focusSidebarKey = selectedAnnotationKey
//        state.changes.insert(.annotations)
//
//        if let key = selectedAnnotationKey {
//            if let existing = state.selectedAnnotationKey {
//                state.updatedAnnotationKeys = [existing]
//            }
//            state.selectedAnnotationKey = key
//            state.changes.insert(.selection)
//        }
//    }
//
//    @discardableResult
//    private func add(annotation: Annotation, to annotationKeys: inout [Int: [String]], allAnnotations: inout [String: Annotation]) -> Int {
//        allAnnotations[annotation.key] = annotation
//
//        let index: Int
//        if let keys = annotationKeys[annotation.page] {
//            if let existingId = keys.firstIndex(where: { $0 == annotation.key }) {
//                return existingId
//            }
//
//            index = keys.index(of: annotation.key, sortedBy: { lKey, rKey in
//                guard let lAnnotation = allAnnotations[lKey], let rAnnotation = allAnnotations[rKey] else { return false }
//                return lAnnotation.sortIndex < rAnnotation.sortIndex
//            })
//            annotationKeys[annotation.page]?.insert(annotation.key, at: index)
//        } else {
//            index = 0
//            annotationKeys[annotation.page] = [annotation.key]
//        }
//        return index
//    }
//
//    /// Updates annotations based on deletions of PSPDFKit annotations in document.
//    /// - parameter annotations: Annotations that were deleted in document.
//    /// - parameter viewModel: ViewModel.
//    private func remove(annotations: [PSPDFKit.Annotation], in viewModel: ViewModel<PDFReaderActionHandler>) {
//        DDLogInfo("PDFReaderActionHandler: delete annotations - \(annotations.map({ "\(type(of: $0));syncable=\($0.syncable);" }))")
//
//        self.update(viewModel: viewModel) { state in
//            self.remove(annotations: annotations, from: &state)
//        }
//    }
//
//    private func remove(annotations: [PSPDFKit.Annotation], from state: inout PDFReaderState) {
//        let keys: Set<String>
//
//        if var snapshot = state.annotationKeysSnapshot {
//            // Search is active, delete annotation from snapshot so that it doesn't re-appear when search is cancelled
//            keys = self.remove(annotations: annotations, from: &snapshot, zoteroAnnotations: &state.annotations)
//            state.annotationKeysSnapshot = snapshot
//            // Remove annotations from search result as well
//            self.remove(annotations: annotations, from: &state.annotationKeys, zoteroAnnotations: &state.annotations)
//        } else {
//            // Search not active, remove from all annotations
//            keys = self.remove(annotations: annotations, from: &state.annotationKeys, zoteroAnnotations: &state.annotations)
//        }
//
//        if let selectedKey = state.selectedAnnotationKey, keys.contains(selectedKey) {
//            state.selectedAnnotationKey = nil
//            state.changes.insert(.selection)
//
//            if state.selectedAnnotationCommentActive {
//                state.selectedAnnotationCommentActive = false
//                state.changes.insert(.activeComment)
//            }
//        }
//
//        keys.forEach({ state.comments[$0] = nil })
//        state.deletedKeys = state.deletedKeys.union(keys)
//        state.insertedKeys = state.insertedKeys.subtracting(keys)
//        state.modifiedKeys = state.modifiedKeys.subtracting(keys)
//        state.changes.insert(.annotations)
//        state.changes.insert(.save)
//    }
//
//    @discardableResult
//    private func remove(annotations: [PSPDFKit.Annotation], from annotationKeys: inout [Int: [String]], zoteroAnnotations: inout [String: Annotation]) -> Set<String> {
//        var keys: Set<String> = []
//        for annotation in annotations {
//            guard annotation.syncable, let key = annotation.key else { continue }
//
//            zoteroAnnotations[key] = nil
//
//            let page = Int(annotation.pageIndex)
//            if let index = annotationKeys[page]?.firstIndex(where: { $0 == key }) {
//                annotationKeys[page]?.remove(at: index)
//                keys.insert(key)
//            }
//        }
//        return keys
//    }

    /// Loads annotations from DB, converts them to Zotero annotations and adds matching PSPDFKit annotations to document.
    private func loadDocumentData(boundingBoxConverter: AnnotationBoundingBoxConverter, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let boundingBoxConverter = self.boundingBoxConverter, viewModel.state.document.pageCount > 0 else { return }

        let isDark = viewModel.state.interfaceStyle == .dark
        let key = viewModel.state.key
        let library = viewModel.state.library

        let dbResult = self.loadAnnotationsAndPage(for: key, library: library)

        switch dbResult {
        case .success((let liveAnnotations, let page)):
            let token = self.observe(items: liveAnnotations, viewModel: viewModel)
            let databaseAnnotations = liveAnnotations.freeze()
            let documentAnnotations = self.loadAnnotations(from: viewModel.state.document, library: library, username: viewModel.state.username, displayName: viewModel.state.displayName)
            let dbToPdfAnnotations = AnnotationConverter.annotations(from: databaseAnnotations, interfaceStyle: viewModel.state.interfaceStyle, currentUserId: viewModel.state.userId,
                                                                     library: library, displayName: viewModel.state.displayName, username: viewModel.state.username,
                                                                     boundingBoxConverter: boundingBoxConverter)
            let sortedKeys = self.createSortedKeys(fromDatabaseAnnotations: databaseAnnotations, documentAnnotations: documentAnnotations)

            self.update(document: viewModel.state.document, zoteroAnnotations: dbToPdfAnnotations, key: key, libraryId: library.identifier, isDark: isDark)
            // Store previews
            for annotation in dbToPdfAnnotations {
                self.annotationPreviewController.store(for: annotation, parentKey: key, libraryId: library.identifier, isDark: isDark)
            }

            self.update(viewModel: viewModel) { state in
                state.liveAnnotations = liveAnnotations
                state.databaseAnnotations = databaseAnnotations
                state.documentAnnotations = documentAnnotations
                state.sortedKeys = sortedKeys
                state.visiblePage = page
                state.token = token
                state.changes = .annotations
            }
        case .failure(let error):
            // TODO: - show error
            break
        }
    }

    private func createSortedKeys(fromDatabaseAnnotations databaseAnnotations: Results<RItem>, documentAnnotations: [String: DocumentAnnotation]) -> [PDFReaderState.AnnotationKey] {
        var keys: [(PDFReaderState.AnnotationKey, String)] = []
        for item in databaseAnnotations {
            keys.append((PDFReaderState.AnnotationKey(key: item.key, type: .database), item.annotationSortIndex))
        }
        for annotation in documentAnnotations.values {
            let key = PDFReaderState.AnnotationKey(key: annotation.key, type: .document)
            let index = keys.index(of: (key, annotation.sortIndex), sortedBy: { lData, rData in
                return lData.1 < rData.1
            })
            keys.insert((key, annotation.sortIndex), at: index)
        }
        return keys.map({ $0.0 })
    }

    private func loadAnnotationsAndPage(for key: String, library: Library) -> Result<(Results<RItem>, Int), Error> {
        do {
            var results: Results<RItem>!
            var page = 0

            try self.dbStorage.perform(on: .main, with: { coordinator in
                page = try coordinator.perform(request: ReadDocumentDataDbRequest(attachmentKey: key, libraryId: library.identifier))
                results = try coordinator.perform(request: ReadAnnotationsDbRequest(attachmentKey: key, libraryId: library.identifier))
            })

            return .success((results, page))
        } catch let error {
            return .failure(error)
        }
    }

    private func observe(items: Results<RItem>, viewModel: ViewModel<PDFReaderActionHandler>) -> NotificationToken {
        return items.observe { [weak self, weak viewModel] change in
            guard let `self` = self, let viewModel = viewModel else { return }
            switch change {
            case .update(let objects, let deletions, let insertions, let modifications):
                self.update(objects: objects, deletions: deletions, insertions: insertions, modifications: modifications, viewModel: viewModel)
            case .error, .initial: break
            }
        }
    }

    private func loadAnnotations(from document: PSPDFKit.Document, library: Library, username: String, displayName: String) -> [String: DocumentAnnotation] {
        var annotations: [String: DocumentAnnotation] = [:]
        for (_, pdfAnnotations) in document.allAnnotations(of: AnnotationsConfig.supported) {
            for pdfAnnotation in pdfAnnotations {
                // Check whether square annotation was previously created by Zotero. If it's just "normal" square (instead of our image) annotation, don't convert it to Zotero annotation.
                if let square = pdfAnnotation as? PSPDFKit.SquareAnnotation, !square.isZoteroAnnotation {
                    continue
                }

                guard let annotation = AnnotationConverter.annotation(from: pdfAnnotation, color: (pdfAnnotation.color?.hexString ?? "#000000"), library: library, username: username,
                                                                      displayName: displayName, boundingBoxConverter: self.boundingBoxConverter) else { continue }

                annotations[annotation.key] = annotation
            }
        }
        return annotations
    }

    private func update(document: PSPDFKit.Document, zoteroAnnotations: [PSPDFKit.Annotation], key: String, libraryId: LibraryIdentifier, isDark: Bool) {
        // Disable all non-zotero annotations, store previews if needed
        let allAnnotations = document.allAnnotations(of: PSPDFKit.Annotation.Kind.all)
        for (_, annotations) in allAnnotations {
            for annotation in annotations {
                annotation.flags.update(with: .locked)
                self.annotationPreviewController.store(for: annotation, parentKey: key, libraryId: libraryId, isDark: isDark)
            }
        }
        // Add zotero annotations to document
        document.add(annotations: zoteroAnnotations, options: [.suppressNotifications: true])
    }

    private func update(objects: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int], viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let boundingBoxConverter = self.boundingBoxConverter else { return }

        // Get sorted database keys
        var keys = viewModel.state.sortedKeys.filter({ $0.type == .database })

        // Update database keys based on realm notification
        var updatedKeys: [PDFReaderState.AnnotationKey] = []
        // Collect deleted and inserted annotations to update the `Document`
        var deletedPdfAnnotations: [PSPDFKit.Annotation] = []
        var insertedPdfAnnotations: [PSPDFKit.Annotation] = []

        for index in modifications {
            let key = keys[index]
            updatedKeys.append(key)

            // Modifications are not written to PDF document when done locally. They are written to DB and observed here. So we always need to translate those changes to PDF document.

            guard let annotation = objects.filter(.key(key.key)).first.flatMap({ DatabaseAnnotation(item: $0) }),
                  let pdfAnnotation = viewModel.state.document.annotations(at: PageIndex(annotation.page)).first(where: { $0.key == annotation.key }) else { continue }
            self.update(pdfAnnotation: pdfAnnotation, with: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, interfaceStyle: viewModel.state.interfaceStyle)
        }

        for index in deletions.reversed() {
            keys.remove(at: index)

            // Deletions are not written to PDF document when done locally. Objects are deleted from DB and deletions are observed here. So we always need to translate those changes to PDF document.

            let oldAnnotation = DatabaseAnnotation(item: viewModel.state.databaseAnnotations[index])
            guard let pdfAnnotation = viewModel.state.document.annotations(at: PageIndex(oldAnnotation.page)).first(where: { $0.key == oldAnnotation.key }) else { continue }
            deletedPdfAnnotations.append(pdfAnnotation)
        }

        for index in insertions {
            let item = objects[index]
            keys.insert(PDFReaderState.AnnotationKey(key: item.key, type: .database), at: index)

            // Check whether annotation was created by sync (remote change from other client) or locally. Annotations created locally in our UI are created by PSPDFKit, reported by PSPDFKit to viewModel,
            // written to DB and the write is observed here. Since the annotation already exists in the document we don't need to re-create here again.

            guard item.changeType == .sync else { continue }

            let annotation = AnnotationConverter.annotation(from: DatabaseAnnotation(item: item), type: .zotero, interfaceStyle: viewModel.state.interfaceStyle, currentUserId: viewModel.state.userId,
                                                            library: viewModel.state.library, displayName: viewModel.state.displayName, username: viewModel.state.username,
                                                            boundingBoxConverter: boundingBoxConverter)
            insertedPdfAnnotations.append(annotation)
        }

        let getSortIndex: (PDFReaderState.AnnotationKey) -> String? = { key in
            switch key.type {
            case .document:
                return viewModel.state.documentAnnotations[key.key]?.sortIndex
            case .database:
                return objects.filter(.key(key.key)).first?.annotationSortIndex
            }
        }

        // Re-add document keys
        for annotation in viewModel.state.documentAnnotations.values {
            let key = PDFReaderState.AnnotationKey(key: annotation.key, type: .document)
            let index = keys.index(of: key, sortedBy: { lKey, rKey in
                let lSortIndex = getSortIndex(lKey) ?? ""
                let rSortIndex = getSortIndex(rKey) ?? ""
                return lSortIndex < rSortIndex
            })
            keys.insert(key, at: index)
        }

        if !deletedPdfAnnotations.isEmpty {
            viewModel.state.document.remove(annotations: deletedPdfAnnotations, options: nil)
        }
        if !insertedPdfAnnotations.isEmpty {
            viewModel.state.document.add(annotations: insertedPdfAnnotations, options: nil)
        }

        // Update state
        self.update(viewModel: viewModel) { state in
            state.databaseAnnotations = objects.freeze()
            state.sortedKeys = keys
            state.updatedAnnotationKeys = updatedKeys
            state.changes = .annotations
        }
    }

    private func update(pdfAnnotation: PSPDFKit.Annotation, with annotation: DatabaseAnnotation, parentKey: String, libraryId: LibraryIdentifier, interfaceStyle: UIUserInterfaceStyle) {
        guard let boundingBoxConverter = self.boundingBoxConverter else { return }

        var changes: PdfAnnotationChanges = []

        if pdfAnnotation.baseColor != annotation.color {
            let hexColor = annotation.color

            let (color, alpha, blendMode) = AnnotationColorGenerator.color(from: UIColor(hex: hexColor), isHighlight: (annotation.type == .highlight), userInterfaceStyle: interfaceStyle)
            pdfAnnotation.baseColor = hexColor
            pdfAnnotation.color = color
            pdfAnnotation.alpha = alpha
            if let blendMode = blendMode {
                pdfAnnotation.blendMode = blendMode
            }

            changes.insert(.color)
        }

        if pdfAnnotation.contents != annotation.comment {
            pdfAnnotation.contents = annotation.comment
            changes.insert(.comment)
        }

        switch annotation.type {
        case .highlight:
            let newBoundingBox = annotation.boundingBox(boundingBoxConverter: boundingBoxConverter)
            if newBoundingBox != pdfAnnotation.boundingBox.rounded(to: 3) {
                pdfAnnotation.boundingBox = newBoundingBox
                changes.insert(.boundingBox)
                pdfAnnotation.rects = annotation.rects(boundingBoxConverter: boundingBoxConverter)
                changes.insert(.rects)
            } else {
                let newRects = annotation.rects(boundingBoxConverter: boundingBoxConverter)
                let oldRects = (pdfAnnotation.rects ?? []).map({ $0.rounded(to: 3) })
                if newRects != oldRects {
                    pdfAnnotation.rects = newRects
                    changes.insert(.rects)
                }
            }

        case .ink:
            if let inkAnnotation = pdfAnnotation as? PSPDFKit.InkAnnotation {
                let newPaths = annotation.paths(boundingBoxConverter: boundingBoxConverter)
                let oldPaths = (inkAnnotation.lines ?? []).map { points in
                    return points.map({ $0.location.rounded(to: 3) })
                }

                if newPaths != oldPaths {
                    changes.insert(.paths)
                    inkAnnotation.lines = newPaths.map { points in
                        return points.map({ DrawingPoint(cgPoint: $0) })
                    }
                }

                if let lineWidth = annotation.lineWidth, lineWidth != inkAnnotation.lineWidth {
                    inkAnnotation.lineWidth = lineWidth
                    changes.insert(.lineWidth)
                }
            }

        case .image:
            let newBoundingBox = annotation.boundingBox(boundingBoxConverter: boundingBoxConverter)
            if pdfAnnotation.boundingBox.rounded(to: 3) != newBoundingBox {
                changes.insert(.boundingBox)
                pdfAnnotation.boundingBox = newBoundingBox
            }

        case .note:
            let newBoundingBox = annotation.boundingBox(boundingBoxConverter: boundingBoxConverter)
            if pdfAnnotation.boundingBox.origin.rounded(to: 3) != newBoundingBox.origin {
                changes.insert(.boundingBox)
                pdfAnnotation.boundingBox = newBoundingBox
            }
        }

        guard !changes.isEmpty else { return }

        if changes.contains(.boundingBox) {
            self.annotationPreviewController.store(for: pdfAnnotation, parentKey: parentKey, libraryId: libraryId, isDark: (interfaceStyle == .dark))
        }

        NotificationCenter.default.post(name: NSNotification.Name.PSPDFAnnotationChanged, object: pdfAnnotation,
                                        userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: PdfAnnotationChanges.stringValues(from: changes)])
    }
}

#endif
