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
    var appearance: Appearance { get }
}

final class PDFReaderAnnotationProvider: PDFContainerAnnotationProvider {
    private enum CacheStatus {
        case unresolved
        case loading
        case loaded(results: Results<RDocumentAnnotation>)
        case failed
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
    public private(set) var keys: [PDFReaderState.AnnotationKey] = []
    public private(set) var uniqueBaseColors: [String] = []
    public weak var pdfReaderAnnotationProviderDelegate: PDFReaderAnnotationProviderDelegate?

    private var cacheStatus: CacheStatus = .unresolved
    private var loadedFilePageIndices = Set<PageIndex>()
    private var loadedDocumentCachePageIndices = Set<PageIndex>()
    private var loadedDatabaseCachePageIndices = Set<PageIndex>()
    private var loadedAnnotationsByPageByKey: [PageIndex: [String: Annotation]] = [:]
    private var loadedAnnotationsByKey: [String: Annotation] = [:]

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
        boundingBoxConverter: AnnotationBoundingBoxConverter
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
        dbQueue.setSpecific(key: dbQueueSpecificKey, value: ())
        super.init(documentProvider: documentProvider)
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

    private func annotation(from cachedAnnotation: RDocumentAnnotation) -> Annotation? {
        guard let documentAnnotation = PDFDocumentAnnotation(annotation: cachedAnnotation, displayName: displayName, username: username) else { return nil }
        let appearance = pdfReaderAnnotationProviderDelegate?.appearance ?? .light

        let annotation = AnnotationConverter.annotation(from: documentAnnotation, appearance: appearance, displayName: displayName, username: username)
        annotation.flags.update(with: [.locked, .readOnly])
        annotation.source = .document
        return annotation
    }

    private func loadFilePage(pageIndex: PageIndex) -> (removedAnnotations: [Annotation], remainingAnnotations: [Annotation]) {
        var removedAnnotations: [Annotation] = []
        var remainingAnnotations: [Annotation] = []
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
                continue
            }
            // Check whether square annotation was previously created by Zotero.
            if let square = annotation as? PSPDFKit.SquareAnnotation, !square.isZoteroAnnotation {
                // If it's just "normal" square (instead of our image) annotation, don't convert it to Zotero annotation.
                remainingAnnotations.append(annotation)
                continue
            }
            removedAnnotations.append(annotation)
        }
        // Remove annotation from file annotation provider cache, as it is handled by this provider's cache.
        fileAnnotationProvider.remove(removedAnnotations, options: [.suppressNotifications: true])
        loadedFilePageIndices.insert(pageIndex)
        return (removedAnnotations: removedAnnotations, remainingAnnotations: remainingAnnotations)
    }

    override func annotationsForPage(at pageIndex: PageIndex) -> [Annotation]? {
        let filePageIsLoaded = performRead { loadedFilePageIndices.contains(pageIndex) }
        let documentCachePageIsLoaded = performRead { loadedDocumentCachePageIndices.contains(pageIndex) }
        let databaseCachePageIsLoaded = performRead { loadedDatabaseCachePageIndices.contains(pageIndex) }
        if filePageIsLoaded && documentCachePageIsLoaded && databaseCachePageIsLoaded {
            let filePageAnnotations = fileAnnotationProvider.annotationsForPage(at: pageIndex)
            let cachePageAnnotations = super.annotationsForPage(at: pageIndex)

            if filePageAnnotations == nil, cachePageAnnotations == nil {
                return nil
            }
            return (filePageAnnotations ?? []) + (cachePageAnnotations ?? [])
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
                    appearance: pdfReaderAnnotationProviderDelegate.appearance,
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

    public func update(metadataEditable: Bool) {
        performWriteAndWait {
            guard metadataEditable != self.metadataEditable else { return }
            self.metadataEditable = metadataEditable
            for pageIndex in loadedDatabaseCachePageIndices {
                guard let annotations = super.annotationsForPage(at: pageIndex) else { continue }
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
                    NotificationCenter.default.post(
                        name: .PSPDFAnnotationChanged,
                        object: annotation,
                        userInfo: [PSPDFAnnotationChangedNotificationKeyPathKey: ["flags"]]
                    )
                }
            }
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
        ) -> (results: Results<RDocumentAnnotation>, keys: [PDFReaderState.AnnotationKey], uniqueBaseColors: [String])? {
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

            let keys = Array(cachedAnnotations.map({ PDFReaderState.AnnotationKey(key: $0.key, sortIndex: $0.sortIndex, type: .document) }))
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

    private func performOnDbQueue<Result>(_ work: () throws -> Result) throws -> Result {
        if DispatchQueue.getSpecific(key: dbQueueSpecificKey) != nil {
            return try work()
        }
        return try dbQueue.sync(execute: work)
    }
}
