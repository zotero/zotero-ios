//
//  PDFReaderActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import RealmSwift
import RxSwift

extension DrawingPoint: SplittablePathPoint {
    var x: Double {
        return location.x
    }

    var y: Double {
        return location.y
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
        static let boundingBox = PdfAnnotationChanges(rawValue: 1 << 1)
        static let rects = PdfAnnotationChanges(rawValue: 1 << 2)
        static let lineWidth = PdfAnnotationChanges(rawValue: 1 << 3)
        static let paths = PdfAnnotationChanges(rawValue: 1 << 4)
        static let contents = PdfAnnotationChanges(rawValue: 1 << 5)
        static let rotation = PdfAnnotationChanges(rawValue: 1 << 6)
        static let fontSize = PdfAnnotationChanges(rawValue: 1 << 7)

        static func stringValues(from changes: PdfAnnotationChanges) -> [String] {
            var rawChanges: [String] = []
            if changes.contains(.color) {
                rawChanges.append(contentsOf: ["color", "alpha"])
            }
            if changes.contains(.rects) {
                rawChanges.append("rects")
            }
            if changes.contains(.boundingBox) {
                rawChanges.append("boundingBox")
            }
            if changes.contains(.lineWidth) {
                rawChanges.append("lineWidth")
            }
            if changes.contains(.paths) {
                rawChanges.append(contentsOf: ["lines", "lineArray"])
            }
            if changes.contains(.contents) {
                rawChanges.append("contents")
            }
            if changes.contains(.rotation) {
                rawChanges.append("rotation")
            }
            if changes.contains(.fontSize) {
                rawChanges.append("fontSize")
            }
            return rawChanges
        }
    }

    unowned let dbStorage: DbStorage
    private unowned let annotationPreviewController: AnnotationPreviewController
    unowned let pdfThumbnailController: PDFThumbnailController
    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    private unowned let schemaController: SchemaController
    private unowned let fileStorage: FileStorage
    private unowned let idleTimerController: IdleTimerController
    private unowned let dateParser: DateParser
    let backgroundQueue: DispatchQueue
    private let disposeBag: DisposeBag

    private var pdfDisposeBag: DisposeBag
    private var pageDebounceDisposeBag: DisposeBag?
    private var freeTextAnnotationRotationDebounceDisposeBagByKey: [String: DisposeBag]
    private var debouncedFreeTextAnnotationAndChangesByKey: [String: ([String], PSPDFKit.FreeTextAnnotation)]
    weak var delegate: (PDFReaderContainerDelegate & AnnotationBoundingBoxConverter)?

    init(
        dbStorage: DbStorage,
        annotationPreviewController: AnnotationPreviewController,
        pdfThumbnailController: PDFThumbnailController,
        htmlAttributedStringConverter: HtmlAttributedStringConverter,
        schemaController: SchemaController,
        fileStorage: FileStorage,
        idleTimerController: IdleTimerController,
        dateParser: DateParser
    ) {
        self.dbStorage = dbStorage
        self.annotationPreviewController = annotationPreviewController
        self.pdfThumbnailController = pdfThumbnailController
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.schemaController = schemaController
        self.fileStorage = fileStorage
        self.idleTimerController = idleTimerController
        self.dateParser = dateParser
        backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.PDFReaderActionHandler.queue", qos: .userInteractive)
        pdfDisposeBag = DisposeBag()
        freeTextAnnotationRotationDebounceDisposeBagByKey = [:]
        debouncedFreeTextAnnotationAndChangesByKey = [:]
        disposeBag = DisposeBag()
    }

    deinit {
        DDLogInfo("PDFReaderActionHandler deinitialized")
    }

    func process(action: PDFReaderAction, in viewModel: ViewModel<PDFReaderActionHandler>) {
        switch action {
        case .loadDocumentData(let boundingBoxConverter):
            loadDocumentData(boundingBoxConverter: boundingBoxConverter, in: viewModel)

        case .startObservingAnnotationPreviewChanges:
            observePreviews(in: viewModel)

        case .searchAnnotations(let term):
            search(for: term, in: viewModel)

        case .selectAnnotation(let key):
            guard !viewModel.state.sidebarEditingEnabled && key != viewModel.state.selectedAnnotationKey else { return }
            select(key: key, didSelectInDocument: false, in: viewModel)

        case .selectAnnotationFromDocument(let key):
            guard !viewModel.state.sidebarEditingEnabled && key != viewModel.state.selectedAnnotationKey else { return }
            select(key: key, didSelectInDocument: true, in: viewModel)

        case .deselectSelectedAnnotation:
            select(key: nil, didSelectInDocument: false, in: viewModel)

        case .selectAnnotationDuringEditing(let key):
            selectDuringEditing(key: key, in: viewModel)

        case .deselectAnnotationDuringEditing(let key):
            deselectDuringEditing(key: key, in: viewModel)

        case .removeAnnotation(let key):
            remove(key: key, in: viewModel)

        case .removeSelectedAnnotations:
            removeSelectedAnnotations(in: viewModel)

        case .mergeSelectedAnnotations:
            guard viewModel.state.sidebarEditingEnabled else { return }
            mergeSelectedAnnotations(in: viewModel)

        case .requestPreviews(let keys, let notify):
            loadPreviews(for: keys, notify: notify, in: viewModel)

        case .setHighlight(let key, let highlight):
            set(highlightText: highlight, key: key, viewModel: viewModel)

        case .parseAndCacheComment(let key, let comment):
            update(viewModel: viewModel, notifyListeners: false) { state in
                state.comments[key] = htmlAttributedStringConverter.convert(text: comment, baseAttributes: [.font: state.commentFont])
            }

        case .setComment(let key, let comment):
            set(comment: comment, key: key, viewModel: viewModel)

        case .setColor(let key, let color):
            set(color: color, key: key, viewModel: viewModel)

        case .setLineWidth(let key, let width):
            set(lineWidth: width, key: key, viewModel: viewModel)

        case .setFontSize(let key, let size):
            set(fontSize: size, key: key, viewModel: viewModel)

        case .setCommentActive(let isActive):
            guard viewModel.state.selectedAnnotationKey != nil else { return }
            update(viewModel: viewModel) { state in
                state.selectedAnnotationCommentActive = isActive
                state.changes = .activeComment
            }

        case .setTags(let key, let tags):
            set(tags: tags, key: key, viewModel: viewModel)

        case .updateAnnotationProperties(let key, let color, let lineWidth, let fontSize, let pageLabel, let updateSubsequentLabels, let highlightText):
            set(
                color: color,
                lineWidth: lineWidth,
                fontSize: fontSize,
                pageLabel: pageLabel,
                updateSubsequentLabels: updateSubsequentLabels,
                highlightText: highlightText,
                key: key,
                viewModel: viewModel
            )

        case .userInterfaceStyleChanged(let interfaceStyle):
            userInterfaceChanged(interfaceStyle: interfaceStyle, in: viewModel)

        case .updateAnnotationPreviews:
            storeAnnotationPreviewsIfNeeded(isDark: viewModel.state.interfaceStyle == .dark, in: viewModel)

        case .setToolOptions(let hex, let size, let tool):
            setToolOptions(hex: hex, size: size, tool: tool, in: viewModel)

        case .createImage(let pageIndex, let origin):
            addImage(onPage: pageIndex, origin: origin, in: viewModel)

        case .createNote(let pageIndex, let origin):
            addNote(onPage: pageIndex, origin: origin, in: viewModel)

        case .createHighlight(let pageIndex, let rects):
            addHighlight(onPage: pageIndex, rects: rects, in: viewModel)

        case .setVisiblePage(let page, let userActionFromDocument, let fromThumbnailList):
            set(page: page, userActionFromDocument: userActionFromDocument, fromThumbnailList: fromThumbnailList, in: viewModel)

        case .submitPendingPage(let page):
            guard pageDebounceDisposeBag != nil else { return }
            pageDebounceDisposeBag = nil
            store(page: page, in: viewModel)

        case .export(let includeAnnotations):
            export(includeAnnotations: includeAnnotations, viewModel: viewModel)

        case .clearTmpData:
            /// Annotations which originate from document and are not synced generate their previews based on annotation UUID, which is in-memory and is not stored in PDF. So these previews are only
            /// temporary and should be cleared when user closes the document.
            annotationPreviewController.deleteAll(parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            // Clear page thumbnails
            pdfThumbnailController.deleteAll(forKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)

        case .setSettings(let settings, let userInterfaceStyle):
            update(settings: settings, parentInterfaceStyle: userInterfaceStyle, in: viewModel)

        case .changeIdleTimerDisabled(let disabled):
            changeIdleTimer(disabled: disabled, in: viewModel)

        case .setSidebarEditingEnabled(let enabled):
            setSidebar(editing: enabled, in: viewModel)

        case .changeFilter(let filter):
            set(filter: filter, in: viewModel)

        case .unlock(let password):
            let result = viewModel.state.document.unlock(withPassword: password)
            update(viewModel: viewModel) { state in
                state.unlockSuccessful = result
            }
        }
    }

    // MARK: - Dark mode changes

    private func userInterfaceChanged(interfaceStyle: UIUserInterfaceStyle, in viewModel: ViewModel<PDFReaderActionHandler>) {
        viewModel.state.previewCache.removeAllObjects()

        for (_, annotations) in viewModel.state.document.allAnnotations(of: AnnotationsConfig.supported) {
            for annotation in annotations {
                let baseColor = annotation.baseColor
                let (color, alpha, blendMode) = AnnotationColorGenerator.color(
                    from: UIColor(hex: baseColor),
                    isHighlight: (annotation is PSPDFKit.HighlightAnnotation),
                    userInterfaceStyle: interfaceStyle
                )
                annotation.color = color
                annotation.alpha = alpha
                if let blendMode {
                    annotation.blendMode = blendMode
                }
            }
        }

        storeAnnotationPreviewsIfNeeded(isDark: interfaceStyle == .dark, in: viewModel)

        update(viewModel: viewModel) { state in
            state.interfaceStyle = interfaceStyle
            state.changes = .interfaceStyle
        }
    }

    private func storeAnnotationPreviewsIfNeeded(isDark: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let libraryId = viewModel.state.library.identifier

        // Load area annotations if needed.
        for (_, annotations) in viewModel.state.document.allAnnotations(of: [.square, .ink, .freeText]) {
            for annotation in annotations {
                guard annotation.shouldRenderPreview && annotation.isZoteroAnnotation &&
                      !annotationPreviewController.hasPreview(for: annotation.previewId, parentKey: viewModel.state.key, libraryId: libraryId, isDark: isDark)
                else { continue }
                annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: libraryId, isDark: isDark)
            }
        }
    }

    // MARK: - Reader actions

    private func selectDuringEditing(key: PDFReaderState.AnnotationKey, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: key) else { return }

        let annotationDeletable = annotation.isSyncable && annotation.editability(currentUserId: viewModel.state.userId, library: viewModel.state.library) != .notEditable

        update(viewModel: viewModel) { state in
            if state.selectedAnnotationsDuringEditing.isEmpty {
                state.deletionEnabled = annotationDeletable
            } else {
                state.deletionEnabled = state.deletionEnabled && annotationDeletable
            }

            state.selectedAnnotationsDuringEditing.insert(key)

            if state.selectedAnnotationsDuringEditing.count == 1 {
                state.mergingEnabled = false
            } else {
                state.mergingEnabled = selectedAnnotationsMergeable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)
            }

            state.changes = .sidebarEditingSelection
        }
    }

    private func deselectDuringEditing(key: PDFReaderState.AnnotationKey, in viewModel: ViewModel<PDFReaderActionHandler>) {
        update(viewModel: viewModel) { state in
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
                let deletionEnabled = selectedAnnotationsDeletable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)

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
                    state.mergingEnabled = selectedAnnotationsMergeable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)
                    state.changes = .sidebarEditingSelection
                }
            }
        }
    }

    private func selectedAnnotationsMergeable(selected: Set<PDFReaderState.AnnotationKey>, in viewModel: ViewModel<PDFReaderActionHandler>) -> Bool {
        var page: Int?
        var type: AnnotationType?
        var color: String?
//        var rects: [CGRect]?

        let hasSameProperties: (PDFAnnotation) -> Bool = { annotation in
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
//                    if !rects(rects: rects, hasIntersectionWith: annotation.rects) {
//                        return false
//                    }
//                } else {
//                    rects = annotation.rects
//                }

            case .note, .image, .underline, .freeText:
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
        return !selected.contains(where: { key in
            guard let annotation = viewModel.state.annotation(for: key) else { return false }
            return !annotation.isSyncable || annotation.editability(currentUserId: viewModel.state.userId, library: viewModel.state.library) == .notEditable
        })
    }

    private func setSidebar(editing enabled: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        update(viewModel: viewModel) { state in
            state.sidebarEditingEnabled = enabled
            state.changes = .sidebarEditing

            if enabled {
                // Deselect selected annotation before editing
                _select(key: nil, didSelectInDocument: false, state: &state)
            } else {
                // Deselect selected annotations during editing
                state.selectedAnnotationsDuringEditing = []
                state.deletionEnabled = false
            }
        }
    }

    private func changeIdleTimer(disabled: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard viewModel.state.settings.idleTimerDisabled != disabled else { return }
        var settings = viewModel.state.settings
        settings.idleTimerDisabled = disabled

        update(viewModel: viewModel) { state in
            state.settings = settings
            // Don't need to assign `changes` or update Defaults.shared.pdfSettings, this setting is not stored and doesn't change anything else
        }

        if settings.idleTimerDisabled {
            idleTimerController.disable()
        } else {
            idleTimerController.enable()
        }
    }

    private func update(settings: PDFSettings, parentInterfaceStyle: UIUserInterfaceStyle, in viewModel: ViewModel<PDFReaderActionHandler>) {
        if viewModel.state.settings.idleTimerDisabled != settings.idleTimerDisabled {
            if settings.idleTimerDisabled {
                idleTimerController.disable()
            } else {
                idleTimerController.enable()
            }
        }

        // Update local state
        update(viewModel: viewModel) { state in
            state.settings = settings
            state.changes = .settings
        }
        // Store new settings to defaults
        Defaults.shared.pdfSettings = settings

        // Check whether interfaceStyle changed and update if needed
        let settingsInterfaceStyle: UIUserInterfaceStyle
        switch settings.appearanceMode {
        case .dark:
            settingsInterfaceStyle = .dark

        case .light:
            settingsInterfaceStyle = .light

        case .automatic:
            settingsInterfaceStyle = parentInterfaceStyle
        }

        guard settingsInterfaceStyle != viewModel.state.interfaceStyle else { return }
        userInterfaceChanged(interfaceStyle: settingsInterfaceStyle, in: viewModel)
    }

    private func set(page: Int, userActionFromDocument: Bool, fromThumbnailList: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard viewModel.state.visiblePage != page else { return }

        update(viewModel: viewModel) { state in
            state.visiblePage = page
            if userActionFromDocument {
                state.changes.insert(.visiblePageFromDocument)
            }
            if fromThumbnailList {
                state.changes.insert(.visiblePageFromThumbnailList)
            }
        }

        let disposeBag = DisposeBag()
        pageDebounceDisposeBag = disposeBag

        Single<Int>.timer(.seconds(3), scheduler: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self, weak viewModel] _ in
                       guard let self, let viewModel else { return }
                       store(page: page, in: viewModel)
                       pageDebounceDisposeBag = nil
                   })
                   .disposed(by: disposeBag)
    }

    private func store(page: Int, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let request = StorePageForItemDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, page: "\(page)")
        perform(request: request) { error in
            guard let error else { return }
            // TODO: - handle error
            DDLogError("PDFReaderActionHandler: can't store page - \(error)")
        }
    }

    private func export(includeAnnotations: Bool, viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let boundingBoxConverter = delegate, let url = viewModel.state.document.fileURL else { return }

        update(viewModel: viewModel) { state in
            state.exportState = .preparing
            state.changes.insert(.export)
        }

        let annotations: [PSPDFKit.Annotation]

        if !includeAnnotations {
            annotations = []
        } else {
            annotations = AnnotationConverter.annotations(
                from: viewModel.state.databaseAnnotations,
                type: .export,
                interfaceStyle: .light,
                currentUserId: viewModel.state.userId,
                library: viewModel.state.library,
                displayName: viewModel.state.displayName,
                username: viewModel.state.username,
                boundingBoxConverter: boundingBoxConverter
            )
        }

        PDFDocumentExporter.export(
            annotations: annotations,
            key: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            url: url,
            fileStorage: fileStorage,
            dbStorage: dbStorage,
            completed: { [weak self, weak viewModel] result in
                guard let self, let viewModel else { return }
                finishExport(result: result, viewModel: viewModel)
            }
        )
    }

    private func finishExport(result: Result<File, PDFDocumentExporter.Error>, viewModel: ViewModel<PDFReaderActionHandler>) {
        update(viewModel: viewModel) { state in
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

    private func setToolOptions(hex: String?, size: CGFloat?, tool: PSPDFKit.Annotation.Tool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        if let hex = hex {
            switch tool {
            case .highlight:
                Defaults.shared.highlightColorHex = hex

            case .note:
                Defaults.shared.noteColorHex = hex

            case .square:
                Defaults.shared.squareColorHex = hex

            case .ink:
                Defaults.shared.inkColorHex = hex

            case .underline:
                Defaults.shared.underlineColorHex = hex

            case .freeText:
                Defaults.shared.textColorHex = hex

            default: return
            }
        }

        if let size = size {
            switch tool {
            case .eraser:
                Defaults.shared.activeEraserSize = Float(size)

            case .ink:
                Defaults.shared.activeLineWidth = Float(size)

            case .freeText:
                Defaults.shared.activeFontSize = Float(size)

            default: break
            }
        }

        update(viewModel: viewModel) { state in
            if let hex = hex {
                state.toolColors[tool] = UIColor(hex: hex)
                state.changedColorForTool = tool
            }

            if let size = size {
                switch tool {
                case .ink:
                    state.activeLineWidth = size
                    state.changes = .activeLineWidth

                case .eraser:
                    state.activeEraserSize = size
                    state.changes = .activeEraserSize

                case .freeText:
                    state.activeFontSize = size
                    state.changes = .activeFontSize
                    
                default: break
                }
            }
        }
    }

    private func mergeSelectedAnnotations(in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard selectedAnnotationsMergeable(selected: viewModel.state.selectedAnnotationsDuringEditing, in: viewModel) else { return }

        let toMerge = sortedSyncableAnnotationsAndDocumentAnnotations(from: viewModel.state.selectedAnnotationsDuringEditing, state: viewModel.state)

        guard toMerge.count > 1, let oldest = toMerge.first else { return }

        do {
            switch oldest.0.type {
            case .ink:
                try merge(inkAnnotations: toMerge, in: viewModel)

            case .highlight:
                break
//                merge(highlightAnnotations: toMerge, in: viewModel)

            default:
                break
            }

            update(viewModel: viewModel) { state in
                state.mergingEnabled = false
                state.deletionEnabled = false
                state.selectedAnnotationsDuringEditing = []
                state.changes = .sidebarEditingSelection
            }
        } catch let error {
            update(viewModel: viewModel) { state in
                state.error = (error as? PDFReaderState.Error) ?? .unknown
            }
        }

        func sortedSyncableAnnotationsAndDocumentAnnotations(from selected: Set<PDFReaderState.AnnotationKey>, state: PDFReaderState) -> [(PDFAnnotation, PSPDFKit.Annotation)] {
            var tuples: [(PDFAnnotation, PSPDFKit.Annotation)] = []

            for (page, annotations) in groupedAnnotationsByPage(from: selected, state: state) {
                let documentAnnotations = state.document.annotations(at: UInt(page))
                for annotation in annotations {
                    guard let documentAnnotation = documentAnnotations.first(where: { $0.key == annotation.key }) else { continue }
                    tuples.append((annotation, documentAnnotation))
                }
            }

            return tuples.sorted(by: { lTuple, rTuple in
                return (lTuple.1.creationDate ?? Date()).compare(rTuple.1.creationDate ?? Date()) == .orderedAscending
            })

            func groupedAnnotationsByPage(from keys: Set<PDFReaderState.AnnotationKey>, state: PDFReaderState) -> [Int: [PDFAnnotation]] {
                var groupedAnnotations: [Int: [PDFAnnotation]] = [:]
                for key in keys {
                    guard let annotation = state.annotation(for: key) else { continue }
                    var annotations = groupedAnnotations[annotation.page, default: []]
                    annotations.append(annotation)
                    groupedAnnotations[annotation.page] = annotations
                }
                return groupedAnnotations
            }
        }

        func merge(inkAnnotations annotations: [(PDFAnnotation, PSPDFKit.Annotation)], in viewModel: ViewModel<PDFReaderActionHandler>) throws {
            guard let (oldestAnnotation, oldestInkAnnotation, lines, lineWidth, tags) = collectInkAnnotationData(from: annotations, in: viewModel) else { return }

            if AnnotationSplitter.splitPathsIfNeeded(paths: lines) != nil {
                throw PDFReaderState.Error.mergeTooBig
            }

            let toDeleteDocumentAnnotations = annotations.dropFirst().map({ $0.1 })

            // Update PDF document with merged annotations
            viewModel.state.document.undoController.recordCommand(named: nil, in: { recorder in
                recorder.record(changing: [oldestInkAnnotation]) {
                    let changes: PdfAnnotationChanges
                    oldestInkAnnotation.lines = lines
                    if oldestInkAnnotation.lineWidth != lineWidth {
                        changes = [.lineWidth, .paths]
                        oldestInkAnnotation.lineWidth = lineWidth
                    } else {
                        changes = [.paths]
                    }

                    NotificationCenter.default.post(
                        name: NSNotification.Name.PSPDFAnnotationChanged,
                        object: oldestInkAnnotation,
                        userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: PdfAnnotationChanges.stringValues(from: changes)]
                    )
                }

                recorder.record(removing: toDeleteDocumentAnnotations) {
                    viewModel.state.document.remove(annotations: toDeleteDocumentAnnotations)
                }
            })

            // Update tags in merged annotation
            set(tags: tags, key: oldestAnnotation.key, viewModel: viewModel)

            typealias InkAnnotatationsData = (oldestAnnotation: PDFAnnotation, oldestDocumentAnnotation: PSPDFKit.InkAnnotation, lines: [[DrawingPoint]], lineWidth: CGFloat, tags: [Tag])

            func collectInkAnnotationData(from annotations: [(PDFAnnotation, PSPDFKit.Annotation)], in viewModel: ViewModel<PDFReaderActionHandler>) -> InkAnnotatationsData? {
                guard let (oldestAnnotation, oldestDocumentAnnotation) = annotations.first, let oldestInkAnnotation = oldestDocumentAnnotation as? PSPDFKit.InkAnnotation else { return nil }

                var lines: [[DrawingPoint]] = oldestInkAnnotation.lines ?? []
                var lineWidthData: [CGFloat: (Int, Date)] = [oldestInkAnnotation.lineWidth: (1, (oldestInkAnnotation.creationDate ?? Date(timeIntervalSince1970: 0)))]
                // TODO: - enable comment merging when ink annotations support commenting
//                var comment = oldestAnnotation.comment
                var tags: [Tag] = oldestAnnotation.tags

                for (annotation, documentAnnotation) in annotations.dropFirst() {
                    guard let inkAnnotation = documentAnnotation as? PSPDFKit.InkAnnotation else { continue }

                    lines += inkAnnotation.lines ?? []

                    if let (count, date) = lineWidthData[documentAnnotation.lineWidth] {
                        var newDate = date
                        if let annotationDate = documentAnnotation.creationDate, annotationDate < date {
                            newDate = annotationDate
                        }
                        lineWidthData[documentAnnotation.lineWidth] = ((count + 1), newDate)
                    } else {
                        lineWidthData[documentAnnotation.lineWidth] = (1, (documentAnnotation.creationDate ?? Date(timeIntervalSince1970: 0)))
                    }

//                    comment += "\n\n" + annotation.comment

                    for tag in annotation.tags {
                        if !tags.contains(tag) {
                            tags.append(tag)
                        }
                    }
                }

                return (oldestAnnotation, oldestInkAnnotation, lines, chooseMergedLineWidth(from: lineWidthData), tags)

                /// Choose line width based on 2 properties. First choose line width which was used the most times.
                /// If multiple line widths were used the same amount of time, pick line width with oldest annotation.
                /// - parameter lineWidthData: Line widths data collected from annotations. It contains count of usage and date of oldest annotation grouped by lineWidth.
                /// - returns: Best line width based on above properties.
                func chooseMergedLineWidth(from lineWidthData: [CGFloat: (Int, Date)]) -> CGFloat {
                    if lineWidthData.isEmpty {
                        // Should never happen
                        return 1
                    }
                    if lineWidthData.keys.count == 1, let width = lineWidthData.keys.first {
                        return width
                    }

                    var data: [(lineWidth: CGFloat, count: Int, oldestCreationDate: Date)] = []
                    for (key, value) in lineWidthData {
                        data.append((key, value.0, value.1))
                    }

                    data.sort { lData, rData in
                        if lData.count != rData.count {
                            // If counts differ, sort in descending order.
                            return lData.count > rData.count
                        }

                        // Otherwise sort by date in ascending order.

                        if lData.oldestCreationDate == rData.oldestCreationDate {
                            // If dates are the same, just pick one
                            return true
                        }

                        return lData.oldestCreationDate < rData.oldestCreationDate
                    }

                    return data[0].lineWidth
                }
            }
        }
    }

//    private func merge(highlightAnnotations annotations: [(Annotation, PSPDFKit.Annotation)], in viewModel: ViewModel<PDFReaderActionHandler>) {
//        guard let (oldestAnnotation, oldestDocumentAnnotation) = annotations.first, let oldestHighlightAnnotation = oldestDocumentAnnotation as? PSPDFKit.HighlightAnnotation,
//              let indexPath = indexPath(for: oldestAnnotation.key, in: viewModel.state.annotations) else { return }
//
//        var rects: [CGRect] = oldestHighlightAnnotation.rects ?? []
//        var comment = oldestAnnotation.comment
//        var tags: [Tag] = oldestAnnotation.tags
//
//        for (annotation, documentAnnotation) in annotations.dropFirst() {
//            guard let highlightAnnotation = documentAnnotation as? PSPDFKit.HighlightAnnotation else { continue }
//            if let _rects = highlightAnnotation.rects {
//                merge(rects: &rects, with: _rects)
//            }
//            comment += "\n\n" + annotation.comment
//            for tag in annotation.tags {
//                if !tags.contains(tag) {
//                    tags.append(tag)
//                }
//            }
//        }
//
//        let toDeleteDocumentAnnotations = annotations.dropFirst().map({ $0.1 })
//        let toDeleteKeys = toDeleteDocumentAnnotations.compactMap({ $0.key })
//
//        update(viewModel: viewModel) { state in
//            state.ignoreNotifications[.PSPDFAnnotationsRemoved] = Set(toDeleteKeys)
//            state.ignoreNotifications[.PSPDFAnnotationChanged] = [oldestAnnotation.key]
//        }
//
//        viewModel.state.document.undoController.recordCommand(named: nil, in: { recorder in
//            recorder.record(changing: [oldestHighlightAnnotation]) {
//                oldestHighlightAnnotation.rects = rects
//                NotificationCenter.default.post(name: NSNotification.Name.PSPDFAnnotationChanged, object: oldestHighlightAnnotation,
//                                                userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: ["rects", "boundingBox"]])
//            }
//
//            recorder.record(removing: toDeleteDocumentAnnotations) {
//                viewModel.state.document.remove(annotations: toDeleteDocumentAnnotations)
//            }
//        })
//
//        let sortIndex = AnnotationConverter.sortIndex(from: oldestHighlightAnnotation, boundingBoxConverter: boundingBoxConverter)
//        let updatedAnnotation = oldestAnnotation.copy(tags: tags).copy(comment: comment).copy(rects: rects, sortIndex: sortIndex)
//        let attributedComment = htmlAttributedStringConverter.convert(text: comment, baseAttributes: [.font: viewModel.state.commentFont])
//
//        update(viewModel: viewModel) { state in
//            update(state: &state, with: updatedAnnotation, from: oldestAnnotation, at: indexPath, shouldReload: true)
//            state.comments[updatedAnnotation.key] = attributedComment
//            remove(annotations: toDeleteDocumentAnnotations, from: &state)
//        }
//    }
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

    private func set(filter: AnnotationsFilter?, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard filter != viewModel.state.filter else { return }
        filterAnnotations(with: viewModel.state.searchTerm, filter: filter, in: viewModel)
    }

    private func search(for term: String, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTerm = trimmedTerm.isEmpty ? nil : trimmedTerm
        guard newTerm != viewModel.state.searchTerm else { return }
        filterAnnotations(with: newTerm, filter: viewModel.state.filter, in: viewModel)
    }

    /// Filters annotations based on given term and filer parameters.
    /// - parameter term: Term to filter annotations.
    /// - parameter viewModel: ViewModel.
    private func filterAnnotations(with term: String?, filter: AnnotationsFilter?, in viewModel: ViewModel<PDFReaderActionHandler>) {
        if term == nil && filter == nil {
            guard let snapshot = viewModel.state.snapshotKeys else { return }

            for (_, annotations) in viewModel.state.document.allAnnotations(of: .all) {
                for annotation in annotations {
                    if annotation.flags.contains(.hidden) {
                        annotation.flags.remove(.hidden)
                        NotificationCenter.default.post(name: .PSPDFAnnotationChanged, object: annotation, userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: ["flags"]])
                    }
                }
            }

            update(viewModel: viewModel) { state in
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
        let filteredKeys = filteredKeys(from: snapshot, term: term, filter: filter, state: viewModel.state)

        for (_, annotations) in viewModel.state.document.allAnnotations(of: PSPDFKit.Annotation.Kind.all) {
            for annotation in annotations {
                let isHidden = !filteredKeys.contains(where: { $0.key == (annotation.key ?? annotation.uuid) })
                if isHidden && !annotation.flags.contains(.hidden) {
                    annotation.flags.update(with: .hidden)
                    NotificationCenter.default.post(name: .PSPDFAnnotationChanged, object: annotation, userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: ["flags"]])
                } else if !isHidden && annotation.flags.contains(.hidden) {
                    annotation.flags.remove(.hidden)
                    NotificationCenter.default.post(name: .PSPDFAnnotationChanged, object: annotation, userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: ["flags"]])
                }
            }
        }

        update(viewModel: viewModel) { state in
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

    private func filteredKeys(from snapshot: [PDFReaderState.AnnotationKey], term: String?, filter: AnnotationsFilter?, state: PDFReaderState) -> [PDFReaderState.AnnotationKey] {
        if term == nil && filter == nil {
            return snapshot
        }
        return snapshot.filter({ key in
            guard let annotation = state.annotation(for: key) else { return false }
            return self.filter(annotation: annotation, with: term, displayName: state.displayName, username: state.username) && self.filter(annotation: annotation, with: filter)
        })
    }

    private func filter(annotation: PDFAnnotation, with term: String?, displayName: String, username: String) -> Bool {
        guard let term else { return true }
        return annotation.key.lowercased() == term.lowercased() ||
               annotation.author(displayName: displayName, username: username).localizedCaseInsensitiveContains(term) ||
               annotation.comment.localizedCaseInsensitiveContains(term) ||
               (annotation.text ?? "").localizedCaseInsensitiveContains(term) ||
               annotation.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(term) })
    }

    private func filter(annotation: PDFAnnotation, with filter: AnnotationsFilter?) -> Bool {
        guard let filter = filter else { return true }
        let hasTag = filter.tags.isEmpty ? true : annotation.tags.contains(where: { filter.tags.contains($0.name) })
        let hasColor = filter.colors.isEmpty ? true : filter.colors.contains(annotation.color)
        return hasTag && hasColor
    }

    /// Set selected annotation. Also sets `focusSidebarIndexPath` or `focusDocumentLocation` if needed.
    /// - parameter key: Annotation key to be selected. Deselects current annotation if `nil`.
    /// - parameter didSelectInDocument: `true` if annotation was selected in document, false if it was selected in sidebar.
    /// - parameter viewModel: ViewModel.
    private func select(key: PDFReaderState.AnnotationKey?, didSelectInDocument: Bool, in viewModel: ViewModel<PDFReaderActionHandler>) {
        update(viewModel: viewModel) { state in
            _select(key: key, didSelectInDocument: didSelectInDocument, state: &state)
        }
    }

    private func _select(key: PDFReaderState.AnnotationKey?, didSelectInDocument: Bool, state: inout PDFReaderState) {
        guard key != state.selectedAnnotationKey else { return }

        if let existing = state.selectedAnnotationKey {
            if state.sortedKeys.contains(existing) {
                var updatedAnnotationKeys = state.updatedAnnotationKeys ?? []
                updatedAnnotationKeys.append(existing)
                state.updatedAnnotationKeys = updatedAnnotationKeys
            }

            if state.selectedAnnotationCommentActive {
                state.selectedAnnotationCommentActive = false
                state.changes.insert(.activeComment)
            }
        }

        state.changes.insert(.selection)

        guard let key else {
            state.selectedAnnotationKey = nil
            return
        }

        state.selectedAnnotationKey = key

        if !didSelectInDocument {
            if let boundingBoxConverter = delegate, let annotation = state.annotation(for: key) {
                state.focusDocumentLocation = (annotation.page, annotation.boundingBox(boundingBoxConverter: boundingBoxConverter))
            }
        } else {
            state.focusSidebarKey = key
        }

        if state.sortedKeys.contains(key) {
            var updatedAnnotationKeys = state.updatedAnnotationKeys ?? []
            updatedAnnotationKeys.append(key)
            state.updatedAnnotationKeys = updatedAnnotationKeys
        }
    }

    // MARK: - Annotation previews

    /// Starts observing preview controller. If new preview is stored, it will be cached immediately.
    /// - parameter viewModel: ViewModel.
    private func observePreviews(in viewModel: ViewModel<PDFReaderActionHandler>) {
        annotationPreviewController
            .observable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self, weak viewModel] annotationKey, parentKey, image in
                guard let self, let viewModel, viewModel.state.key == parentKey else { return }
                update(viewModel: viewModel) { state in
                    state.previewCache.setObject(image, forKey: (annotationKey as NSString))
                    state.loadedPreviewImageAnnotationKeys = [annotationKey]
                }
            })
            .disposed(by: disposeBag)
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
            annotationPreviewController.preview(for: key, parentKey: viewModel.state.key, libraryId: libraryId, isDark: isDark) { [weak viewModel] image in
                if let image = image {
                    viewModel?.state.previewCache.setObject(image, forKey: nsKey)
                    loadedKeys.insert(key)
                }
                group.leave()
            }
        }

        guard notify else { return }

        group.notify(queue: .main) { [weak self, weak viewModel] in
            guard !loadedKeys.isEmpty, let self, let viewModel else { return }
            update(viewModel: viewModel) { state in
                state.loadedPreviewImageAnnotationKeys = loadedKeys
            }
        }
    }

    // MARK: - Annotation management

    private func tool(from annotationType: AnnotationType) -> PSPDFKit.Annotation.Tool {
        switch annotationType {
        case .note:
            return .note

        case .highlight:
            return .highlight

        case .image:
            return .square

        case .ink:
            return .ink

        case .underline:
            return .underline

        case .freeText:
            return .freeText
        }
    }

    private func addImage(onPage pageIndex: PageIndex, origin: CGPoint, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let activeColor = viewModel.state.toolColors[tool(from: .image)] else { return }
        let color = AnnotationColorGenerator.color(from: activeColor, isHighlight: false, userInterfaceStyle: viewModel.state.interfaceStyle).color
        let rect = CGRect(origin: origin, size: CGSize(width: 100, height: 100))

        let square = SquareAnnotation()
        square.pageIndex = pageIndex
        square.boundingBox = rect
        square.borderColor = color
        square.lineWidth = AnnotationsConfig.imageAnnotationLineWidth

        viewModel.state.document.undoController.recordCommand(named: nil, adding: [square]) {
            viewModel.state.document.add(annotations: [square], options: nil)
        }
    }

    private func addNote(onPage pageIndex: PageIndex, origin: CGPoint, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let activeColor = viewModel.state.toolColors[tool(from: .note)] else { return }
        let color = AnnotationColorGenerator.color(from: activeColor, isHighlight: false, userInterfaceStyle: viewModel.state.interfaceStyle).color
        let rect = CGRect(origin: origin, size: AnnotationsConfig.noteAnnotationSize)

        let note = NoteAnnotation(contents: "")
        note.pageIndex = pageIndex
        note.boundingBox = rect
        note.borderStyle = .dashed
        note.color = color

        viewModel.state.document.undoController.recordCommand(named: nil, adding: [note]) {
            viewModel.state.document.add(annotations: [note], options: nil)
        }
    }

    private func addHighlight(onPage pageIndex: PageIndex, rects: [CGRect], in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let activeColor = viewModel.state.toolColors[tool(from: .highlight)] else { return }
        let (color, alpha, blendMode) = AnnotationColorGenerator.color(from: activeColor, isHighlight: true, userInterfaceStyle: viewModel.state.interfaceStyle)

        let highlight = HighlightAnnotation()
        highlight.rects = rects
        highlight.boundingBox = AnnotationBoundingBoxCalculator.boundingBox(from: rects)
        highlight.alpha = alpha
        highlight.color = color
        if let blendMode {
            highlight.blendMode = blendMode
        }
        highlight.pageIndex = pageIndex

        viewModel.state.document.undoController.recordCommand(named: nil, adding: [highlight]) {
            viewModel.state.document.add(annotations: [highlight], options: nil)
        }
    }

    /// Removes Zotero annotation from document.
    /// - parameter key: Annotation key to remove.
    /// - parameter viewModel: ViewModel.
    private func remove(key: PDFReaderState.AnnotationKey, in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: key),
              let pdfAnnotation = viewModel.state.document.annotations(at: PageIndex(annotation.page)).first(where: { $0.key == annotation.key })
        else { return }
        remove(annotations: [pdfAnnotation], in: viewModel.state.document)
    }

    private func removeSelectedAnnotations(in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard !viewModel.state.selectedAnnotationsDuringEditing.isEmpty else { return }
        let keys = viewModel.state.selectedAnnotationsDuringEditing.filter({ $0.type == .database })
        let pdfAnnotations = keys.compactMap({ key -> PSPDFKit.Annotation? in
            guard let annotation = viewModel.state.annotation(for: key),
                  let pdfAnnotation = viewModel.state.document.annotations(at: PageIndex(annotation.page)).first(where: { $0.key == annotation.key })
            else { return nil }
            return pdfAnnotation
        })
        remove(annotations: pdfAnnotations, in: viewModel.state.document)

        update(viewModel: viewModel) { state in
            state.mergingEnabled = false
            state.deletionEnabled = false
            state.selectedAnnotationsDuringEditing = []
            state.changes = .sidebarEditingSelection
        }
    }

    private func remove(annotations: [PSPDFKit.Annotation], in document: PSPDFKit.Document) {
        document.undoController.recordCommand(named: nil, removing: annotations) {
            for annotation in annotations {
                if annotation.flags.contains(.readOnly) {
                    annotation.flags.remove(.readOnly)
                }
            }
            document.remove(annotations: annotations, options: nil)
        }
    }

    private func set(lineWidth: CGFloat, key: String, viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: PDFReaderState.AnnotationKey(key: key, type: .database)) else { return }
        update(annotation: annotation, lineWidth: lineWidth, in: viewModel.state.document)
    }

    private func set(fontSize: UInt, key: String, viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: PDFReaderState.AnnotationKey(key: key, type: .database)) else { return }
        update(annotation: annotation, fontSize: fontSize, in: viewModel.state.document)
    }

    private func set(color: String, key: String, viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: PDFReaderState.AnnotationKey(key: key, type: .database)) else { return }
        update(annotation: annotation, color: (color, viewModel.state.interfaceStyle), in: viewModel.state.document)
    }

    private func set(comment: NSAttributedString, key: String, viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: PDFReaderState.AnnotationKey(key: key, type: .database)) else { return }

        let htmlComment = htmlAttributedStringConverter.convert(attributedString: comment)

        update(viewModel: viewModel) { state in
            state.comments[key] = comment
        }

        update(annotation: annotation, contents: htmlComment, in: viewModel.state.document)
    }

    private func set(highlightText: String, key: String, viewModel: ViewModel<PDFReaderActionHandler>) {
        let values = [KeyBaseKeyPair(key: FieldKeys.Item.Annotation.text, baseKey: nil): highlightText]
        let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }

            DDLogError("PDFReaderActionHandler: can't update annotation \(key) - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func set(tags: [Tag], key: String, viewModel: ViewModel<PDFReaderActionHandler>) {
        let request = EditTagsForItemDbRequest(key: key, libraryId: viewModel.state.library.identifier, tags: tags)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }

            DDLogError("PDFReaderActionHandler: can't set tags \(key) - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func set(
        color: String,
        lineWidth: CGFloat,
        fontSize: UInt,
        pageLabel: String,
        updateSubsequentLabels: Bool,
        highlightText: String,
        key: String,
        viewModel: ViewModel<PDFReaderActionHandler>
    ) {
        // `lineWidth`, `fontSize` and `color` is stored in `Document`, update document, which will trigger a notification wich will update the DB
        guard let annotation = viewModel.state.annotation(for: PDFReaderState.AnnotationKey(key: key, type: .database)) else { return }
        update(annotation: annotation, color: (color, viewModel.state.interfaceStyle), lineWidth: lineWidth, fontSize: fontSize, in: viewModel.state.document)

        // Update remaining values directly
        let values = [KeyBaseKeyPair(key: FieldKeys.Item.Annotation.pageLabel, baseKey: nil): pageLabel, KeyBaseKeyPair(key: FieldKeys.Item.Annotation.text, baseKey: nil): highlightText]
        let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }

            DDLogError("PDFReaderActionHandler: can't update annotation \(key) - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func update(
        annotation: PDFAnnotation,
        color: (String, UIUserInterfaceStyle)? = nil,
        lineWidth: CGFloat? = nil,
        fontSize: UInt? = nil,
        contents: String? = nil,
        in document: PSPDFKit.Document
    ) {
        guard let pdfAnnotation = document.annotations(at: PageIndex(annotation.page)).first(where: { $0.key == annotation.key }) else { return }

        var changes: PdfAnnotationChanges = []

        if let lineWidth, lineWidth.rounded(to: 3) != annotation.lineWidth {
            changes.insert(.lineWidth)
        }
        if let fontSize, fontSize != annotation.fontSize {
            changes.insert(.fontSize)
        }
        if let (color, _) = color, color != annotation.color {
            changes.insert(.color)
        }
        if let contents, contents != annotation.comment {
            changes.insert(.contents)
        }

        guard !changes.isEmpty else { return }

        document.undoController.recordCommand(named: nil, changing: [pdfAnnotation]) {
            if changes.contains(.lineWidth), let inkAnnotation = pdfAnnotation as? PSPDFKit.InkAnnotation, let lineWidth {
                inkAnnotation.lineWidth = lineWidth.rounded(to: 3)
            }

            if changes.contains(.color), let (color, interfaceStyle) = color {
                let (_color, alpha, blendMode) = AnnotationColorGenerator.color(from: UIColor(hex: color), isHighlight: (annotation.type == .highlight), userInterfaceStyle: interfaceStyle)
                pdfAnnotation.color = _color
                pdfAnnotation.alpha = alpha
                if let blendMode {
                    pdfAnnotation.blendMode = blendMode
                }
            }

            if changes.contains(.contents), let contents {
                pdfAnnotation.contents = contents
            }

            if changes.contains(.fontSize), let textAnnotation = pdfAnnotation as? PSPDFKit.FreeTextAnnotation, let fontSize {
                textAnnotation.fontSize = CGFloat(fontSize)
            }

            NotificationCenter.default.post(
                name: NSNotification.Name.PSPDFAnnotationChanged,
                object: pdfAnnotation,
                userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: PdfAnnotationChanges.stringValues(from: changes)]
            )
        }
    }

    // MARK: - Store PDF notifications to DB

    /// Updates annotations based on insertions to PSPDFKit document.
    /// - parameter annotations: Annotations that were added to the document.
    /// - parameter viewModel: ViewModel.
    private func add(annotations: [PSPDFKit.Annotation], in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let boundingBoxConverter = delegate else { return }

        DDLogInfo("PDFReaderActionHandler: annotations added - \(annotations.map({ "\(type(of: $0));key=\($0.key ?? "nil");" }))")

        let (keptAsIs, toRemove, toAdd) = transformIfNeeded(annotations: annotations, state: viewModel.state)
        let finalAnnotations = keptAsIs + toAdd
        for annotation in finalAnnotations {
            if annotation.key == nil {
                annotation.user = viewModel.state.displayName
                annotation.customData = [AnnotationsConfig.keyKey: KeyGenerator.newKey]
            }
        }
        if !toRemove.isEmpty || !toAdd.isEmpty {
            let document = viewModel.state.document
            let undoController = document.undoController
            let undoManager = undoController.undoManager
            // Originally added annotations are transformed, so we remove them by performing last undo.
            // This also removes the undo command from the stack, allowing us to record the transformed addition.
            undoManager.disableUndoRegistration()
            if undoManager.canUndo {
                undoManager.undo()
            }
            undoManager.enableUndoRegistration()
            undoController.recordCommand(named: nil, adding: finalAnnotations) {
                // Remove may be superfluous, if those annotations are already removed by the undo, but it doesn't cause any issue.
                document.remove(annotations: toRemove, options: [.suppressNotifications: true])
                // Transformed annotations need to be added, before they are converted, otherwise their document property is nil.
                document.add(annotations: finalAnnotations, options: [.suppressNotifications: true])
            }
        }

        guard !finalAnnotations.isEmpty else { return }
        let documentAnnotations: [PDFDocumentAnnotation] = finalAnnotations.compactMap { annotation in
            var color: UIColor? = annotation.color
            if color == nil, let tool = tool(from: annotation), let activeColor = viewModel.state.toolColors[tool] {
                color = activeColor
            }
            guard let color else { return nil }
            let documentAnnotation = AnnotationConverter.annotation(
                from: annotation,
                color: color.hexString,
                library: viewModel.state.library,
                username: viewModel.state.username,
                displayName: viewModel.state.displayName,
                boundingBoxConverter: boundingBoxConverter
            )
            guard let documentAnnotation else { return nil }
            // Only create preview for annotations that will be
            annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, isDark: (viewModel.state.interfaceStyle == .dark))
            return documentAnnotation
        }

        let request = CreatePDFAnnotationsDbRequest(
            attachmentKey: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            annotations: documentAnnotations,
            userId: viewModel.state.userId,
            schemaController: schemaController,
            boundingBoxConverter: boundingBoxConverter
        )
        perform(request: request) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }

            DDLogError("PDFReaderActionHandler: can't add annotations - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantAddAnnotations
            }
        }

        func transformIfNeeded(annotations: [PSPDFKit.Annotation], state: PDFReaderState) -> (keptAsIs: [PSPDFKit.Annotation], toRemove: [PSPDFKit.Annotation], toAdd: [PSPDFKit.Annotation]) {
            var keptAsIs: [PSPDFKit.Annotation] = []
            var toRemove: [PSPDFKit.Annotation] = []
            var toAdd: [PSPDFKit.Annotation] = []

            for annotation in annotations {
                guard let tool = tool(from: annotation), let activeColor = state.toolColors[tool] else { continue }
                // `AnnotationStateManager` doesn't apply the `blendMode` to created annotations, so it needs to be applied to newly created annotations here.
                let (_, _, blendMode) = AnnotationColorGenerator.color(from: activeColor, isHighlight: (annotation is PSPDFKit.HighlightAnnotation), userInterfaceStyle: state.interfaceStyle)
                annotation.blendMode = blendMode ?? .normal

                // Either annotation is new (key not assigned) or the user used undo/redo and we check whether the annotation exists in DB
                guard annotation.key == nil || state.annotation(for: .init(key: annotation.key!, type: .database)) == nil else {
                    keptAsIs.append(annotation)
                    continue
                }
                var workingAnnotation = annotation

                if let mergedHighlightAnnotation = mergeHighlightRectsIfNeeded(annotation: annotation) {
                    DDLogInfo("PDFReaderActionHandler: did merge highlight annotation rects")
                    toRemove.append(annotation)
                    toAdd.append(mergedHighlightAnnotation)
                    workingAnnotation = mergedHighlightAnnotation
                }

                let splitAnnotations = splitIfNeeded(annotation: workingAnnotation)

                guard splitAnnotations.count > 1 else {
                    if workingAnnotation == annotation {
                        keptAsIs.append(annotation)
                    }
                    continue
                }
                DDLogInfo("PDFReaderActionHandler: did split annotations into \(splitAnnotations.count)")
                if workingAnnotation == annotation {
                    toRemove.append(annotation)
                } else {
                    toAdd.removeLast()
                }
                toAdd.append(contentsOf: splitAnnotations)
            }

            return (keptAsIs, toRemove, toAdd)

            // TODO: Remove if issue is fixed in PSPDFKit
            /// Merges highlight annotation rects that are in the same text line. If not a higlight annotation, or merges are not needed, it returns nil.
            /// Issue appeared in PSPDFKit 13.5.0
            /// - parameter annotation: Annotation to split
            func mergeHighlightRectsIfNeeded(annotation: PSPDFKit.Annotation) -> HighlightAnnotation? {
                guard annotation is HighlightAnnotation, let rects = annotation.rects, rects.count > 1 else { return nil }
                // Check if there are gaps for sequential highlight rects on the same line, and if so transform the annotation to eliminate them.
                var mergedRects: [CGRect] = []
                for rect in rects {
                    guard let previousRect = mergedRects.last, rect.minY == previousRect.minY, rect.height == previousRect.height else {
                        mergedRects.append(rect)
                        continue
                    }
                    let mergedRect = CGRect(x: previousRect.minX, y: previousRect.minY, width: rect.minX + rect.width - previousRect.minX, height: previousRect.height)
                    mergedRects.removeLast()
                    mergedRects.append(mergedRect)
                }
                guard mergedRects.count < rects.count else { return nil }
                let newAnnotation = HighlightAnnotation()
                newAnnotation.rects = mergedRects
                newAnnotation.boundingBox = AnnotationBoundingBoxCalculator.boundingBox(from: rects)
                newAnnotation.alpha = annotation.alpha
                newAnnotation.color = annotation.color
                newAnnotation.blendMode = annotation.blendMode
                newAnnotation.contents = annotation.contents
                newAnnotation.pageIndex = annotation.pageIndex
                return newAnnotation
            }

            /// Splits annotation if it exceedes position limit. If it is within limit, it returns original annotation.
            /// - parameter annotation: Annotation to split
            /// - returns: Array with original annotation if limit was not exceeded. Otherwise array of new split annotations.
            func splitIfNeeded(annotation: PSPDFKit.Annotation) -> [PSPDFKit.Annotation] {
                if let annotation = annotation as? HighlightAnnotation, let rects = annotation.rects, let splitRects = AnnotationSplitter.splitRectsIfNeeded(rects: rects) {
                    return createAnnotations(from: splitRects, original: annotation)
                }

                if let annotation = annotation as? InkAnnotation, let paths = annotation.lines, let splitPaths = AnnotationSplitter.splitPathsIfNeeded(paths: paths) {
                    return createAnnotations(from: splitPaths, original: annotation)
                }

                return [annotation]

                func createAnnotations(from splitRects: [[CGRect]], original: HighlightAnnotation) -> [HighlightAnnotation] {
                    guard splitRects.count > 1 else { return [original] }
                    return splitRects.map { rects -> HighlightAnnotation in
                        let new = HighlightAnnotation()
                        new.rects = rects
                        new.boundingBox = AnnotationBoundingBoxCalculator.boundingBox(from: rects)
                        new.alpha = original.alpha
                        new.color = original.color
                        new.blendMode = original.blendMode
                        new.contents = original.contents
                        new.pageIndex = original.pageIndex
                        return new
                    }
                }

                func createAnnotations(from splitPaths: [[[DrawingPoint]]], original: InkAnnotation) -> [InkAnnotation] {
                    guard splitPaths.count > 1 else { return [original] }
                    return splitPaths.map { paths in
                        let new = InkAnnotation(lines: paths)
                        new.lineWidth = original.lineWidth
                        new.alpha = original.alpha
                        new.color = original.color
                        new.blendMode = original.blendMode
                        new.contents = original.contents
                        new.pageIndex = original.pageIndex
                        return new
                    }
                }
            }
        }

        func tool(from annotation: PSPDFKit.Annotation) -> PSPDFKit.Annotation.Tool? {
            if annotation is PSPDFKit.HighlightAnnotation {
                return .highlight
            }
            if annotation is PSPDFKit.NoteAnnotation {
                return .note
            }
            if annotation is PSPDFKit.SquareAnnotation {
                return .square
            }
            if annotation is PSPDFKit.InkAnnotation {
                return .ink
            }
            if annotation is PSPDFKit.UnderlineAnnotation {
                return .underline
            }
            if annotation is PSPDFKit.FreeTextAnnotation {
                return .freeText
            }
            return nil
        }
    }

    private func change(annotation: PSPDFKit.Annotation, with changes: [String], in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard !changes.isEmpty, let key = annotation.key, let boundingBoxConverter = delegate else { return }

        annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, isDark: (viewModel.state.interfaceStyle == .dark))

        let hasChanges: (PdfAnnotationChanges) -> Bool = { pdfChanges in
            let rawPdfChanges = PdfAnnotationChanges.stringValues(from: pdfChanges)
            for change in changes {
                if rawPdfChanges.contains(change) {
                    return true
                }
            }
            return false
        }

        DDLogInfo("PDFReaderActionHandler: annotation changed - \(key); \(changes)")

        var requests: [DbRequest] = []

        if let inkAnnotation = annotation as? PSPDFKit.InkAnnotation {
            if hasChanges([.paths, .boundingBox]) {
                let paths = AnnotationConverter.paths(from: inkAnnotation)
                requests.append(EditAnnotationPathsDbRequest(key: key, libraryId: viewModel.state.library.identifier, paths: paths, boundingBoxConverter: boundingBoxConverter))
            }

            if hasChanges(.lineWidth) {
                let values = [KeyBaseKeyPair(key: FieldKeys.Item.Annotation.Position.lineWidth, baseKey: FieldKeys.Item.Annotation.position): "\(inkAnnotation.lineWidth.rounded(to: 3))"]
                let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
                requests.append(request)
            }
        } else if hasChanges([.boundingBox, .rects]), let rects = AnnotationConverter.rects(from: annotation) {
            requests.append(EditAnnotationRectsDbRequest(key: key, libraryId: viewModel.state.library.identifier, rects: rects, boundingBoxConverter: boundingBoxConverter))
        } else if hasChanges([.boundingBox]), let rects = AnnotationConverter.rects(from: annotation) {
            // FreeTextAnnotation has only `boundingBox` change, not paired with paths or rects.
            requests.append(EditAnnotationRectsDbRequest(key: key, libraryId: viewModel.state.library.identifier, rects: rects, boundingBoxConverter: boundingBoxConverter))
        }

        if let textAnnotation = annotation as? PSPDFKit.FreeTextAnnotation {
            if hasChanges([.rotation]) {
                requests.append(EditAnnotationRotationDbRequest(key: key, libraryId: viewModel.state.library.identifier, rotation: textAnnotation.rotation))
            }

            if hasChanges([.fontSize]) {
                requests.append(EditAnnotationFontSizeDbRequest(key: key, libraryId: viewModel.state.library.identifier, size: UInt(textAnnotation.fontSize)))
            }
        }

        if hasChanges(.color) {
            let values = [KeyBaseKeyPair(key: FieldKeys.Item.Annotation.color, baseKey: nil): annotation.baseColor]
            let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
            requests.append(request)
        }

        if hasChanges(.contents) {
            let values = [KeyBaseKeyPair(key: FieldKeys.Item.Annotation.comment, baseKey: nil): annotation.contents ?? ""]
            let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
            requests.append(request)
        }

        guard !requests.isEmpty else { return }

        perform(writeRequests: requests) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }

            DDLogError("PDFReaderActionHandler: can't update changed annotations - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func remove(annotations: [PSPDFKit.Annotation], in viewModel: ViewModel<PDFReaderActionHandler>) {
        let keys = annotations.compactMap({ $0.key })

        for annotation in annotations {
            annotationPreviewController.delete(for: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
        }

        DDLogInfo("PDFReaderActionHandler: annotations deleted - \(annotations.map({ "\(type(of: $0));key=\($0.key ?? "nil");" }))")

        guard !keys.isEmpty else { return }

        let request = MarkObjectsAsDeletedDbRequest<RItem>(keys: keys, libraryId: viewModel.state.library.identifier)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let self, let viewModel, let error else { return }

            DDLogError("PDFReaderActionHandler: can't remove annotations \(keys) - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantDeleteAnnotation
            }
        }
    }

    // MARK: - Initial load

    /// Loads annotations from DB, converts them to Zotero annotations and adds matching PSPDFKit annotations to document.
    private func loadDocumentData(boundingBoxConverter: AnnotationBoundingBoxConverter, in viewModel: ViewModel<PDFReaderActionHandler>) {
        do {
            guard let boundingBoxConverter = delegate, viewModel.state.document.pageCount > 0 else {
                throw PDFReaderState.Error.documentEmpty
            }

            let start = CFAbsoluteTimeGetCurrent()

            let key = viewModel.state.key
            let (item, liveAnnotations, storedPage) = try loadItemAnnotationsAndPage(for: key, libraryId: viewModel.state.library.identifier)

            if checkWhetherMd5Changed(forItem: item, andUpdateViewModel: viewModel, handler: self) {
                return
            }

            let (library, libraryToken) = try viewModel.state.library.identifier.observe(in: dbStorage, changes: { [weak self, weak viewModel] library in
                guard let self, let viewModel else { return }
                observe(library: library, viewModel: viewModel, handler: self)
            })
            let itemToken = observe(item: item, viewModel: viewModel, handler: self)
            let token = observe(items: liveAnnotations, viewModel: viewModel, handler: self)
            let databaseAnnotations = liveAnnotations.freeze()
            let documentAnnotations = loadAnnotations(from: viewModel.state.document, library: library, username: viewModel.state.username, displayName: viewModel.state.displayName)
            let dbToPdfAnnotations = AnnotationConverter.annotations(
                from: databaseAnnotations,
                interfaceStyle: viewModel.state.interfaceStyle,
                currentUserId: viewModel.state.userId,
                library: library,
                displayName: viewModel.state.displayName,
                username: viewModel.state.username,
                boundingBoxConverter: boundingBoxConverter
            )
            let sortedKeys = createSortedKeys(fromDatabaseAnnotations: databaseAnnotations, documentAnnotations: documentAnnotations)
            let isDark = viewModel.state.interfaceStyle == .dark
            update(document: viewModel.state.document, zoteroAnnotations: dbToPdfAnnotations, key: key, libraryId: library.identifier, isDark: isDark)
            annotationPreviewController.async { controller in
                for annotation in dbToPdfAnnotations {
                    controller.store(for: annotation, parentKey: key, libraryId: library.identifier, isDark: isDark)
                }
            }
            let (page, selectedData) = preselectedData(databaseAnnotations: databaseAnnotations, storedPage: storedPage, boundingBoxConverter: boundingBoxConverter, in: viewModel)

            let end = CFAbsoluteTimeGetCurrent()
            DDLogInfo("TTL: \(end - start)")

            update(viewModel: viewModel) { state in
                state.library = library
                state.libraryToken = libraryToken
                state.databaseAnnotations = databaseAnnotations
                state.documentAnnotations = documentAnnotations
                state.sortedKeys = sortedKeys
                state.visiblePage = page
                state.token = token
                state.itemToken = itemToken
                state.changes = [.annotations, .initialDataLoaded]
                state.initialPage = nil

                if let (key, location) = selectedData {
                    state.selectedAnnotationKey = key
                    state.focusDocumentLocation = location
                    state.focusSidebarKey = key
                }
            }

            observeDocument(in: viewModel)
        } catch let error {
            // TODO: - Show error
        }

        func observe(library: Library, viewModel: ViewModel<PDFReaderActionHandler>, handler: PDFReaderActionHandler) {
            handler.update(viewModel: viewModel) { state in
                if state.selectedAnnotationKey != nil {
                    state.selectedAnnotationKey = nil
                    state.changes = [.selection, .selectionDeletion]
                }
                state.library = library
                state.changes.insert(.library)
            }
        }

        func observe(items: Results<RItem>, viewModel: ViewModel<PDFReaderActionHandler>, handler: PDFReaderActionHandler) -> NotificationToken {
            return items.observe { [weak handler, weak viewModel] change in
                guard let handler, let viewModel else { return }
                switch change {
                case .update(let objects, let deletions, let insertions, let modifications):
                    handler.update(objects: objects, deletions: deletions, insertions: insertions, modifications: modifications, viewModel: viewModel)

                case .error, .initial: break
                }
            }
        }

        func observe(item: RItem, viewModel: ViewModel<PDFReaderActionHandler>, handler: PDFReaderActionHandler) -> NotificationToken {
            return item.observe(keyPaths: ["fields"], on: .main) { [weak handler, weak viewModel] (change: ObjectChange<RItem>) in
                guard let handler, let viewModel else { return }
                switch change {
                case .change(let item, _):
                    checkWhetherMd5Changed(forItem: item, andUpdateViewModel: viewModel, handler: handler)

                case .deleted, .error:
                    break
                }
            }
        }

        @discardableResult
        func checkWhetherMd5Changed(forItem item: RItem, andUpdateViewModel viewModel: ViewModel<PDFReaderActionHandler>, handler: PDFReaderActionHandler) -> Bool {
            guard let documentURL = viewModel.state.document.fileURL, let md5 = md5(from: documentURL), item.backendMd5 != md5 else { return false }
            handler.update(viewModel: viewModel) { state in
                state.changes = .md5
            }
            return true
        }

        func loadItemAnnotationsAndPage(for key: String, libraryId: LibraryIdentifier) throws -> (RItem, Results<RItem>, Int) {
            var results: Results<RItem>!
            var pageStr = "0"
            var item: RItem!

            try dbStorage.perform(on: .main, with: { coordinator in
                item = try coordinator.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))
                pageStr = try coordinator.perform(request: ReadDocumentDataDbRequest(attachmentKey: key, libraryId: libraryId))
                results = try coordinator.perform(request: ReadAnnotationsDbRequest(attachmentKey: key, libraryId: libraryId))
            })

            guard let page = Int(pageStr) else {
                throw PDFReaderState.Error.pageNotInt
            }

            return (item, results, page)
        }
    }

    private func preselectedData(
        databaseAnnotations: Results<RItem>,
        storedPage: Int,
        boundingBoxConverter: AnnotationBoundingBoxConverter,
        in viewModel: ViewModel<PDFReaderActionHandler>
    ) -> (Int, (PDFReaderState.AnnotationKey, AnnotationDocumentLocation)?) {
        if let key = viewModel.state.selectedAnnotationKey, let item = databaseAnnotations.filter(.key(key.key)).first, let annotation = PDFDatabaseAnnotation(item: item) {
            let page = annotation._page ?? storedPage
            let boundingBox = annotation.boundingBox(boundingBoxConverter: boundingBoxConverter)
            return (page, (key, (page, boundingBox)))
        }

        if let initialPage = viewModel.state.initialPage, initialPage >= 0 && initialPage < viewModel.state.document.pageCount {
            return (initialPage, nil)
        }

        if storedPage >= 0 && storedPage < viewModel.state.document.pageCount {
            return (storedPage, nil)
        }

        return (Int(viewModel.state.document.pageCount - 1), nil)
    }

    private func observeDocument(in viewModel: ViewModel<PDFReaderActionHandler>) {
        let nextBlock: (Notification) -> Void = { [weak self, weak viewModel] notification in
            guard let self, let viewModel else { return }
            processAnnotationObserving(handler: self, notification: notification, viewModel: viewModel)
        }

        NotificationCenter.default.rx
            .notification(.PSPDFAnnotationChanged)
            .subscribe(onNext: nextBlock)
            .disposed(by: pdfDisposeBag)

        NotificationCenter.default.rx
            .notification(.PSPDFAnnotationsAdded)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: nextBlock)
            .disposed(by: pdfDisposeBag)

        NotificationCenter.default.rx
            .notification(.PSPDFAnnotationsRemoved)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: nextBlock)
            .disposed(by: pdfDisposeBag)

        func processAnnotationObserving(handler: PDFReaderActionHandler, notification: Notification, viewModel: ViewModel<PDFReaderActionHandler>) {
            guard isNotification(notification, from: viewModel.state.document) else { return }

            // TODO: Improve this if PSPDFKit allows more control for automatic command recording, e.g. by providing a detached recorder
            // Delay handling of notifications until next main run loop iteration, so they have completely recorded their undo command.
            DispatchQueue.main.async { [weak handler, weak viewModel] in
                guard let handler, let viewModel else { return }

                switch notification.name {
                case .PSPDFAnnotationChanged:
                    guard let annotation = notification.object as? PSPDFKit.Annotation else { return }

                    if let changes = notification.userInfo?[PSPDFAnnotationChangedNotificationKeyPathKey] as? [String] {
                        if let freeTextAnnotation = annotation as? PSPDFKit.FreeTextAnnotation, let key = annotation.key {
                            if changes.contains("rotation") {
                                // Debounce these notifications because FreeTextAnnotation rotation change spams these annotations in milliseconds
                                // and it looks bad in sidebar while it's also unnecessary cpu burden.
                                let disposeBag = DisposeBag()
                                handler.freeTextAnnotationRotationDebounceDisposeBagByKey[key] = disposeBag
                                handler.debouncedFreeTextAnnotationAndChangesByKey[key] = (changes, freeTextAnnotation)
                                Single<Int>.timer(.milliseconds(100), scheduler: MainScheduler.instance)
                                    .subscribe(onSuccess: { [weak handler, weak viewModel] _ in
                                        guard let handler, let viewModel else { return }
                                        handler.freeTextAnnotationRotationDebounceDisposeBagByKey[key] = nil
                                        if let (changes, annotation) = handler.debouncedFreeTextAnnotationAndChangesByKey[key] {
                                            handler.debouncedFreeTextAnnotationAndChangesByKey[key] = nil
                                            handler.change(annotation: annotation, with: changes, in: viewModel)
                                        }
                                    })
                                    .disposed(by: disposeBag)
                            } else {
                                handler.freeTextAnnotationRotationDebounceDisposeBagByKey[key] = nil
                                if let (changes, annotation) = handler.debouncedFreeTextAnnotationAndChangesByKey[key] {
                                    handler.debouncedFreeTextAnnotationAndChangesByKey[key] = nil
                                    handler.change(annotation: annotation, with: changes, in: viewModel)
                                }
                                handler.change(annotation: annotation, with: changes, in: viewModel)
                            }
                        } else {
                            handler.change(annotation: annotation, with: changes, in: viewModel)
                        }
                    } else if annotation is PSPDFKit.InkAnnotation, notification.userInfo?["com.pspdfkit.sourceDrawLayer"] != nil {
                        let changes = PdfAnnotationChanges.stringValues(from: [.boundingBox, .paths])
                        handler.change(annotation: annotation, with: changes, in: viewModel)
                    }

                case .PSPDFAnnotationsAdded:
                    guard let annotations = notification.object as? [PSPDFKit.Annotation] else { return }
                    handler.add(annotations: annotations, in: viewModel)

                case .PSPDFAnnotationsRemoved:
                    guard let annotations = notification.object as? [PSPDFKit.Annotation] else { return }
                    handler.remove(annotations: annotations, in: viewModel)

                default:
                    break
                }
            }

            handler.update(viewModel: viewModel) { state in
                state.pdfNotification = notification
            }

            func isNotification(_ notification: Notification, from document: PSPDFKit.Document) -> Bool {
                guard let annotation = (notification.object as? PSPDFKit.Annotation) ?? (notification.object as? [PSPDFKit.Annotation])?.first else { return false }
                return annotation.document == document
            }
        }
    }

    private func createSortedKeys(fromDatabaseAnnotations databaseAnnotations: Results<RItem>, documentAnnotations: [String: PDFDocumentAnnotation]) -> [PDFReaderState.AnnotationKey] {
        var keys: [(PDFReaderState.AnnotationKey, String)] = []
        for item in databaseAnnotations {
            guard let annotation = PDFDatabaseAnnotation(item: item), validate(databaseAnnotation: annotation) else { continue }
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

    private func validate(databaseAnnotation: PDFDatabaseAnnotation) -> Bool {
        if databaseAnnotation._page == nil {
            return false
        }

        switch databaseAnnotation.type {
        case .ink:
            if databaseAnnotation.item.paths.isEmpty {
                DDLogInfo("PDFReaderActionHandler: ink annotation \(databaseAnnotation.key) missing paths")
                return false
            }

        case .highlight, .image, .note, .underline:
            if databaseAnnotation.item.rects.isEmpty {
                DDLogInfo("PDFReaderActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing rects")
                return false
            }

        case .freeText:
            if databaseAnnotation.item.rects.isEmpty {
                DDLogInfo("PDFReaderActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing rects")
                return false
            }
            if databaseAnnotation.fontSize == nil {
                DDLogInfo("PDFReaderActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing fontSize")
                return false
            }
            if databaseAnnotation.rotation == nil {
                DDLogInfo("PDFReaderActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing rotation")
                return false
            }
        }

        // Sort index consists of 3 parts separated by "|":
        // - 1. page index (5 characters)
        // - 2. character offset (6 characters)
        // - 3. y position from top (5 characters)
        let sortIndex = databaseAnnotation.sortIndex
        let parts = sortIndex.split(separator: "|")
        if parts.count != 3 || parts[0].count != 5 || parts[1].count != 6 || parts[2].count != 5 {
            DDLogInfo("PDFReaderActionHandler: invalid sort index (\(sortIndex)) for \(databaseAnnotation.key)")
            return false
        }

        return true
    }

    private func loadAnnotations(from document: PSPDFKit.Document, library: Library, username: String, displayName: String) -> [String: PDFDocumentAnnotation] {
        var annotations: [String: PDFDocumentAnnotation] = [:]
        for (_, pdfAnnotations) in document.allAnnotations(of: AnnotationsConfig.supported) {
            for pdfAnnotation in pdfAnnotations {
                // Check whether square annotation was previously created by Zotero. If it's just "normal" square (instead of our image) annotation, don't convert it to Zotero annotation.
                if let square = pdfAnnotation as? PSPDFKit.SquareAnnotation, !square.isZoteroAnnotation {
                    continue
                }

                guard let annotation = AnnotationConverter.annotation(
                    from: pdfAnnotation,
                    color: (pdfAnnotation.color?.hexString ?? "#000000"),
                    library: library,
                    username: username,
                    displayName: displayName,
                    boundingBoxConverter: delegate
                )
                else { continue }

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
                annotationPreviewController.async { controller in
                    controller.store(for: annotation, parentKey: key, libraryId: libraryId, isDark: isDark)
                }
            }
        }
        var filteredZoteroAnnotations: [PSPDFKit.Annotation] = []
        for annotation in zoteroAnnotations {
            guard annotation.pageIndex < document.pageCount else {
                DDLogError("PDFReaderActionHandler: annotation \(annotation.key ?? "-") for item \(key); \(libraryId) has incorrect page index - \(annotation.pageIndex) / \(document.pageCount)")
                continue
            }
            filteredZoteroAnnotations.append(annotation)
        }
        // Add zotero annotations to document
        document.add(annotations: filteredZoteroAnnotations, options: [.suppressNotifications: true])
    }

    // MARK: - Translate sync (db) changes to PDF document

    private func update(objects: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int], viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let boundingBoxConverter = delegate else { return }

        DDLogInfo("PDFReaderActionHandler: database annotation changed")

        // Get sorted database keys
        var keys = (viewModel.state.snapshotKeys ?? viewModel.state.sortedKeys).filter({ $0.type == .database })
        var comments = viewModel.state.comments
        var selectKey: PDFReaderState.AnnotationKey?
        var selectionDeleted = false
        // Update database keys based on realm notification
        var updatedKeys: [PDFReaderState.AnnotationKey] = []
        // Collect modified, deleted and inserted annotations to update the `Document`
        var updatedPdfAnnotations: [(PSPDFKit.Annotation, PDFDatabaseAnnotation)] = []
        var deletedPdfAnnotations: [PSPDFKit.Annotation] = []
        var insertedPdfAnnotations: [PSPDFKit.Annotation] = []

        // Check which annotations changed and update `Document`
        for index in modifications {
            if index >= keys.count {
                DDLogWarn("PDFReaderActionHandler: tried modifying index out of bounds! keys.count=\(keys.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)")
                continue
            }

            let key = keys[index]
            guard let item = objects.filter(.key(key.key)).first, let annotation = PDFDatabaseAnnotation(item: item) else { continue }

            if canUpdate(key: key, item: item, at: index, viewModel: viewModel) {
                DDLogInfo("PDFReaderActionHandler: update key \(key)")
                updatedKeys.append(key)

                if item.changeType == .sync {
                    // Update comment if it's remote sync change
                    DDLogInfo("PDFReaderActionHandler: update comment")
                    comments[key.key] = htmlAttributedStringConverter.convert(text: annotation.comment, baseAttributes: [.font: viewModel.state.commentFont])
                }
            }

            guard item.changeType == .sync, let pdfAnnotation = viewModel.state.document.annotations(at: PageIndex(annotation.page)).first(where: { $0.key == key.key }) else { continue }

            DDLogInfo("PDFReaderActionHandler: update PDF annotation")
            updatedPdfAnnotations.append((pdfAnnotation, annotation))
        }

        var shouldCancelUpdate = false

        // Find `Document` annotations to be removed from document
        for index in deletions.reversed() {
            if index >= keys.count {
                DDLogWarn("PDFReaderActionHandler: tried removing index out of bounds! keys.count=\(keys.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)")
                shouldCancelUpdate = true
                break
            }

            let key = keys.remove(at: index)
            DDLogInfo("PDFReaderActionHandler: delete key \(key)")

            if viewModel.state.selectedAnnotationKey == key {
                DDLogInfo("PDFReaderActionHandler: deleted selected annotation")
                selectionDeleted = true
            }

            guard let oldAnnotation = PDFDatabaseAnnotation(item: viewModel.state.databaseAnnotations[index]),
                  let pdfAnnotation = viewModel.state.document.annotations(at: PageIndex(oldAnnotation.page)).first(where: { $0.key == oldAnnotation.key })
            else { continue }
            DDLogInfo("PDFReaderActionHandler: delete PDF annotation")
            deletedPdfAnnotations.append(pdfAnnotation)
        }

        if shouldCancelUpdate {
            return
        }

        // Create `PSPDFKit.Annotation`s which need to be added to the `Document`
        for index in insertions {
            if index > keys.count {
                DDLogWarn("PDFReaderActionHandler: tried inserting index out of bounds! keys.count=\(keys.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)")
                shouldCancelUpdate = true
                break
            }

            let item = objects[index]
            keys.insert(PDFReaderState.AnnotationKey(key: item.key, type: .database), at: index)
            DDLogInfo("PDFReaderActionHandler: insert key \(item.key)")

            guard let annotation = PDFDatabaseAnnotation(item: item) else {
                DDLogWarn("PDFReaderActionHandler: tried inserting unsupported annotation (\(item.annotationType))! keys.count=\(keys.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)")
                shouldCancelUpdate = true
                break
            }
            guard annotation.page < viewModel.state.document.pageCount else {
                DDLogWarn("PDFReaderActionHandler: tried inserting page (\(annotation.page)) outside of document page count (\(viewModel.state.document.pageCount)); \(annotation.key); \(viewModel.state.key)")
                continue
            }

            switch item.changeType {
            case .user:
                // Select newly created annotation if needed
                let sidebarVisible = delegate?.isSidebarVisible ?? false
                let isNote = annotation.type == .note
                if !viewModel.state.sidebarEditingEnabled && (sidebarVisible || isNote) {
                    selectKey = PDFReaderState.AnnotationKey(key: item.key, type: .database)
                    DDLogInfo("PDFReaderActionHandler: select new annotation")
                }

            case .sync, .syncResponse:
                let pdfAnnotation = AnnotationConverter.annotation(
                    from: annotation,
                    type: .zotero,
                    interfaceStyle: viewModel.state.interfaceStyle,
                    currentUserId: viewModel.state.userId,
                    library: viewModel.state.library,
                    displayName: viewModel.state.displayName,
                    username: viewModel.state.username,
                    boundingBoxConverter: boundingBoxConverter
                )
                insertedPdfAnnotations.append(pdfAnnotation)
                DDLogInfo("PDFReaderActionHandler: insert PDF annotation")
            }
        }

        if shouldCancelUpdate {
            return
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

        // Temporarily disable PDF notifications, because these changes were made by sync and they don't need to be translated back to the database
        pdfDisposeBag = DisposeBag()
        // Update annotations in `Document`
        for (pdfAnnotation, annotation) in updatedPdfAnnotations {
            update(pdfAnnotation: pdfAnnotation, with: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, interfaceStyle: viewModel.state.interfaceStyle)
        }
        // Remove annotations from `Document`
        if !deletedPdfAnnotations.isEmpty {
            for annotation in deletedPdfAnnotations {
                if annotation.flags.contains(.readOnly) {
                    annotation.flags.remove(.readOnly)
                }
                annotationPreviewController.async { [weak viewModel] controller in
                    guard let viewModel else { return }
                    controller.delete(for: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
                }
            }
            viewModel.state.document.remove(annotations: deletedPdfAnnotations, options: nil)
        }
        // Insert new annotations to `Document`
        if !insertedPdfAnnotations.isEmpty {
            viewModel.state.document.add(annotations: insertedPdfAnnotations, options: nil)

            annotationPreviewController.async { controller in
                for pdfAnnotation in insertedPdfAnnotations {
                    controller.store(for: pdfAnnotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, isDark: (viewModel.state.interfaceStyle == .dark))
                }
            }
        }
        observeDocument(in: viewModel)

        // Update state
        update(viewModel: viewModel) { state in
            // Update db annotations
            state.databaseAnnotations = objects.freeze()
            state.comments = comments
            state.changes = .annotations

            // Apply changed keys
            if state.snapshotKeys != nil {
                state.snapshotKeys = keys
                state.sortedKeys = filteredKeys(from: keys, term: state.searchTerm, filter: state.filter, state: state)
            } else {
                state.sortedKeys = keys
            }

            // Filter updated keys to include only keys that are actually available in `sortedKeys`. If filter/search is turned on and an item is edited so that it disappears from the filter/search,
            // `updatedKeys` will try to update it while the key will be deleted from data source at the same time.
            state.updatedAnnotationKeys = updatedKeys.filter({ state.sortedKeys.contains($0) })

            // Update selection
            if let key = selectKey {
                _select(key: key, didSelectInDocument: true, state: &state)
            } else if selectionDeleted {
                state.changes.insert(.selectionDeletion)
                _select(key: nil, didSelectInDocument: true, state: &state)
            }

            // Disable sidebar editing if there are no results
            if (state.snapshotKeys ?? state.sortedKeys).isEmpty {
                state.sidebarEditingEnabled = false
                state.changes.insert(.sidebarEditing)
            }
        }

        func canUpdate(key: PDFReaderState.AnnotationKey, item: RItem, at index: Int, viewModel: ViewModel<PDFReaderActionHandler>) -> Bool {
            // If there was a sync type change, always update item
            switch item.changeType {
            case .sync:
                // If sync happened and this item changed, always update item
                return true

            case .syncResponse:
                // This is a response to local changes being synced to backend, can be ignored
                return false
                
            case .user: break
            }

            // Check whether selected annotation's comment is being edited.
            guard viewModel.state.selectedAnnotationCommentActive && viewModel.state.selectedAnnotationKey == key else { return true }

            // Check whether the comment actually changed.
            let newComment = item.fields.filter(.key(FieldKeys.Item.Annotation.comment)).first?.value
            let oldComment = viewModel.state.databaseAnnotations[index].fields.filter(.key(FieldKeys.Item.Annotation.comment)).first?.value
            return oldComment == newComment
        }
    }

    private func update(pdfAnnotation: PSPDFKit.Annotation, with annotation: PDFDatabaseAnnotation, parentKey: String, libraryId: LibraryIdentifier, interfaceStyle: UIUserInterfaceStyle) {
        guard let boundingBoxConverter = delegate else { return }

        var changes: PdfAnnotationChanges = []

        if pdfAnnotation.baseColor != annotation.color {
            let hexColor = annotation.color

            let (color, alpha, blendMode) = AnnotationColorGenerator.color(from: UIColor(hex: hexColor), isHighlight: (annotation.type == .highlight), userInterfaceStyle: interfaceStyle)
            pdfAnnotation.color = color
            pdfAnnotation.alpha = alpha
            if let blendMode {
                pdfAnnotation.blendMode = blendMode
            }

            changes.insert(.color)
        }

        switch annotation.type {
        case .highlight, .underline:
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

        case .image, .freeText:
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

        annotationPreviewController.async { controller in
            controller.store(for: pdfAnnotation, parentKey: parentKey, libraryId: libraryId, isDark: (interfaceStyle == .dark))
        }

        NotificationCenter.default.post(
            name: NSNotification.Name.PSPDFAnnotationChanged,
            object: pdfAnnotation,
            userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: PdfAnnotationChanges.stringValues(from: changes)]
        )
    }
}

extension PSPDFKit.Annotation {
    var baseColor: String {
        return color.flatMap({ AnnotationsConfig.colorVariationMap[$0.hexString] }) ?? AnnotationsConfig.defaultActiveColor
    }
}
