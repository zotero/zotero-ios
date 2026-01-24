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
    func deleteDocumentAnnotationsCache(for key: String, libraryId: LibraryIdentifier)
    var appearance: Appearance { get }
}

final class PDFReaderAnnotationProvider: PDFContainerAnnotationProvider {
    private enum Source {
        case unresolved
        case resolving
        case resolved
        case failed
    }

    private let fileAnnotationProvider: PDFFileAnnotationProvider
    private unowned let dbStorage: DbStorage
    private let displayName: String
    private let username: String

    public private(set) var results: Results<RDocumentAnnotation>?
    public private(set) var keys: [PDFReaderState.AnnotationKey] = []
    public private(set) var uniqueBaseColors: [String] = []
    public weak var pdfReaderAnnotationProviderDelegate: PDFReaderAnnotationProviderDelegate?

    private var source: Source = .unresolved
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
            let pageFileAnnotations = fileAnnotationProvider.annotationsForPage(at: pageIndex)
            let cachePageAnnotations = super.annotationsForPage(at: pageIndex)

            if pageFileAnnotations == nil, cachePageAnnotations == nil {
                return nil
            }
            return (pageFileAnnotations ?? []) + (cachePageAnnotations ?? [])
        }
        return performWriteAndWait {// () -> [Annotation]? in
            // Because we had to leave the critical region from reading to writing, another thread could have raced here before us.
            // In order to prevent caching the same annotations multiple times, we check again our indices first.
            let pageFileAnnotations: [Annotation]?
            if loadedFilePageIndices.contains(pageIndex) {
                pageFileAnnotations = fileAnnotationProvider.annotationsForPage(at: pageIndex)
            } else {
                (_, pageFileAnnotations) = loadFilePage(pageIndex: pageIndex)
            }

            if !loadedCachePageIndices.contains(pageIndex) {
                // Annotations from database cache not loaded yet.
                if let cachedDocumentAnnotations = results.flatMap({ Array($0.filter("page = %d", Int(pageIndex))) }), !cachedDocumentAnnotations.isEmpty {
                    // There are cached document annotations for this page, add them to provider cache
                    var annotationsToAdd: [Annotation] = []
                    for cachedDocumentAnnotation in cachedDocumentAnnotations {
                        guard let annotation = annotation(from: cachedDocumentAnnotation) else { continue }
                        annotationsToAdd.append(annotation)
                    }
                    loadedCachePageIndices.insert(pageIndex)
                    if !annotationsToAdd.isEmpty {
                        _ = super.add(annotationsToAdd, options: [.suppressNotifications: true])
                    }
                }
                // In any case, this page is considered loaded.
                loadedCachePageIndices.insert(pageIndex)
            }
            // Annotations are fetched from super, as apart from cached document annotations, more may have been added before it was accessed here.
            let cachePageAnnotations = super.annotationsForPage(at: pageIndex)

            if pageFileAnnotations == nil, cachePageAnnotations == nil {
                return nil
            }
            return (pageFileAnnotations ?? []) + (cachePageAnnotations ?? [])
        }

        func annotation(from cachedAnnotation: RDocumentAnnotation) -> Annotation? {
            guard let documentAnnotation = PDFDocumentAnnotation(annotation: cachedAnnotation, displayName: displayName, username: username)
            else { return nil }
            let appearance = pdfReaderAnnotationProviderDelegate?.appearance ?? .light

            let annotation = AnnotationConverter.annotation(from: documentAnnotation, appearance: appearance, displayName: displayName, username: username)
            annotation.flags.update(with: [.locked, .readOnly])
            return annotation
        }
    }

    override func add(_ annotations: [Annotation], options: [AnnotationManager.ChangeBehaviorKey: Any]? = nil) -> [Annotation]? {
        return super.add(annotations, options: options)
    }

    override func remove(_ annotations: [Annotation], options: [AnnotationManager.ChangeBehaviorKey: Any]? = nil) -> [Annotation]? {
        return super.remove(annotations, options: options)
    }

    // MARK: - Public Actions

    public func createCacheIfNeeded(
        attachmentKey: String,
        libraryId: LibraryIdentifier,
        documentMD5: String?,
        pageCount: Int,
        boundingBoxConverter: AnnotationBoundingBoxConverter?
    ) {
        var shouldResolve = false
        performWriteAndWait {
            guard case .unresolved = source else { return }
            source = .resolving
            shouldResolve = true
        }
        guard shouldResolve else { return }

        if let cachedDocumentAnnotationsTuple = loadCachedDocumentAnnotations(attachmentKey: attachmentKey, libraryId: libraryId, md5: documentMD5) {
            performWriteAndWait {
                results = cachedDocumentAnnotationsTuple.results
                keys = cachedDocumentAnnotationsTuple.keys
                uniqueBaseColors = cachedDocumentAnnotationsTuple.uniqueBaseColors
                source = .resolved
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
                    results = cachedDocumentAnnotationsTuple.results
                    keys = cachedDocumentAnnotationsTuple.keys
                    uniqueBaseColors = cachedDocumentAnnotationsTuple.uniqueBaseColors
                    source = .resolved
                }
                return
            }
        }

        performWrite { [weak self] in
            self?.source = .failed
        }

        func loadCachedDocumentAnnotations(
            attachmentKey: String,
            libraryId: LibraryIdentifier,
            md5: String?
        ) -> (results: Results<RDocumentAnnotation>, keys: [PDFReaderState.AnnotationKey], uniqueBaseColors: [String])? {
            guard let md5, !md5.isEmpty else { return nil }
            var response: ReadDocumentAnnotationsCacheInfoAndAnnotationsDbRequest.Response!
            do {
                try dbStorage.perform(on: .main, with: { coordinator in
                    response = try coordinator.perform(request: ReadDocumentAnnotationsCacheInfoAndAnnotationsDbRequest(attachmentKey: attachmentKey, libraryId: libraryId, page: nil))
                })
            } catch {
                DDLogError("PDFReaderAnnotationProvider: failed to read document annotations cache - \(error)")
                return nil
            }
            guard let (cacheInfo, cachedAnnotations) = response else { return nil }
            guard cacheInfo.md5 == md5 else {
                pdfReaderAnnotationProviderDelegate?.deleteDocumentAnnotationsCache(for: attachmentKey, libraryId: libraryId)
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
                DDLogError("PDFReaderAnnotationProbvider: failed to store document annotation cache - \(error)")
                return false
            }
        }
    }
}
