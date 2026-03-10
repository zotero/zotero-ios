//
//  PDFReaderAnnotationProvider.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 06/02/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import PSPDFKit
import RealmSwift

protocol PDFReaderAnnotationProviderDelegate: AnyObject {
    var displayName: String { get }
}

final class PDFReaderAnnotationProvider: PDFContainerAnnotationProvider {
    private enum CacheStatus {
        case unresolved
        case loading
        case loaded(results: Results<RDocumentAnnotation>)
        case failed
    }

    private struct FilterContext: Hashable {
        let term: String?
        let colors: Set<String>
        let tags: Set<String>

        static let empty: Self = .init(term: nil, colors: [], tags: [])

        var filter: AnnotationsFilter {
            .init(colors: colors, tags: tags)
        }

        var isEmpty: Bool {
            return self == .empty
        }

        init(term: String?, colors: Set<String>, tags: Set<String>) {
            self.term = term
            self.colors = colors
            self.tags = tags
        }

        init(term: String?, filter: AnnotationsFilter?) {
            self.init(term: term, colors: filter?.colors ?? [], tags: filter?.tags ?? [])
        }
    }

    private let fileAnnotationProvider: PDFFileAnnotationProvider
    private unowned let dbStorage: DbStorage
    private let dbQueue: DispatchQueue
    private let dbQueueSpecificKey: DispatchSpecificKey<Void>
    private let attachmentKey: String
    private let libraryId: LibraryIdentifier
    private let userId: Int
    private let username: String
    private let documentPageCount: PageCount
    private var metadataEditable: Bool
    private unowned let boundingBoxConverter: AnnotationBoundingBoxConverter
    var displayName: String {
        pdfReaderAnnotationProviderDelegate?.displayName ?? ""
    }

    var results: Results<RDocumentAnnotation>? {
        switch cacheStatus {
        case .unresolved, .loading, .failed:
            return nil

        case .loaded(let results):
            return results
        }
    }
    public private(set) var keys: [PDFReaderAnnotationKey] = []
    public private(set) var uniqueBaseColors: [String] = []
    public weak var pdfReaderAnnotationProviderDelegate: PDFReaderAnnotationProviderDelegate?

    private var cacheStatus: CacheStatus = .unresolved
    private var loadedFilePageIndices = Set<PageIndex>()
    private var loadedDocumentCachePageIndices = Set<PageIndex>()
    private var loadedDatabaseCachePageIndices = Set<PageIndex>()
    private var loadedFileNonLinkAnnotationsByPage: [PageIndex: [Annotation]] = [:]
    private var loadedAnnotationsByPageByKey: [PageIndex: [String: Annotation]] = [:]
    private var loadedAnnotationsByKey: [String: Annotation] = [:]
    private var visiblePageIndex: PageIndex?
    private var currentFilterContext: FilterContext = .empty
    private var currentAppearance: Appearance

    override var allAnnotations: [Annotation] {
        return performRead { super.allAnnotations }
    }

    init(
        documentProvider: PDFDocumentProvider,
        fileAnnotationProvider: PDFFileAnnotationProvider,
        dbStorage: DbStorage,
        dbQueue: DispatchQueue,
        attachmentKey: String,
        libraryId: LibraryIdentifier,
        userId: Int,
        username: String,
        documentPageCount: PageCount,
        metadataEditable: Bool,
        boundingBoxConverter: AnnotationBoundingBoxConverter,
        appearance: Appearance
    ) {
        self.fileAnnotationProvider = fileAnnotationProvider
        self.dbStorage = dbStorage
        self.dbQueue = dbQueue
        dbQueueSpecificKey = DispatchSpecificKey()
        self.attachmentKey = attachmentKey
        self.libraryId = libraryId
        self.userId = userId
        self.username = username
        self.documentPageCount = documentPageCount
        self.metadataEditable = metadataEditable
        self.boundingBoxConverter = boundingBoxConverter
        currentAppearance = appearance
        dbQueue.setSpecific(key: dbQueueSpecificKey, value: ())
        super.init(documentProvider: documentProvider)
    }

    // MARK: - AnnotationProvider

    private var providerDelegateBackingStore: AnnotationProviderChangeNotifier?
    override var providerDelegate: AnnotationProviderChangeNotifier? {
        get {
            return providerDelegateBackingStore
        }
        set {
            guard newValue?.isEqual(providerDelegate) == false else { return }
            providerDelegateBackingStore = newValue
        }
    }

    override var allowAnnotationZIndexMoves: Bool {
        return false
    }

    override var shouldSaveAnnotations: Bool {
        return false
    }

    override func saveAnnotations(options: [String: Any]? = nil) throws {
        return
    }

    override func hasLoadedAnnotationsForPage(at pageIndex: PageIndex) -> Bool {
        return performRead {
            return loadedFilePageIndices.contains(pageIndex) && loadedDocumentCachePageIndices.contains(pageIndex) && loadedDatabaseCachePageIndices.contains(pageIndex)
        }
    }

    override func annotationsForPage(at pageIndex: PageIndex) -> [Annotation]? {
        let filePageIsLoaded = performRead { loadedFilePageIndices.contains(pageIndex) }
        let documentCachePageIsLoaded = performRead { loadedDocumentCachePageIndices.contains(pageIndex) }
        let databaseCachePageIsLoaded = performRead { loadedDatabaseCachePageIndices.contains(pageIndex) }
        if filePageIsLoaded && documentCachePageIsLoaded && databaseCachePageIsLoaded {
            return performRead {
                let filePageAnnotations = fileAnnotationProvider.annotationsForPage(at: pageIndex)
                let cachePageAnnotations = super.annotationsForPage(at: pageIndex)

                if filePageAnnotations == nil, cachePageAnnotations == nil {
                    return nil
                }
                return (filePageAnnotations ?? []) + (cachePageAnnotations ?? [])
            }
        }
        return performWriteAndWait {
            // Because we had to leave the critical region from reading to writing, another thread could have raced here before us.
            // In order to prevent caching the same annotations multiple times, we check again our indices first.

            // First the index for the document annotations that are read from the file (unsupported types which include links).
            let filePageAnnotations = fileAnnotationsForPage(at: pageIndex)

            // Then the index for the document annotations that are read from the cache.
            loadDocumentCacheIfNeededForPage(at: pageIndex)

            // Finally the index for the database annotations that are read from the cache.
            loadDatabaseCacheIfNeededForPage(at: pageIndex)

            // Annotations are fetched from `super`, apart from cached document and database annotations, as more may have been added before it was accessed here.
            let cachePageAnnotations = super.annotationsForPage(at: pageIndex)

            // Since this is the first time the annotations are loaded, apply current filter, if not empty.
            if !currentFilterContext.isEmpty {
                applyCurrentFilterForPage(at: pageIndex, notify: true)
            }
            // TODO: Check if current apperance needs to be applied to the file page annotations.

            if filePageAnnotations == nil, cachePageAnnotations == nil {
                return nil
            }
            return (filePageAnnotations ?? []) + (cachePageAnnotations ?? [])
        }

        func fileAnnotationsForPage(at pageIndex: PageIndex) -> [Annotation]? {
            let annotations: [Annotation]?
            if loadedFilePageIndices.contains(pageIndex) {
                annotations = fileAnnotationProvider.annotationsForPage(at: pageIndex)
            } else {
                (_, annotations) = loadFilePage(pageIndex: pageIndex)
            }
            return annotations
        }

        func loadDocumentCacheIfNeededForPage(at pageIndex: PageIndex) {
            guard !loadedDocumentCachePageIndices.contains(pageIndex) else { return }
            switch cacheStatus {
            case .loaded(let results):
                // Document annotations database cache is loaded, load annotations to provider cache.
                let documentAnnotations = Array(results.filter("page = %d", Int(pageIndex)))
                if !documentAnnotations.isEmpty {
                    // There are document annotations for this page in the database cache, add them to provider cache.
                    var annotationsToAdd: [Annotation] = []
                    for documentAnnotation in documentAnnotations {
                        guard let annotation = annotation(from: documentAnnotation) else { continue }
                        annotationsToAdd.append(annotation)
                    }
                    if !annotationsToAdd.isEmpty {
                        _ = add(annotationsToAdd, options: [.suppressNotifications: true])
                    }
                }
                loadedDocumentCachePageIndices.insert(pageIndex)

            case .failed:
                // Database cache failed to load. Mark page in provider cache as loaded.
                loadedDocumentCachePageIndices.insert(pageIndex)

            case .unresolved, .loading:
                // Defer marking document cache page as loaded, so it can be revisited after database cache resolution.
                return
            }

            func annotation(from cachedAnnotation: RDocumentAnnotation) -> Annotation? {
                guard let documentAnnotation = PDFDocumentAnnotation(annotation: cachedAnnotation, displayName: displayName, username: username) else { return nil }
                let annotation = AnnotationConverter.annotation(from: documentAnnotation, appearance: currentAppearance, displayName: displayName, username: username)
                annotation.flags.update(with: [.locked, .readOnly])
                annotation.source = .document
                return annotation
            }
        }

        func loadDatabaseCacheIfNeededForPage(at pageIndex: PageIndex) {
            guard !loadedDatabaseCachePageIndices.contains(pageIndex) else { return }
            guard let pdfReaderAnnotationProviderDelegate else {
                DDLogWarn("PDFReaderAnnotationProvider: missing context for database annotations page \(pageIndex)")
                // Defer marking database cache page as loaded, so it can be revisited if delegate is set later.
                return
            }
            var annotationsToAdd: [Annotation] = []
            do {
                let items = try performOnDbQueue {
                    try dbStorage.perform(
                        request: ReadAnnotationsDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: Int(pageIndex)),
                        on: dbQueue
                    ).freeze()
                }
                annotationsToAdd.append(contentsOf: AnnotationConverter.annotations(
                    from: items,
                    appearance: currentAppearance,
                    currentUserId: userId,
                    libraryId: libraryId,
                    metadataEditable: metadataEditable,
                    displayName: displayName,
                    username: username,
                    documentPageCount: documentPageCount,
                    boundingBoxConverter: boundingBoxConverter
                ))
            } catch {
                DDLogError("PDFReaderAnnotationProvider: failed to read database annotations for page \(pageIndex) - \(error)")
            }
            for annotation in annotationsToAdd {
                annotation.source = .database
            }
            if !annotationsToAdd.isEmpty {
                _ = add(annotationsToAdd, options: [.suppressNotifications: true])
            }
            loadedDatabaseCachePageIndices.insert(pageIndex)
        }
    }

    override func add(_ annotations: [Annotation], options: [AnnotationManager.ChangeBehaviorKey: Any]? = nil) -> [Annotation]? {
        return performWriteAndWait {
            let addedAnnotations = super.add(annotations, options: options)
            for annotation in addedAnnotations ?? [] {
                index(annotation: annotation)
            }
            return addedAnnotations

            func index(annotation: Annotation) {
                let key = annotation.key ?? annotation.uuid
                let pageIndex = annotation.pageIndex
                loadedAnnotationsByPageByKey[pageIndex, default: [:]][key] = annotation
                loadedAnnotationsByKey[key] = annotation
            }
        }
    }

    override func remove(_ annotations: [Annotation], options: [AnnotationManager.ChangeBehaviorKey: Any]? = nil) -> [Annotation]? {
        return performWriteAndWait {
            let removedAnnotations = super.remove(annotations, options: options)
            for annotation in removedAnnotations ?? [] {
                deindex(annotation: annotation)
            }
            return removedAnnotations

            func deindex(annotation: Annotation) {
                let key = annotation.key ?? annotation.uuid
                let pageIndex = annotation.pageIndex
                loadedAnnotationsByPageByKey[pageIndex]?[key] = nil
                loadedAnnotationsByKey[key] = nil
            }
        }
    }

    // MARK: - Public Actions

    public func setVisiblePage(_ pageIndex: PageIndex) {
        performWrite { [weak self] in
            guard let self else { return }
            guard pageIndex != visiblePageIndex else { return }
            visiblePageIndex = pageIndex
        }
    }

    public func updateFilter(term: String?, filter: AnnotationsFilter?) {
        performWrite { [weak self] in
            guard let self else { return }
            let newContext = FilterContext(term: term, filter: filter)
            guard newContext != currentFilterContext else { return }
            currentFilterContext = newContext
            applyCurrentFilterToLoadedPages()
        }

        func applyCurrentFilterToLoadedPages() {
            let loadedPageIndices = loadedFilePageIndices
                .intersection(loadedDocumentCachePageIndices)
                .intersection(loadedDatabaseCachePageIndices)
            guard !loadedPageIndices.isEmpty else { return }

            var orderedPageIndices: [PageIndex] = []
            var remainingPageIndices = loadedPageIndices

            if let visiblePageIndex, documentPageCount > 0 {
                for offset in [0, -1, 1, -2, 2] {
                    let rawPage = Int(visiblePageIndex) + offset
                    guard rawPage >= 0, rawPage < Int(documentPageCount) else { continue }
                    let pageIndex = PageIndex(rawPage)
                    guard remainingPageIndices.contains(pageIndex) else { continue }
                    orderedPageIndices.append(pageIndex)
                    remainingPageIndices.remove(pageIndex)
                }
            }

            orderedPageIndices.append(contentsOf: remainingPageIndices.sorted())
            for pageIndex in orderedPageIndices {
                applyCurrentFilterForPage(at: pageIndex, notify: true)
            }
        }
    }

    public func update(metadataEditable: Bool) {
        performWrite { [weak self] in
            guard let self, metadataEditable != self.metadataEditable else { return }
            self.metadataEditable = metadataEditable
            var changedAnnotations: [Annotation] = []
            for pageIndex in loadedDatabaseCachePageIndices {
                guard let annotations = loadedAnnotationsByPageByKey[pageIndex]?.values  else { continue }
                for annotation in annotations where annotation.source == .database {
                    let shouldBeReadOnly = databaseAnnotationShouldBeReadOnly(
                        annotation: annotation,
                        metadataEditable: metadataEditable
                    )
                    guard shouldBeReadOnly != annotation.isReadOnly else { continue }
                    if shouldBeReadOnly {
                        annotation.flags.update(with: .readOnly)
                    } else {
                        annotation.flags.remove(.readOnly)
                    }
                    changedAnnotations.append(annotation)
                }
            }
            notifyAnnotationsChanged(changedAnnotations, changes: ["flags"])
        }

        func databaseAnnotationShouldBeReadOnly(annotation: Annotation, metadataEditable: Bool) -> Bool {
            guard metadataEditable else { return true }
            switch libraryId {
            case .custom:
                return false

            case .group:
                return annotation.createdByUserId != userId
            }
        }
    }

    public func update(appearance: Appearance) {
        // Appearance update happens on the calling thread without notifying of the changes.
        var shouldUpdate = false
        performWriteAndWait {
            guard appearance != currentAppearance else { return }
            currentAppearance = appearance
            shouldUpdate = true
        }
        guard shouldUpdate else { return }

        let loadedPageIndices = performRead {
            return loadedFilePageIndices
                .intersection(loadedDocumentCachePageIndices)
                .intersection(loadedDatabaseCachePageIndices)
        }
        guard !loadedPageIndices.isEmpty else { return }

        var orderedPageIndices: [PageIndex] = []
        var remainingPageIndices = loadedPageIndices

        if let visiblePageIndex, documentPageCount > 0 {
            for offset in [0, -1, 1, -2, 2] {
                let rawPage = Int(visiblePageIndex) + offset
                guard rawPage >= 0, rawPage < Int(documentPageCount) else { continue }
                let pageIndex = PageIndex(rawPage)
                guard remainingPageIndices.contains(pageIndex) else { continue }
                orderedPageIndices.append(pageIndex)
                remainingPageIndices.remove(pageIndex)
            }
        }

        orderedPageIndices.append(contentsOf: remainingPageIndices.sorted())
        for pageIndex in orderedPageIndices {
            applyCurrentAppearanceForPage(at: pageIndex, notify: false)
        }
    }

    func loadedAnnotation(with key: String) -> Annotation? {
        return performRead {
            loadedAnnotationsByKey[key]
        }
    }

    func loadedAnnotation(at pageIndex: PageIndex, with key: String) -> Annotation? {
        return performRead {
            loadedAnnotationsByPageByKey[pageIndex]?[key]
        }
    }

    public func loadDocumentAnnotationsDatabaseCache(documentMD5: String?) {
        var shouldLoad = false
        performWriteAndWait {
            guard case .unresolved = cacheStatus else { return }
            cacheStatus = .loading
            shouldLoad = true
        }
        guard shouldLoad else { return }

        if let cachedDocumentAnnotationsTuple = loadCachedDocumentAnnotations(attachmentKey: attachmentKey, libraryId: libraryId, md5: documentMD5) {
            performWriteAndWait {
                keys = cachedDocumentAnnotationsTuple.keys
                uniqueBaseColors = cachedDocumentAnnotationsTuple.uniqueBaseColors
                cacheStatus = .loaded(results: cachedDocumentAnnotationsTuple.results)
            }
            return
        }

        let pdfDocumentAnnotations = loadSupportedAndLockUnsupportedAnnotations(
            username: username,
            displayName: displayName,
            boundingBoxConverter: boundingBoxConverter
        )
        if let documentMD5 {
            let storeSucceeded = storeDocumentAnnotationsCache(
                annotations: pdfDocumentAnnotations,
                attachmentKey: attachmentKey,
                libraryId: libraryId,
                md5: documentMD5,
                documentPageCount: documentPageCount
            )
            if storeSucceeded, let cachedDocumentAnnotationsTuple = loadCachedDocumentAnnotations(attachmentKey: attachmentKey, libraryId: libraryId, md5: documentMD5) {
                performWriteAndWait {
                    keys = cachedDocumentAnnotationsTuple.keys
                    uniqueBaseColors = cachedDocumentAnnotationsTuple.uniqueBaseColors
                    cacheStatus = .loaded(results: cachedDocumentAnnotationsTuple.results)
                }
                return
            }
        }

        performWriteAndWait {
            cacheStatus = .failed
        }

        func loadCachedDocumentAnnotations(
            attachmentKey: String,
            libraryId: LibraryIdentifier,
            md5: String?
        ) -> (results: Results<RDocumentAnnotation>, keys: [PDFReaderAnnotationKey], uniqueBaseColors: [String])? {
            guard let md5, !md5.isEmpty else { return nil }
            let frozenResponse: ReadDocumentAnnotationsCacheInfoAndAnnotationsDbRequest.Response
            do {
                frozenResponse = try performOnDbQueue {
                    guard let response = try dbStorage.perform(
                        request: ReadDocumentAnnotationsCacheInfoAndAnnotationsDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: nil),
                        on: dbQueue
                    ) else {
                        return nil
                    }
                    return (response.info.freeze(), response.annotations.freeze())
                }
            } catch {
                DDLogError("PDFReaderAnnotationProvider: failed to read document annotations cache - \(error)")
                return nil
            }
            guard let cacheInfo = frozenResponse?.info, let cachedAnnotations = frozenResponse?.annotations else { return nil }
            guard cacheInfo.md5 == md5 else {
                do {
                    try performOnDbQueue {
                        try dbStorage.perform(
                            request: DeleteDocumentAnnotationsCacheDbRequest(attachmentKey: attachmentKey, libraryId: libraryId),
                            on: dbQueue
                        )
                    }
                } catch {
                    DDLogError("PDFReaderAnnotationProvider: failed to delete document annotations cache - \(error)")
                }
                return nil
            }

            let keys = Array(cachedAnnotations.map({ PDFReaderAnnotationKey(key: $0.key, sortIndex: $0.sortIndex, type: .document) }))
            let uniqueBaseColors = Array(cacheInfo.uniqueBaseColors)
            DDLogInfo("PDFReaderAnnotationProvider: loaded \(keys.count) cached document annotations")
            return (cachedAnnotations, keys, uniqueBaseColors)
        }

        func loadSupportedAndLockUnsupportedAnnotations(
            username: String,
            displayName: String,
            boundingBoxConverter: AnnotationBoundingBoxConverter?
        ) -> [PDFDocumentAnnotation] {
            // To prime the database cache all annotations are loaded from the file, so they can also be added to the provider cache.
            return performWriteAndWait {
                var documentAnnotations: [PDFDocumentAnnotation] = []
                for page in 0..<documentPageCount {
                    let pageIndex = PageIndex(page)

                    let (removedAnnotations, _) = loadFilePage(pageIndex: pageIndex)
                    for annotation in removedAnnotations {
                        annotation.key = KeyGenerator.newKey
                        guard let annotation = AnnotationConverter.annotation(
                            from: annotation,
                            color: annotation.baseColor,
                            username: username,
                            displayName: displayName,
                            defaultPageLabel: nil,
                            boundingBoxConverter: boundingBoxConverter
                        )
                        else { continue }

                        documentAnnotations.append(annotation)
                    }
                }

                return documentAnnotations
            }
        }

        func storeDocumentAnnotationsCache(
            annotations: [PDFDocumentAnnotation],
            attachmentKey: String,
            libraryId: LibraryIdentifier,
            md5: String,
            documentPageCount: PageCount
        ) -> Bool {
            let request = StoreDocumentAnnotationsCacheDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, md5: md5, pageCount: Int(documentPageCount), annotations: annotations)
            do {
                try performOnDbQueue {
                    try dbStorage.perform(request: request, on: dbQueue)
                }
                return true
            } catch {
                DDLogError("PDFReaderAnnotationProvider: failed to store document annotation cache - \(error)")
                return false
            }
        }
    }

    // MARK: - Filtering

    private func applyCurrentFilterForPage(at pageIndex: PageIndex, notify: Bool) {
        performWriteAndWait {
            let changedFileAnnotations = applyToFileNonLinkAnnotations(at: pageIndex, filterContext: currentFilterContext)
            let filteredKeys = filteredCombinedAnnotationKeys(for: Int(pageIndex), filterContext: currentFilterContext)
            let changedCacheAnnotations = applyToCacheAnnotations(at: pageIndex, filterContext: currentFilterContext, filteredKeys: filteredKeys)
            guard notify else { return }
            notifyAnnotationsChanged(changedFileAnnotations + changedCacheAnnotations, changes: ["flags"])
        }

        func filteredCombinedAnnotationKeys(for page: Int, filterContext: FilterContext) -> Set<String>? {
            guard !filterContext.isEmpty else { return nil }
            do {
                return try performOnDbQueue {
                    try dbStorage.perform(
                        request: ReadFilteredCombinedAnnotationKeysDbRequest(
                            attachmentKey: attachmentKey,
                            libraryId: libraryId,
                            page: page,
                            term: filterContext.term,
                            filter: filterContext.filter,
                            displayName: displayName,
                            username: username
                        ),
                        on: dbQueue
                    )
                }
            } catch {
                DDLogError("PDFReaderAnnotationProvider: failed to read filtered combined annotation keys for page \(page) - \(error)")
                return []
            }
        }

        func applyToFileNonLinkAnnotations(at pageIndex: PageIndex, filterContext: FilterContext) -> [Annotation] {
            var changedAnnotations: [Annotation] = []
            // Annotations that are handled by the file annotation provider are always hidden, if not LinkAnnotation.
            // TODO: Desktop client shows them instead. Resolve this and update.
            for annotation in loadedFileNonLinkAnnotationsByPage[pageIndex] ?? [] {
                let isHidden = !filterContext.isEmpty
                guard annotation.isHidden != isHidden else { continue }
                annotation.isHidden = isHidden
                changedAnnotations.append(annotation)
            }
            return changedAnnotations
        }

        func applyToCacheAnnotations(at pageIndex: PageIndex, filterContext: FilterContext, filteredKeys: Set<String>?) -> [Annotation] {
            var changedAnnotations: [Annotation] = []
            for annotation in (loadedAnnotationsByPageByKey[pageIndex] ?? [:]).values {
                guard annotation.source != nil else { continue }
                let isHidden: Bool
                if filterContext.isEmpty {
                    isHidden = false
                } else {
                    let annotationKey = annotation.key ?? annotation.uuid
                    isHidden = !(filteredKeys?.contains(annotationKey) ?? false)
                }
                guard annotation.isHidden != isHidden else { continue }
                annotation.isHidden = isHidden
                changedAnnotations.append(annotation)
            }
            return changedAnnotations
        }
    }

    // MARK: Appearance

    private func applyCurrentAppearanceForPage(at pageIndex: PageIndex, notify: Bool) {
        performWriteAndWait {
            let changedFileAnnotations = applyToFileNonLinkAnnotations(at: pageIndex, appearance: currentAppearance)
            let changedCacheAnnotations = applyToCacheAnnotations(at: pageIndex, appearance: currentAppearance)
            guard notify else { return }
            notifyAnnotationsChanged(changedFileAnnotations + changedCacheAnnotations, changes: ["color", "alpha", "blendMode"])
        }

        func applyToFileNonLinkAnnotations(at pageIndex: PageIndex, appearance: Appearance) -> [Annotation] {
            var changedAnnotations: [Annotation] = []
            for annotation in loadedFileNonLinkAnnotationsByPage[pageIndex] ?? [] {
                guard change(annotation, to: appearance) else { continue }
                changedAnnotations.append(annotation)
            }
            return changedAnnotations
        }

        func applyToCacheAnnotations(at pageIndex: PageIndex, appearance: Appearance) -> [Annotation] {
            var changedAnnotations: [Annotation] = []
            for annotation in (loadedAnnotationsByPageByKey[pageIndex] ?? [:]).values {
                guard change(annotation, to: appearance) else { continue }
                changedAnnotations.append(annotation)
            }
            return changedAnnotations
        }

        func change(_ annotation: Annotation, to appearance: Appearance) -> Bool {
            guard AnnotationsConfig.supported.contains(annotation.type),
                  let annotationType = annotation.type.annotationType
            else { return false }

            let baseColor = annotation.baseColor
            let (color, alpha, blendMode) = AnnotationColorGenerator.color(
                from: UIColor(hex: baseColor),
                type: annotationType,
                appearance: currentAppearance
            )

            let normalizedBlendMode = blendMode ?? .normal
            guard annotation.color != color ||
                  annotation.alpha != alpha ||
                  annotation.blendMode != normalizedBlendMode
            else { return false }

            annotation.color = color
            annotation.alpha = alpha
            annotation.blendMode = normalizedBlendMode
            return true
        }
    }

    // MARK: Private Methods

    private func loadFilePage(pageIndex: PageIndex) -> (removedAnnotations: [Annotation], remainingAnnotations: [Annotation]) {
        return performWriteAndWait {
            var removedAnnotations: [Annotation] = []
            var remainingAnnotations: [Annotation] = []
            var remainingNonLinkAnnotations: [Annotation] = []
            for annotation in fileAnnotationProvider.annotationsForPage(at: pageIndex) ?? [] {
                if annotation is LinkAnnotation {
                    // Don't lock Link Annotations, as they are not editable, and if numerous they can create a noticeable hang the first time the document lazily evaluates dirty annotations.
                    remainingAnnotations.append(annotation)
                    continue
                }
                annotation.flags.update(with: .locked)
                if !AnnotationsConfig.supported.contains(annotation.type) {
                    // Unsupported annotations aren't visible in sidebar.
                    remainingAnnotations.append(annotation)
                    remainingNonLinkAnnotations.append(annotation)
                    continue
                }
                // Check whether square annotation was previously created by Zotero.
                if let square = annotation as? PSPDFKit.SquareAnnotation, !square.isZoteroAnnotation {
                    // If it's just "normal" square (instead of our image) annotation, don't convert it to Zotero annotation.
                    remainingAnnotations.append(annotation)
                    remainingNonLinkAnnotations.append(annotation)
                    continue
                }
                // Remove annotation from file annotation provider cache, as it is handled by this provider's cache.
                removedAnnotations.append(annotation)
            }
            fileAnnotationProvider.remove(removedAnnotations, options: [.suppressNotifications: true])
            loadedFilePageIndices.insert(pageIndex)
            loadedFileNonLinkAnnotationsByPage[pageIndex] = remainingNonLinkAnnotations
            return (removedAnnotations: removedAnnotations, remainingAnnotations: remainingAnnotations)
        }
    }

    private func performOnDbQueue<Result>(_ work: () throws -> Result) throws -> Result {
        if DispatchQueue.getSpecific(key: dbQueueSpecificKey) != nil {
            return try work()
        }
        return try dbQueue.sync(execute: work)
    }

    private func postChangeNotification(for annotations: [Annotation], changes: [String]) {
        inMainThread {
            for annotation in annotations {
                NotificationCenter.default.post(
                    name: .PSPDFAnnotationChanged,
                    object: annotation,
                    userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: changes]
                )
            }
        }
    }

    private func notifyAnnotationsChanged(_ annotations: [Annotation], changes: [String]) {
        guard !annotations.isEmpty else { return }
        if let providerDelegate {
            providerDelegate.update(annotations, animated: true)
        } else {
            postChangeNotification(for: annotations, changes: changes)
        }
    }
}
