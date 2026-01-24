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
    private var annotationProvider: PDFReaderAnnotationProvider?
    internal var appearance: Appearance = .light

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
        case .prepareDocumentProvider:
            prepareDocumentProvider(in: viewModel)

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

        case .parseAndCacheText(let key, let text, let font):
            updateTextCache(key: key, text: text, font: font, viewModel: viewModel, notifyListeners: false)

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

        case .updateAnnotationProperties(let key, let type, let color, let lineWidth, let fontSize, let pageLabel, let updateSubsequentLabels, let highlightText, let highlightFont):
            set(
                type: type,
                color: color,
                lineWidth: lineWidth,
                fontSize: fontSize,
                pageLabel: pageLabel,
                updateSubsequentLabels: updateSubsequentLabels,
                highlightText: highlightText,
                highlightFont: highlightFont,
                key: key,
                viewModel: viewModel
            )

        case .userInterfaceStyleChanged(let interfaceStyle):
            userInterfaceChanged(interfaceStyle: interfaceStyle, in: viewModel)

        case .updateAnnotationPreviews:
            storeAnnotationPreviewsIfNeeded(appearance: appearance, in: viewModel)

        case .setToolOptions(let hex, let size, let tool):
            setToolOptions(hex: hex, size: size, tool: tool, in: viewModel)

        case .createImage(let pageIndex, let origin):
            addImage(onPage: pageIndex, origin: origin, in: viewModel)

        case .createNote(let pageIndex, let origin):
            addNote(onPage: pageIndex, origin: origin, in: viewModel)

        case .createHighlight(let pageIndex, let rects):
            addHighlightOrUnderline(isHighlight: true, onPage: pageIndex, rects: rects, in: viewModel)

        case .createUnderline(let pageIndex, let rects):
            addHighlightOrUnderline(isHighlight: false, onPage: pageIndex, rects: rects, in: viewModel)

        case .setVisiblePage(let page, let userActionFromDocument, let fromThumbnailList):
            set(page: page, userActionFromDocument: userActionFromDocument, fromThumbnailList: fromThumbnailList, in: viewModel)

        case .submitPendingPage(let page):
            guard pageDebounceDisposeBag != nil else { return }
            pageDebounceDisposeBag = nil
            store(page: page, in: viewModel)

        case .export(let includeAnnotations):
            export(includeAnnotations: includeAnnotations, viewModel: viewModel)

        case .clearTmpData:
            // Clear page thumbnails
            pdfThumbnailController.deleteAll(forKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)

        case .setSettings(let settings):
            update(settings: settings, in: viewModel)

        case .changeIdleTimerDisabled(let disabled):
            changeIdleTimer(disabled: disabled)

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

    // MARK: - Appearance changes

    private func userInterfaceChanged(interfaceStyle: UIUserInterfaceStyle, in viewModel: ViewModel<PDFReaderActionHandler>) {
        appearance = .from(appearanceMode: viewModel.state.settings.appearanceMode, interfaceStyle: interfaceStyle)
        // Always update interface style so that we have current value when `automatic` is selected
        update(viewModel: viewModel) { state in
            state.interfaceStyle = interfaceStyle
        }
        guard viewModel.state.settings.appearanceMode == .automatic else { return }
        updateAnnotations(to: appearance, in: viewModel)
        update(viewModel: viewModel) { state in
            state.changes = .appearance
        }
    }

    private func appearanceChanged(appearanceMode: ReaderSettingsState.Appearance, in viewModel: ViewModel<PDFReaderActionHandler>) {
        appearance = .from(appearanceMode: appearanceMode, interfaceStyle: viewModel.state.interfaceStyle)
        updateAnnotations(to: appearance, in: viewModel)
        update(viewModel: viewModel) { state in
            state.changes = .appearance
        }
    }

    private func updateAnnotations(to appearance: Appearance, in viewModel: ViewModel<PDFReaderActionHandler>) {
        viewModel.state.previewCache.removeAllObjects()
        for (_, annotations) in viewModel.state.document.allAnnotations(of: AnnotationsConfig.supported) {
            for annotation in annotations {
                let baseColor = annotation.baseColor
                let (color, alpha, blendMode) = AnnotationColorGenerator.color(
                    from: UIColor(hex: baseColor),
                    type: annotation.type.annotationType,
                    appearance: appearance
                )
                annotation.color = color
                annotation.alpha = alpha
                if let blendMode {
                    annotation.blendMode = blendMode
                }
            }
        }
        storeAnnotationPreviewsIfNeeded(appearance: appearance, in: viewModel)
    }

    private func storeAnnotationPreviewsIfNeeded(appearance: Appearance, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let libraryId = viewModel.state.library.identifier
        // Load annotation previews if needed.
        for (_, annotations) in viewModel.state.document.allAnnotations(of: [.square, .ink, .freeText]) {
            for annotation in annotations {
                guard !annotationPreviewController.hasPreview(for: annotation.previewId, parentKey: viewModel.state.key, libraryId: libraryId, appearance: appearance) else { continue }
                annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: libraryId, appearance: appearance)
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

    private func changeIdleTimer(disabled: Bool) {
        if disabled {
            idleTimerController.startCustomIdleTimer()
        } else {
            idleTimerController.stopCustomIdleTimer()
        }
    }

    private func update(settings: PDFSettings, in viewModel: ViewModel<PDFReaderActionHandler>) {
        let appearanceDidChange = settings.appearanceMode != viewModel.state.settings.appearanceMode
        // Update local state
        update(viewModel: viewModel) { state in
            state.settings = settings
            state.changes = .settings
        }
        // Store new settings to defaults
        Defaults.shared.pdfSettings = settings
        guard appearanceDidChange else { return }
        appearanceChanged(appearanceMode: settings.appearanceMode, in: viewModel)
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
                appearance: .light,
                currentUserId: viewModel.state.userId,
                library: viewModel.state.library,
                displayName: viewModel.state.displayName,
                username: viewModel.state.username,
                documentPageCount: viewModel.state.document.pageCount,
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

    /// Filters annotations based on given term and filter parameters.
    /// - parameter term: Term to filter annotations.
    /// - parameter viewModel: ViewModel.
    private func filterAnnotations(with term: String?, filter: AnnotationsFilter?, in viewModel: ViewModel<PDFReaderActionHandler>) {
        if term == nil && filter == nil {
            guard let snapshot = viewModel.state.snapshotKeys else { return }

            for (_, annotations) in viewModel.state.document.allAnnotations(of: .all.subtracting([.link])) {
                for annotation in annotations {
                    guard annotation.isHidden else { continue }
                    annotation.isHidden = false
                    NotificationCenter.default.post(name: .PSPDFAnnotationChanged, object: annotation, userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: ["flags"]])
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

        for (_, annotations) in viewModel.state.document.allAnnotations(of: .all.subtracting([.link])) {
            for annotation in annotations {
                let isHidden = !filteredKeys.contains(where: { $0.key == (annotation.key ?? annotation.uuid) })
                guard isHidden != annotation.isHidden else { continue }
                annotation.isHidden = isHidden
                NotificationCenter.default.post(name: .PSPDFAnnotationChanged, object: annotation, userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: ["flags"]])
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
        let selectedDefaultColors: Set<String>
        let selectedExtraColors: Set<String>
        if let filter, !filter.colors.isEmpty {
            let defaultColors = Set(AnnotationsConfig.allColors)
            selectedDefaultColors = filter.colors.intersection(defaultColors)
            selectedExtraColors = filter.colors.subtracting(defaultColors)
        } else {
            selectedDefaultColors = []
            selectedExtraColors = []
        }
        return snapshot.filter({ key in
            guard let annotation = state.annotation(for: key) else { return false }
            let hasTerm = filterAnnotation(annotation, with: term, displayName: state.displayName, username: state.username)
            let hasFilter = (filter == nil) ? true : filterAnnotation(annotation, tags: filter?.tags ?? [], defaultColors: selectedDefaultColors, extraColors: selectedExtraColors)
            return hasTerm && hasFilter
        })

        func filterAnnotation(_ annotation: PDFAnnotation, with term: String?, displayName: String, username: String) -> Bool {
            guard let term else { return true }
            return annotation.key.lowercased() == term.lowercased() ||
                   annotation.author(displayName: displayName, username: username).localizedCaseInsensitiveContains(term) ||
                   annotation.comment.localizedCaseInsensitiveContains(term) ||
                   (annotation.text ?? "").localizedCaseInsensitiveContains(term) ||
                   annotation.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(term) })
        }

        func filterAnnotation(_ annotation: PDFAnnotation, tags: Set<String>, defaultColors: Set<String>, extraColors: Set<String>) -> Bool {
            let hasTag: Bool
            if tags.isEmpty {
                // Filter doesn't contain any tags.
                hasTag = true
            } else if annotation.isSyncable {
                // Database annotation filtered with tags.
                hasTag = annotation.tags.contains(where: { tags.contains($0.name) })
            } else {
                // Document annotations don't have tags, return immediately false.
                return false
            }

            let hasColor: Bool
            if defaultColors.isEmpty && extraColors.isEmpty {
                // Filter doesn't contain any colors.
                hasColor = true
            } else if !annotation.isSyncable {
                // Document annotation is filtered with both default and extra colors.
                hasColor = defaultColors.contains(annotation.color) || extraColors.contains(annotation.color)
            } else if !defaultColors.isEmpty {
                // Database annotation is filtered only with default colors.
                hasColor = defaultColors.contains(annotation.color)
            } else {
                // Database annotation is filtered with extra colors, return immediately false.
                return false
            }

            return hasTag && hasColor
        }
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
        let libraryId = viewModel.state.library.identifier

        var loadedKeys: Set<String> = []

        for key in keys {
            let nsKey = key as NSString
            guard viewModel.state.previewCache.object(forKey: nsKey) == nil else { continue }

            group.enter()
            annotationPreviewController.preview(for: key, parentKey: viewModel.state.key, libraryId: libraryId, appearance: appearance) { [weak viewModel] image in
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
        let color = AnnotationColorGenerator.color(from: activeColor, type: .image, appearance: appearance).color
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
        let color = AnnotationColorGenerator.color(from: activeColor, type: .note, appearance: appearance).color
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

    private func addHighlightOrUnderline(isHighlight: Bool, onPage pageIndex: PageIndex, rects: [CGRect], in viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let activeColor = viewModel.state.toolColors[tool(from: isHighlight ? .highlight : .underline)] else { return }
        let (color, alpha, blendMode) = AnnotationColorGenerator.color(from: activeColor, type: isHighlight ? .highlight : .underline, appearance: appearance)

        let annotation = isHighlight ? HighlightAnnotation() : UnderlineAnnotation()
        annotation.rects = rects
        annotation.boundingBox = AnnotationBoundingBoxCalculator.boundingBox(from: rects)
        annotation.alpha = alpha
        annotation.color = color
        if let blendMode {
            annotation.blendMode = blendMode
        }
        annotation.pageIndex = pageIndex

        viewModel.state.document.undoController.recordCommand(named: nil, adding: [annotation]) {
            viewModel.state.document.add(annotations: [annotation], options: nil)
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
        update(annotation: annotation, lineWidth: lineWidth, in: viewModel)
    }

    private func set(fontSize: CGFloat, key: String, viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: PDFReaderState.AnnotationKey(key: key, type: .database)) else { return }
        update(annotation: annotation, fontSize: fontSize, in: viewModel)
    }

    private func set(color: String, key: String, viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: PDFReaderState.AnnotationKey(key: key, type: .database)) else { return }
        update(annotation: annotation, color: (color, appearance), in: viewModel)
    }

    private func set(comment: NSAttributedString, key: String, viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: PDFReaderState.AnnotationKey(key: key, type: .database)) else { return }

        let htmlComment = htmlAttributedStringConverter.convert(attributedString: comment)

        update(viewModel: viewModel) { state in
            state.comments[key] = comment
        }

        update(annotation: annotation, contents: htmlComment, in: viewModel)
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
        type: AnnotationType,
        color: String,
        lineWidth: CGFloat,
        fontSize: CGFloat,
        pageLabel: String,
        updateSubsequentLabels: Bool,
        highlightText: NSAttributedString,
        highlightFont: UIFont,
        key: String,
        viewModel: ViewModel<PDFReaderActionHandler>
    ) {
        // `type`, `lineWidth`, `fontSize` and `color` is stored in `Document`, update document, which will trigger a notification wich will update the DB
        guard let annotation = viewModel.state.annotation(for: PDFReaderState.AnnotationKey(key: key, type: .database)) else { return }
        update(annotation: annotation, type: type, color: (color, appearance), lineWidth: lineWidth, fontSize: fontSize, in: viewModel)

        // Update remaining values directly
        let text = htmlAttributedStringConverter.convert(attributedString: highlightText)
        let values = [
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.pageLabel, baseKey: nil): pageLabel,
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.text, baseKey: nil): text
        ]
        let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let self, let viewModel else { return }
            if let error {
                DDLogError("PDFReaderActionHandler: can't update annotation \(key) - \(error)")

                update(viewModel: viewModel) { state in
                    state.error = .cantUpdateAnnotation
                }
                return
            }
            updateTextCache(key: key, text: text, font: highlightFont, viewModel: viewModel, notifyListeners: true)
        }
    }

    private func update(
        annotation: PDFAnnotation,
        type: AnnotationType? = nil,
        color: (String, Appearance)? = nil,
        lineWidth: CGFloat? = nil,
        fontSize: CGFloat? = nil,
        contents: String? = nil,
        in viewModel: ViewModel<PDFReaderActionHandler>
    ) {
        let document = viewModel.state.document
        guard let pdfAnnotation = document.annotations(at: PageIndex(annotation.page)).first(where: { $0.key == annotation.key }) else { return }
        // If type changed, we need to remove the old annotation and insert a new one with proper types.
        if let type, annotation.type != type {
            changeType()
        } else {
            // Otherwise just update existing annotation
            updateProperties()
        }

        func changeType() {
            let newAnnotation: PSPDFKit.Annotation
            switch (type, annotation.type) {
            case (.highlight, .underline):
                newAnnotation = HighlightAnnotation()

            case (.underline, .highlight):
                newAnnotation = UnderlineAnnotation()

            default:
                return
            }

            if let (color, appearance) = color, color != annotation.color {
                let (_color, alpha, blendMode) = AnnotationColorGenerator.color(from: UIColor(hex: color), type: type, appearance: appearance)
                newAnnotation.color = _color
                newAnnotation.alpha = alpha
                if let blendMode {
                    newAnnotation.blendMode = blendMode
                }
                newAnnotation.baseColor = color
            } else {
                newAnnotation.color = pdfAnnotation.color
                newAnnotation.alpha = pdfAnnotation.alpha
                newAnnotation.blendMode = pdfAnnotation.blendMode
                newAnnotation.baseColor = annotation.color
            }

            newAnnotation.rects = pdfAnnotation.rects
            newAnnotation.boundingBox = pdfAnnotation.boundingBox
            newAnnotation.pageIndex = pdfAnnotation.pageIndex
            newAnnotation.contents = contents ?? pdfAnnotation.contents
            newAnnotation.user = pdfAnnotation.user
            newAnnotation.name = pdfAnnotation.name

            document.undoController.recordCommand(named: nil, in: { recorder in
                recorder.record(removing: [pdfAnnotation]) {
                    document.remove(annotations: [pdfAnnotation])
                }
                recorder.record(adding: [newAnnotation]) {
                    document.add(annotations: [newAnnotation])
                }
            })
        }

        func updateProperties() {
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

                if changes.contains(.color), let (color, appearance) = color {
                    let (_color, alpha, blendMode) = AnnotationColorGenerator.color(from: UIColor(hex: color), type: annotation.type, appearance: appearance)
                    pdfAnnotation.color = _color
                    pdfAnnotation.alpha = alpha
                    if let blendMode {
                        pdfAnnotation.blendMode = blendMode
                    }
                    pdfAnnotation.baseColor = color
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
                // We use the displayName, but if this is empty we use the username, which is what would be presented anyway.
                // Since a username cannot be empty, we guarantee an non-empty annotation.user field.
                annotation.user = viewModel.state.displayName.isEmpty ? viewModel.state.username : viewModel.state.displayName
                annotation.customData = [
                    AnnotationsConfig.keyKey: KeyGenerator.newKey,
                    AnnotationsConfig.baseColorKey: annotation.baseColor
                ]
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
                // Remove may be superfluous, if those annotations are already removed by the undo.
                // Annotations are filtered, so only those that still need to are removed, to avoid an edge case where undocumented PSPDFKit expection
                // "The removed annotation does not belong to the current document" is thrown.
                let needRemove = toRemove.compactMap { document.annotation(on: Int($0.pageIndex), with: $0.key ?? $0.uuid) }
                if !needRemove.isEmpty {
                    document.remove(annotations: needRemove, options: [.suppressNotifications: true])
                }
                // Transformed annotations need to be added, before they are converted, otherwise their document property is nil.
                // Caution, if an annotation is added this way, with any empty string user, its user field will be converted to nil!
                document.add(annotations: finalAnnotations, options: [.suppressNotifications: true])
            }
        }

        guard !finalAnnotations.isEmpty else { return }
        let documentAnnotations: [PDFDocumentAnnotation] = finalAnnotations.compactMap { annotation in
            let documentAnnotation = AnnotationConverter.annotation(
                from: annotation,
                color: annotation.baseColor,
                username: viewModel.state.username,
                displayName: viewModel.state.displayName,
                defaultPageLabel: viewModel.state.defaultAnnotationPageLabel,
                boundingBoxConverter: boundingBoxConverter
            )
            guard let documentAnnotation else { return nil }
            // Only create preview for annotations that will be added in the database.
            annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, appearance: appearance)
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
                let (_, _, blendMode) = AnnotationColorGenerator.color(from: activeColor, type: annotation.type.annotationType, appearance: appearance)
                annotation.blendMode = blendMode ?? .normal

                // Either annotation is new (key not assigned) or the user used undo/redo and we check whether the annotation exists in DB
                guard annotation.key == nil || state.annotation(for: .init(key: annotation.key!, type: .database)) == nil else {
                    keptAsIs.append(annotation)
                    continue
                }
                var workingAnnotation = annotation

                if let transformedAnnotation = transformHighlightOrUnderlineRectsIfNeeded(annotation: annotation) {
                    DDLogInfo("PDFReaderActionHandler: did transform highlight/underline annotation rects")
                    toRemove.append(annotation)
                    toAdd.append(transformedAnnotation)
                    workingAnnotation = transformedAnnotation
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

            // TODO: Remove if issues are fixed in PSPDFKit
            /// Transforms highlight/underline annotation if needed.
            /// (a) Merges rects that are in the same text line.
            /// (b) Trims different line rects that overlap. This is needed only for highlight annotations.
            ///     PSPDFKit 26.5.0 fixed the highlight annotation rendering so that overlapping rects don't blend,
            ///     but rects values are exactly the same as before, so we still need to transform them for our needs.
            /// If not a higlight/underline annotation, or transformations are not needed, it returns nil.
            /// Issue appeared in PSPDFKit 13.5.0
            /// - parameter annotation: Annotation to be transformed if needed
            func transformHighlightOrUnderlineRectsIfNeeded(annotation: PSPDFKit.Annotation) -> PSPDFKit.Annotation? {
                guard annotation is HighlightAnnotation || annotation is UnderlineAnnotation, let rects = annotation.rects, rects.count > 1 else { return nil }
                let isHighlight = annotation is HighlightAnnotation
                var workingRects = rects
                workingRects = mergeHighlightOrUnderlineRectsIfNeeded(workingRects)
                if isHighlight {
                    workingRects = trimOverlappingHighlightRectsIfNeeded(workingRects)
                }
                guard workingRects != rects else { return nil }
                return copyHighlightOrUnderlineAnnotation(isHighlight: isHighlight, from: annotation, with: workingRects)

                func mergeHighlightOrUnderlineRectsIfNeeded(_ rects: [CGRect]) -> [CGRect] {
                    // Check if there are gaps for sequential highlight/underline rects on the same line, and if so transform the annotation to eliminate them.
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
                    return mergedRects
                }

                func trimOverlappingHighlightRectsIfNeeded(_ rects: [CGRect]) -> [CGRect] {
                    // Check if highlight rects for sequential lines overlap, and if so transform the annotation to trim the overlap equally between two rects.
                    var trimmedRects: [CGRect] = []
                    for currentRect in rects {
                        guard let previousRect = trimmedRects.last else {
                            trimmedRects.append(currentRect)
                            continue
                        }
                        let intersection = previousRect.intersection(currentRect)
                        guard intersection != .null else {
                            trimmedRects.append(currentRect)
                            continue
                        }
                        // Each rect is trimmed by half the intersection height, plus 0.25 to have a small gap between the lines.
                        let trim = (intersection.height / 2) + 0.25
                        let previousTrimmedRect = CGRect(x: previousRect.minX, y: previousRect.minY + trim, width: previousRect.width, height: previousRect.height - trim)
                        let currentTrimmedRect = CGRect(x: currentRect.minX, y: currentRect.minY, width: currentRect.width, height: currentRect.height - trim)
                        trimmedRects.removeLast()
                        trimmedRects.append(contentsOf: [previousTrimmedRect, currentTrimmedRect])
                    }
                    return trimmedRects
                }

                func copyHighlightOrUnderlineAnnotation(isHighlight: Bool, from annotation: PSPDFKit.Annotation, with rects: [CGRect]) -> Annotation {
                    let newAnnotation = isHighlight ? HighlightAnnotation() : UnderlineAnnotation()
                    newAnnotation.rects = rects
                    newAnnotation.boundingBox = AnnotationBoundingBoxCalculator.boundingBox(from: rects)
                    newAnnotation.alpha = annotation.alpha
                    newAnnotation.color = annotation.color
                    newAnnotation.blendMode = annotation.blendMode
                    newAnnotation.contents = annotation.contents
                    newAnnotation.pageIndex = annotation.pageIndex
                    return newAnnotation
                }
            }

            /// Splits annotation if it exceedes position limit. If it is within limit, it returns original annotation.
            /// - parameter annotation: Annotation to split
            /// - returns: Array with original annotation if limit was not exceeded. Otherwise array of new split annotations.
            func splitIfNeeded(annotation: PSPDFKit.Annotation) -> [PSPDFKit.Annotation] {
                if annotation is HighlightAnnotation || annotation is UnderlineAnnotation, let rects = annotation.rects, let splitRects = AnnotationSplitter.splitRectsIfNeeded(rects: rects) {
                    let isHighlight = annotation is HighlightAnnotation
                    return createHighlightOrUnderlineAnnotations(isHighlight: isHighlight, from: splitRects, original: annotation)
                }

                if let annotation = annotation as? InkAnnotation, let paths = annotation.lines, let splitPaths = AnnotationSplitter.splitPathsIfNeeded(paths: paths) {
                    return createInkAnnotations(from: splitPaths, original: annotation)
                }

                return [annotation]

                func createHighlightOrUnderlineAnnotations(isHighlight: Bool, from splitRects: [[CGRect]], original: Annotation) -> [Annotation] {
                    guard splitRects.count > 1 else { return [original] }
                    return splitRects.map { rects -> Annotation in
                        let new = isHighlight ? HighlightAnnotation() : UnderlineAnnotation()
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

                func createInkAnnotations(from splitPaths: [[[DrawingPoint]]], original: InkAnnotation) -> [InkAnnotation] {
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

        annotationPreviewController.store(for: annotation, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier, appearance: appearance)

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
        } else if let textAnnotation = annotation as? PSPDFKit.FreeTextAnnotation {
            var editFontSize = hasChanges([.fontSize])
            // FreeTextAnnotation has only `boundingBox` change, not paired with paths or rects.
            if hasChanges([.boundingBox]), let rects = AnnotationConverter.rects(from: annotation) {
                requests.append(EditAnnotationRectsDbRequest(key: key, libraryId: viewModel.state.library.identifier, rects: rects, boundingBoxConverter: boundingBoxConverter))
                // Font size may change due to the user resizing the bounding box, but it is not communicated properly in the PSPDFKit notification.
                // Therefore, we always edit font size in this case, even if it didn't change.
                editFontSize = true
            }

            if hasChanges([.rotation]) {
                requests.append(EditAnnotationRotationDbRequest(key: key, libraryId: viewModel.state.library.identifier, rotation: textAnnotation.rotation))
            }

            if editFontSize {
                let roundedFontSize = AnnotationsConfig.roundFreeTextAnnotationFontSize(textAnnotation.fontSize)
                requests.append(EditAnnotationFontSizeDbRequest(key: key, libraryId: viewModel.state.library.identifier, size: roundedFontSize))
            }
        } else if hasChanges([.boundingBox, .rects]), let rects = AnnotationConverter.rects(from: annotation) {
            requests.append(EditAnnotationRectsDbRequest(key: key, libraryId: viewModel.state.library.identifier, rects: rects, boundingBoxConverter: boundingBoxConverter))
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

    private func prepareDocumentProvider(in viewModel: ViewModel<PDFReaderActionHandler>) {
        appearance = .from(appearanceMode: viewModel.state.settings.appearanceMode, interfaceStyle: viewModel.state.interfaceStyle)
        viewModel.state.document.didCreateDocumentProviderBlock = { [weak self] documentProvider in
            guard let self, let fileAnnotationProvider = documentProvider.annotationManager.fileAnnotationProvider else { return }
            let provider = PDFReaderAnnotationProvider(
                documentProvider: documentProvider,
                fileAnnotationProvider: fileAnnotationProvider,
                dbStorage: dbStorage,
                displayName: viewModel.state.displayName,
                username: viewModel.state.username
            )
            provider.pdfReaderAnnotationProviderDelegate = self
            annotationProvider = provider
            documentProvider.annotationManager.annotationProviders = [provider]
        }
    }

    /// Loads annotations from DB, converts them to Zotero annotations and adds matching PSPDFKit annotations to document.
    private func loadDocumentData(boundingBoxConverter: AnnotationBoundingBoxConverter, in viewModel: ViewModel<PDFReaderActionHandler>) {
        do {
            let pageCount = viewModel.state.document.pageCount
            guard let boundingBoxConverter = delegate, pageCount > 0 else { throw PDFReaderState.Error.documentEmpty }

            let startTime = CFAbsoluteTimeGetCurrent()

            let key = viewModel.state.key
            let (item, liveAnnotations, storedPage) = try loadItemAnnotationsAndPage(for: key, libraryId: viewModel.state.library.identifier)

            let (documentMD5, _, changed) = checkWhetherMd5Changed(forItem: item, andUpdateViewModel: viewModel, handler: self)
            if changed == true {
                DDLogWarn("PDFReaderActionHandler: MD5 has changed, before PDF was loaded")
                return
            }

            let (library, libraryToken) = try viewModel.state.library.identifier.observe(in: dbStorage, changes: { [weak self, weak viewModel] library in
                guard let self, let viewModel else { return }
                observe(library: library, viewModel: viewModel, handler: self)
            })
            let itemToken = observe(item: item, viewModel: viewModel)
            let token = observe(items: liveAnnotations, viewModel: viewModel)
            let databaseAnnotations = liveAnnotations.freeze()

            let loadDocumentAnnotationsStartTime = CFAbsoluteTimeGetCurrent()
            if let annotationProvider {
                annotationProvider.createCacheIfNeeded(
                    attachmentKey: key,
                    libraryId: library.identifier,
                    documentMD5: documentMD5,
                    pageCount: Int(viewModel.state.document.pageCount),
                    boundingBoxConverter: boundingBoxConverter
                )
            } else {
                DDLogWarn("PDFReaderActionHandler: annotation provider not initialized before loading document data")
            }

            let allDocumentAnnotations = viewModel.state.document.allAnnotations(of: .all).values.flatMap({ $0 })
            annotationPreviewController.store(annotations: allDocumentAnnotations, parentKey: key, libraryId: library.identifier, appearance: appearance)
            let documentAnnotations = annotationProvider?.results
            let documentAnnotationKeys = annotationProvider?.keys ?? []
            let documentAnnotationUniqueBaseColors = annotationProvider?.uniqueBaseColors ?? []

            let annotationPages = readAnnotationPages(attachmentKey: key, libraryId: viewModel.state.library.identifier)

            let convertDbAnnotationsStartTime = CFAbsoluteTimeGetCurrent()
            let dbToPdfAnnotations = AnnotationConverter.annotations(
                from: databaseAnnotations,
                appearance: appearance,
                currentUserId: viewModel.state.userId,
                library: library,
                displayName: viewModel.state.displayName,
                username: viewModel.state.username,
                documentPageCount: viewModel.state.document.pageCount,
                boundingBoxConverter: boundingBoxConverter
            )

            let sortStartTime = CFAbsoluteTimeGetCurrent()
            let sortedKeys = createSortedKeys(fromDatabaseAnnotations: databaseAnnotations, documentAnnotationKeys: documentAnnotationKeys)
            let defaultAnnotationPageLabelStartTime = CFAbsoluteTimeGetCurrent()
            let defaultAnnotationPageLabel = defaultAnnotationPageLabel(fromDatabaseAnnotations: databaseAnnotations)
            let (page, selectedData) = preselectedData(databaseAnnotations: databaseAnnotations, storedPage: storedPage, boundingBoxConverter: boundingBoxConverter, in: viewModel)

            let updateDocumentStartTime = CFAbsoluteTimeGetCurrent()
            viewModel.state.document.add(annotations: dbToPdfAnnotations, options: [.suppressNotifications: true])
            let endTime = CFAbsoluteTimeGetCurrent()

            annotationPreviewController.store(annotations: dbToPdfAnnotations, parentKey: key, libraryId: library.identifier, appearance: appearance)

            update(viewModel: viewModel) { state in
                state.library = library
                state.libraryToken = libraryToken
                state.databaseAnnotations = databaseAnnotations
                state.defaultAnnotationPageLabel = defaultAnnotationPageLabel
                state.documentAnnotations = documentAnnotations
                state.documentAnnotationKeys = documentAnnotationKeys
                state.documentAnnotationUniqueBaseColors = documentAnnotationUniqueBaseColors
                state.sortedKeys = sortedKeys
                state.annotationPages = annotationPages
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

            DDLogInfo("PDFReaderActionHandler: loaded PDF with \(viewModel.state.document.pageCount) pages, \(documentAnnotationKeys.count) document annotations, \(dbToPdfAnnotations.count) zotero annotations")
            var timeLog = "PDFReaderActionHandler: total time \(endTime - startTime)"
            timeLog += ", initial loading: \(loadDocumentAnnotationsStartTime - startTime)"
            timeLog += ", load document annotations: \(convertDbAnnotationsStartTime - loadDocumentAnnotationsStartTime)"
            timeLog += ", load zotero annotations: \(sortStartTime - convertDbAnnotationsStartTime)"
            timeLog += ", sort keys: \(defaultAnnotationPageLabelStartTime - sortStartTime)"
            timeLog += ", default annotation page label: \(updateDocumentStartTime - defaultAnnotationPageLabelStartTime)"
            timeLog += ", update document: \(endTime - updateDocumentStartTime)"
            DDLogInfo(DDLogMessageFormat(stringLiteral: timeLog))

            observeDocument(in: viewModel)
        } catch let error {
            DDLogError("PDFReaderActionHandler: failed to load PDF: \(error)")
            update(viewModel: viewModel) { state in
                state.error = (error as? PDFReaderState.Error) ?? .unknownLoading
            }
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

        func observe(items: Results<RItem>, viewModel: ViewModel<PDFReaderActionHandler>) -> NotificationToken {
            return items.observe { [weak self, weak viewModel] change in
                guard let self, let viewModel else { return }
                switch change {
                case .update(let objects, let deletions, let insertions, let modifications):
                    update(objects: objects, deletions: deletions, insertions: insertions, modifications: modifications, viewModel: viewModel)

                case .error, .initial:
                    break
                }
            }
        }

        func observe(item: RItem, viewModel: ViewModel<PDFReaderActionHandler>) -> NotificationToken {
            return item.observe(keyPaths: ["fields"], on: .main) { [weak self, weak viewModel] (change: ObjectChange<RItem>) in
                guard let self, let viewModel else { return }
                switch change {
                case .change(let item, _):
                    checkWhetherMd5Changed(forItem: item, andUpdateViewModel: viewModel, handler: self)

                case .deleted, .error:
                    break
                }
            }
        }

        @discardableResult
        func checkWhetherMd5Changed(
            forItem item: RItem,
            andUpdateViewModel viewModel: ViewModel<PDFReaderActionHandler>,
            handler: PDFReaderActionHandler
        ) -> (documentMD5: String?, backendMD5: String?, changed: Bool?) {
            var documentMD5: String?
            if let documentURL = viewModel.state.document.fileURL {
                documentMD5 = cachedMD5(from: documentURL, using: fileStorage.fileManager)
            }
            let backendMD5 = !item.backendMd5.isEmpty ? item.backendMd5 : nil
            guard let documentMD5 else { return (documentMD5: nil, backendMD5: backendMD5, changed: nil) }
            guard backendMD5 != documentMD5 else { return (documentMD5: documentMD5, backendMD5: backendMD5, changed: false) }
            deleteDocumentAnnotationsCache(for: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            annotationPreviewController.deleteAll(parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            handler.update(viewModel: viewModel) { state in
                state.changes = .md5
            }
            return (documentMD5: documentMD5, backendMD5: backendMD5, changed: true)
        }

        func loadItemAnnotationsAndPage(for key: String, libraryId: LibraryIdentifier) throws -> (RItem, Results<RItem>, Int) {
            var results: Results<RItem>!
            var pageStr = "0"
            var item: RItem!

            try dbStorage.perform(on: .main, with: { coordinator in
                item = try coordinator.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))
                pageStr = try coordinator.perform(request: ReadDocumentDataDbRequest(attachmentKey: key, libraryId: libraryId, defaultPageValue: "0"))
                results = try coordinator.perform(request: ReadAnnotationsDbRequest(attachmentKey: key, libraryId: libraryId, page: nil))
            })

            guard let page = Int(pageStr) else {
                throw PDFReaderState.Error.pageNotInt
            }

            return (item, results, page)
        }
    }

    private func readAnnotationPages(attachmentKey: String, libraryId: LibraryIdentifier) -> IndexSet {
        do {
            return try dbStorage.perform(request: ReadAnnotationPagesDbRequest(attachmentKey: attachmentKey, libraryId: libraryId), on: .main)
        } catch {
            DDLogError("PDFReaderActionHandler: failed to read annotation pages - \(error)")
            return IndexSet()
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

    private func createSortedKeys(fromDatabaseAnnotations databaseAnnotations: Results<RItem>, documentAnnotationKeys: [PDFReaderState.AnnotationKey]) -> [PDFReaderState.AnnotationKey] {
        var keys: [PDFReaderState.AnnotationKey] = []
        for item in databaseAnnotations {
            guard let annotation = PDFDatabaseAnnotation(item: item), isValid(databaseAnnotation: annotation) else { continue }
            keys.append(PDFReaderState.AnnotationKey(key: item.key, sortIndex: item.annotationSortIndex, type: .database))
        }
        keys.append(contentsOf: documentAnnotationKeys)
//        keys.sort(by: { $0.sortIndex < $1.sortIndex })
        keys.sort(by: { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }
            if lhs.key != rhs.key {
                return lhs.key < rhs.key
            }
            return lhs.type == .database && rhs.type == .document
        })
        return keys
    }

    private func isValid(databaseAnnotation: PDFDatabaseAnnotation) -> Bool {
        guard databaseAnnotation._page != nil else { return false }

        switch databaseAnnotation.type {
        case .ink:
            if databaseAnnotation.item.paths.isEmpty {
                DDLogInfo("PDFReaderActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing paths")
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
                // Since free text annotations are created in AnnotationConverter using `setBoundingBox(annotation.boundingBox(boundingBoxConverter: boundingBoxConverter), transformSize: true)`
                // it's ok even if they are missing `fontSize`, so we just log it and continue validation.
                DDLogInfo("PDFReaderActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing fontSize")
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

    private func defaultAnnotationPageLabel(fromDatabaseAnnotations databaseAnnotations: Results<RItem>) -> PDFReaderState.DefaultAnnotationPageLabel {
        var uniquePageLabelsCountByPage: [Int: [String: Int]] = [:]
        for item in databaseAnnotations {
            guard let annotation = PDFDatabaseAnnotation(item: item), let page = annotation._page, let pageLabel = annotation._pageLabel, !pageLabel.isEmpty, pageLabel != "-" else { continue }
            var uniquePageLabelsCount = uniquePageLabelsCountByPage[page, default: [:]]
            uniquePageLabelsCount[pageLabel, default: 0] += 1
            uniquePageLabelsCountByPage[page] = uniquePageLabelsCount
        }
        var defaultPageLabelByPage: [Int: String] = [:]
        for (page, uniquePageLabelsCount) in uniquePageLabelsCountByPage {
            if let maxCount = uniquePageLabelsCount.values.max(), let defaultPageLabel = uniquePageLabelsCount.filter({ $0.value == maxCount }).keys.sorted().first {
                defaultPageLabelByPage[page] = defaultPageLabel
            }
        }
        let uniquePageOffsets = Set(defaultPageLabelByPage.map({ (page, pageLabel) in Int(pageLabel).flatMap({ $0 - page }) }))
        if uniquePageOffsets.count == 1, let uniquePageOffset = uniquePageOffsets.first, let commonPageOffset = uniquePageOffset {
            return .commonPageOffset(offset: commonPageOffset)
        }
        if !defaultPageLabelByPage.isEmpty {
            return .labelPerPage(labelsByPage: defaultPageLabelByPage)
        }
        return .commonPageOffset(offset: 1)
    }

    // MARK: - Translate sync (db) changes to PDF document

    private func update(objects: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int], viewModel: ViewModel<PDFReaderActionHandler>) {
        guard let boundingBoxConverter = delegate else { return }

        DDLogInfo("PDFReaderActionHandler: database annotation changed")

        let databaseAnnotations = viewModel.state.databaseAnnotations!
        var texts = viewModel.state.texts
        var comments = viewModel.state.comments
        var selectKey: PDFReaderState.AnnotationKey?
        var selectionDeleted = false
        // Update database keys based on realm notification
        var updatedKeys: [PDFReaderState.AnnotationKey] = []
        // Collect modified, deleted and inserted annotations to update the `Document`
        var updatedPdfAnnotations: [(PSPDFKit.Annotation, PDFDatabaseAnnotation)] = []
        var deletedPdfAnnotations: [PSPDFKit.Annotation] = []
        var insertedPdfAnnotations: [PSPDFKit.Annotation] = []
        var shouldRecomputeDefaultAnnotationPageLabel = false

        // Check which annotations changed and update `Document`
        // Modifications are indexed by the previously observed items
        for index in modifications {
            if index >= databaseAnnotations.count {
                DDLogWarn("PDFReaderActionHandler: tried modifying index out of bounds! keys.count=\(databaseAnnotations.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)")
                continue
            }

            let key = PDFReaderState.AnnotationKey(key: databaseAnnotations[index].key, type: .database)
            guard let item = objects.filter(.key(key.key)).first, let annotation = PDFDatabaseAnnotation(item: item) else { continue }

            if canUpdate(key: key, item: item, at: index, viewModel: viewModel) {
                DDLogInfo("PDFReaderActionHandler: update key \(key)")
                updatedKeys.append(key)

                if item.changeType == .sync {
                    // Update text and comment if it's remote sync change
                    DDLogInfo("PDFReaderActionHandler: update text and comment")

                    let textCacheTuple: (String, [UIFont: NSAttributedString])?
                    let comment: NSAttributedString?
                    // Annotation text
                    switch annotation.type {
                    case .highlight, .underline:
                        textCacheTuple = annotation.text.flatMap({
                            ($0, [viewModel.state.textFont: htmlAttributedStringConverter.convert(text: $0, baseAttributes: [.font: viewModel.state.textFont])])
                        })

                    case .note, .image, .ink, .freeText:
                        textCacheTuple = nil
                    }
                    texts[key.key] = textCacheTuple
                    // Annotation comment
                    switch annotation.type {
                    case .note, .highlight, .image, .underline:
                        comment = htmlAttributedStringConverter.convert(text: annotation.comment, baseAttributes: [.font: viewModel.state.commentFont])

                    case .ink, .freeText:
                        comment = nil
                    }
                    comments[key.key] = comment
                }
            }

            let newPageLabel = item.fields.filter(.key(FieldKeys.Item.Annotation.pageLabel)).first?.value
            let oldPageaLabel = viewModel.state.databaseAnnotations[index].fields.filter(.key(FieldKeys.Item.Annotation.pageLabel)).first?.value
            if newPageLabel != oldPageaLabel {
                shouldRecomputeDefaultAnnotationPageLabel = true
            }

            guard item.changeType == .sync, let pdfAnnotation = viewModel.state.document.annotations(at: PageIndex(annotation.page)).first(where: { $0.key == key.key }) else { continue }

            DDLogInfo("PDFReaderActionHandler: update PDF annotation")
            updatedPdfAnnotations.append((pdfAnnotation, annotation))
        }

        var shouldCancelUpdate = false

        // Find `Document` annotations to be removed from document
        // Modifications are indexed by the previously observed items
        for index in deletions.reversed() {
            if index >= databaseAnnotations.count {
                DDLogWarn("PDFReaderActionHandler: tried removing index out of bounds! keys.count=\(databaseAnnotations.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)")
                shouldCancelUpdate = true
                break
            }

            let key = PDFReaderState.AnnotationKey(key: databaseAnnotations[index].key, type: .database)
            DDLogInfo("PDFReaderActionHandler: delete key \(key)")

            if viewModel.state.selectedAnnotationKey == key {
                DDLogInfo("PDFReaderActionHandler: deleted selected annotation")
                selectionDeleted = true
            }

            shouldRecomputeDefaultAnnotationPageLabel = true
            
            guard let oldAnnotation = PDFDatabaseAnnotation(item: databaseAnnotations[index]),
                  let pdfAnnotation = viewModel.state.document.annotations(at: PageIndex(oldAnnotation.page)).first(where: { $0.key == oldAnnotation.key })
            else { continue }
            DDLogInfo("PDFReaderActionHandler: delete PDF annotation")
            deletedPdfAnnotations.append(pdfAnnotation)
        }

        if shouldCancelUpdate {
            return
        }

        // Create `PSPDFKit.Annotation`s which need to be added to the `Document`
        // Keys for insertions are indexed by the currently observed items
        for index in insertions {
            if index >= objects.count {
                DDLogWarn("PDFReaderActionHandler: tried inserting index out of bounds! keys.count=\(objects.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)")
                shouldCancelUpdate = true
                break
            }

            let item = objects[index]
            DDLogInfo("PDFReaderActionHandler: insert key \(item.key)")

            guard let annotation = PDFDatabaseAnnotation(item: item) else {
                DDLogWarn("PDFReaderActionHandler: tried inserting unsupported annotation (\(item.annotationType))! keys.count=\(objects.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)")
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
                    appearance: appearance,
                    currentUserId: viewModel.state.userId,
                    library: viewModel.state.library,
                    displayName: viewModel.state.displayName,
                    username: viewModel.state.username,
                    boundingBoxConverter: boundingBoxConverter
                )
                insertedPdfAnnotations.append(pdfAnnotation)
                if annotation.pageLabel != viewModel.state.defaultAnnotationPageLabel.label(for: annotation.page) {
                    shouldRecomputeDefaultAnnotationPageLabel = true
                }

                DDLogInfo("PDFReaderActionHandler: insert PDF annotation")
            }
        }

        if shouldCancelUpdate {
            return
        }

        let annotationPages = readAnnotationPages(attachmentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
        // Create new sorted keys by re-adding document keys
        let sortedKeys = createSortedKeys(fromDatabaseAnnotations: objects, documentAnnotationKeys: viewModel.state.documentAnnotationKeys)

        let defaultAnnotationPageLabel = shouldRecomputeDefaultAnnotationPageLabel ? defaultAnnotationPageLabel(fromDatabaseAnnotations: objects) : nil

        // Temporarily disable PDF notifications, because these changes were made by sync and they don't need to be translated back to the database
        pdfDisposeBag = DisposeBag()
        // Update annotations in `Document`
        for (pdfAnnotation, annotation) in updatedPdfAnnotations {
            update(
                pdfAnnotation: pdfAnnotation,
                with: annotation,
                parentKey: viewModel.state.key,
                libraryId: viewModel.state.library.identifier,
                appearance: appearance
            )
        }
        // Remove annotations from `Document`
        if !deletedPdfAnnotations.isEmpty {
            for annotation in deletedPdfAnnotations {
                if annotation.flags.contains(.readOnly) {
                    annotation.flags.remove(.readOnly)
                }
            }
            annotationPreviewController.delete(annotations: deletedPdfAnnotations, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            viewModel.state.document.remove(annotations: deletedPdfAnnotations, options: nil)
        }
        // Insert new annotations to `Document`
        if !insertedPdfAnnotations.isEmpty {
            viewModel.state.document.add(annotations: insertedPdfAnnotations, options: nil)
            annotationPreviewController.store(
                annotations: insertedPdfAnnotations,
                parentKey: viewModel.state.key,
                libraryId: viewModel.state.library.identifier,
                appearance: appearance
            )
        }
        observeDocument(in: viewModel)

        // Update state
        update(viewModel: viewModel) { state in
            // Update db annotations
            state.databaseAnnotations = objects.freeze()
            if let defaultAnnotationPageLabel {
                state.defaultAnnotationPageLabel = defaultAnnotationPageLabel
            }
            state.texts = texts
            state.comments = comments
            state.changes = .annotations
            state.annotationPages = annotationPages

            // Apply changed keys
            if state.snapshotKeys != nil {
                state.snapshotKeys = sortedKeys
                state.sortedKeys = filteredKeys(from: sortedKeys, term: state.searchTerm, filter: state.filter, state: state)
            } else {
                state.sortedKeys = sortedKeys
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

    private func update(pdfAnnotation: PSPDFKit.Annotation, with annotation: PDFDatabaseAnnotation, parentKey: String, libraryId: LibraryIdentifier, appearance: Appearance) {
        guard let boundingBoxConverter = delegate else { return }

        var changes: PdfAnnotationChanges = []

        if pdfAnnotation.baseColor != annotation.color {
            let hexColor = annotation.color

            let (color, alpha, blendMode) = AnnotationColorGenerator.color(from: UIColor(hex: hexColor), type: annotation.type, appearance: appearance)
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

        annotationPreviewController.store(for: pdfAnnotation, parentKey: parentKey, libraryId: libraryId, appearance: appearance)

        NotificationCenter.default.post(
            name: NSNotification.Name.PSPDFAnnotationChanged,
            object: pdfAnnotation,
            userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: PdfAnnotationChanges.stringValues(from: changes)]
        )
    }

    private func updateTextCache(key: String, text: String, font: UIFont, viewModel: ViewModel<PDFReaderActionHandler>, notifyListeners: Bool) {
        update(viewModel: viewModel, notifyListeners: notifyListeners) { state in
            var (cachedText, attributedTextByFont) = state.texts[key, default: (text, [:])]
            if cachedText != text {
                attributedTextByFont = [:]
            }
            attributedTextByFont[font] = htmlAttributedStringConverter.convert(text: text, baseAttributes: [.font: font])
            state.texts[key] = (text, attributedTextByFont)
        }
    }
}

extension PDFReaderActionHandler: PDFReaderAnnotationProviderDelegate {
    func deleteDocumentAnnotationsCache(for key: String, libraryId: LibraryIdentifier) {
        let request = DeleteDocumentAnnotationsCacheDbRequest(attachmentKey: key, libraryId: libraryId)
        perform(request: request) { error in
            guard let error else { return }
            DDLogError("PDFReaderActionHandler: failed to delete document annotation cache - \(error)")
        }
    }
}
