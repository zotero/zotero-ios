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
    private let displayName: String
    private let username: String

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
    private var loadedCachePageIndices = Set<PageIndex>()

    init(documentProvider: PDFDocumentProvider, fileAnnotationProvider: PDFFileAnnotationProvider, dbStorage: DbStorage, displayName: String, username: String) {
        self.fileAnnotationProvider = fileAnnotationProvider
        self.dbStorage = dbStorage
        self.displayName = displayName
        self.username = username
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
        return performRead { loadedFilePageIndices.contains(pageIndex) && loadedCachePageIndices.contains(pageIndex) }
    }

    private func annotation(from cachedAnnotation: RDocumentAnnotation) -> Annotation? {
        guard let documentAnnotation = PDFDocumentAnnotation(annotation: cachedAnnotation, displayName: displayName, username: username) else { return nil }
        let appearance = pdfReaderAnnotationProviderDelegate?.appearance ?? .light

        let annotation = AnnotationConverter.annotation(from: documentAnnotation, appearance: appearance, displayName: displayName, username: username)
        annotation.flags.update(with: [.locked, .readOnly])
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
        let cachePageIsLoaded = performRead { loadedCachePageIndices.contains(pageIndex) }
        if filePageIsLoaded && cachePageIsLoaded {
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

            // Then the index for the document annotations that are read from the database cache.
            loadCachedDocumentAnnotationsIfNeededForPage(at: pageIndex)

            // Annotations are fetched from super, apart from cached document annotations, as more may have been added before it was accessed here.
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

        func loadCachedDocumentAnnotationsIfNeededForPage(at pageIndex: PageIndex) {
            guard !loadedCachePageIndices.contains(pageIndex) else { return }
            switch cacheStatus {
            case .loaded(let results):
                // Database cache is loaded, load annotations to provider cache.
                let cachedDocumentAnnotations = Array(results.filter("page = %d", Int(pageIndex)))
                if !cachedDocumentAnnotations.isEmpty {
                    // There are document annotations for this page in the database cache, add them to provider cache.
                    var annotationsToAdd: [Annotation] = []
                    for cachedDocumentAnnotation in cachedDocumentAnnotations {
                        guard let annotation = annotation(from: cachedDocumentAnnotation) else { continue }
                        annotationsToAdd.append(annotation)
                    }
                    if !annotationsToAdd.isEmpty {
                        _ = super.add(annotationsToAdd, options: [.suppressNotifications: true])
                    }
                }
                loadedCachePageIndices.insert(pageIndex)

            case .failed:
                // Database cache failed to load. Mark page in provider cache as loaded.
                loadedCachePageIndices.insert(pageIndex)

            case .unresolved, .loading:
                // Defer marking page in provider cache as loaded, so it can be revisited after database cache resolution.
                return
            }
        }
    }

    override func add(_ annotations: [Annotation], options: [AnnotationManager.ChangeBehaviorKey: Any]? = nil) -> [Annotation]? {
        return super.add(annotations, options: options)
    }

    override func remove(_ annotations: [Annotation], options: [AnnotationManager.ChangeBehaviorKey: Any]? = nil) -> [Annotation]? {
        return super.remove(annotations, options: options)
    }

    // MARK: - Public Actions

    public func loadCache(
        attachmentKey: String,
        libraryId: LibraryIdentifier,
        documentMD5: String?,
        pageCount: Int,
        boundingBoxConverter: AnnotationBoundingBoxConverter?
    ) {
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
                pageCount: pageCount
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
            var response: ReadDocumentAnnotationsCacheInfoAndAnnotationsDbRequest.Response!
            do {
                response = try dbStorage.perform(request: ReadDocumentAnnotationsCacheInfoAndAnnotationsDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: nil), on: .main)
            } catch {
                DDLogError("PDFReaderAnnotationProvider: failed to read document annotations cache - \(error)")
                return nil
            }
            guard let (cacheInfo, cachedAnnotations) = response else { return nil }
            guard cacheInfo.md5 == md5 else {
                do {
                    try dbStorage.perform(request: DeleteDocumentAnnotationsCacheDbRequest(attachmentKey: attachmentKey, libraryId: libraryId), on: .main)
                } catch {
                    DDLogError("PDFReaderAnnotationProvider: failed to delete document annotations cache - \(error)")
                }
                return nil
            }

            let frozenInfo = cacheInfo.freeze()
            let frozenAnnotations = cachedAnnotations.freeze()
            let keys = Array(frozenAnnotations.map({ PDFReaderState.AnnotationKey(key: $0.key, sortIndex: $0.sortIndex, type: .document) }))
            let uniqueBaseColors = Array(frozenInfo.uniqueBaseColors)
            DDLogInfo("PDFReaderAnnotationProvider: loaded \(keys.count) cached document annotations")
            return (frozenAnnotations, keys, uniqueBaseColors)
        }

        func loadSupportedAndLockUnsupportedAnnotations(
            username: String,
            displayName: String,
            boundingBoxConverter: AnnotationBoundingBoxConverter?
        ) -> [PDFDocumentAnnotation] {
            // To prime the database cache all annotations are loaded from the file, so they can also be added to the provider cache.
            return performWriteAndWait {
                var documentAnnotations: [PDFDocumentAnnotation] = []
                for page in 0..<pageCount {
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
            pageCount: Int
        ) -> Bool {
            let request = StoreDocumentAnnotationsCacheDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, md5: md5, pageCount: pageCount, annotations: annotations)
            do {
                try dbStorage.perform(request: request, on: .main)
                return true
            } catch {
                DDLogError("PDFReaderAnnotationProvider: failed to store document annotation cache - \(error)")
                return false
            }
        }
    }
}
