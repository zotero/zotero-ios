//
//  SquareAnnotationPreviewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

typealias AnnotationPreviewUpdate = (annotationKey: String, pdfKey: String, image: UIImage)

final class AnnotationPreviewController: NSObject {
    enum Error: Swift.Error {
        case imageNotAvailable
    }

    struct SubscriberKey: Hashable {
        let key: String
        let parentKey: String
        let size: CGSize
        let scale: CGFloat
    }
    
    /// Type of annotation preview
    /// - temporary: Rendered image is returned by `Single<UIImage>` immediately, no caching is performed.
    /// - cachedAndReported: Rendered image is cached and reported through global observable `PublishSubject<AnnotationPreviewUpdate>`.
    /// - cachedOnly: Rendered image is only cached for later use.
    enum PreviewType {
        case temporary(subscriberKey: SubscriberKey)
        case cachedAndReported
        case cachedOnly
    }

    let observable: PublishSubject<AnnotationPreviewUpdate>
    private let previewSize: CGSize
    private let queue: DispatchQueue
    private unowned let fileStorage: FileStorage

    private var subscribers: [SubscriberKey: (SingleEvent<UIImage>) -> Void]

    init(previewSize: CGSize, fileStorage: FileStorage) {
        self.previewSize = previewSize
        self.fileStorage = fileStorage
        self.subscribers = [:]
        self.observable = PublishSubject()
        self.queue = DispatchQueue(label: "org.zotero.AnnotationPreviewController.queue", qos: .userInitiated)
        super.init()
    }
}

import PSPDFKit

// MARK: - PSPDFKit

extension AnnotationPreviewController {
    /// Renders part of document if it's not cached already and returns as `Single`. Does not write results to cache file.
    /// - parameter document: Document to render.
    /// - parameter page: Page of document to render.
    /// - parameter rect: Part of page of document to render.
    /// - parameter imageSize: Size of rendered image.
    /// - parameter imageScale: Scale factor of rendering. 0.0 will result to the PSPDFkit default.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of parent of annotation.
    /// - parameter libraryId: Library identifier of item.
    /// - returns: `Single` with rendered image.
    func render(document: Document, page: PageIndex, rect: CGRect, imageSize: CGSize, imageScale: CGFloat, key: String, parentKey: String, libraryId: LibraryIdentifier) -> Single<UIImage> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let self = self else { return Disposables.create() }

            let subscriberKey = SubscriberKey(key: key, parentKey: parentKey, size: imageSize, scale: imageScale)
            self.queue.async(flags: .barrier) {
                self.subscribers[subscriberKey] = subscriber
            }

            enqueue(
                key: key,
                parentKey: parentKey,
                libraryId: libraryId,
                document: document,
                pageIndex: page,
                rect: rect,
                imageSize: imageSize,
                imageScale: imageScale,
                type: .temporary(subscriberKey: subscriberKey)
            )

            return Disposables.create()
        }
    }

    /// Stores preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be cached.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    func store(for annotation: PSPDFKit.Annotation, parentKey: String, libraryId: LibraryIdentifier, isDark: Bool) {
        guard annotation.shouldRenderPreview && annotation.isZoteroAnnotation, let document = annotation.document else { return }

        // Cache and report original color
        let rect = annotation.previewBoundingBox
        let includeAnnotation = annotation is PSPDFKit.InkAnnotation || annotation is PSPDFKit.FreeTextAnnotation
        enqueue(
            key: annotation.previewId,
            parentKey: parentKey,
            libraryId: libraryId,
            document: document,
            pageIndex: annotation.pageIndex,
            rect: rect,
            imageSize: previewSize,
            imageScale: 0.0,
            includeAnnotation: includeAnnotation,
            isDark: isDark,
            type: .cachedAndReported
        )
    }

    /// Deletes cached preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be deleted.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    func delete(for annotation: PSPDFKit.Annotation, parentKey: String, libraryId: LibraryIdentifier) {
        guard annotation.shouldRenderPreview && annotation.isZoteroAnnotation else { return }

        let key = annotation.previewId
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, isDark: true))
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, isDark: false))
        }
    }

    func deleteAll(parentKey: String, libraryId: LibraryIdentifier) {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            try? self.fileStorage.remove(Files.annotationPreviews(for: parentKey, libraryId: libraryId))
        }
    }

    /// Checks whether preview is available for given annotation.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - returns: `true` if preview is available, `false` otherwise.
    func hasPreview(for key: String, parentKey: String, libraryId: LibraryIdentifier, isDark: Bool) -> Bool {
        return self.fileStorage.has(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, isDark: isDark))
    }

    /// Loads cached preview for given annotation.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - parameter completed: Completion handler which contains loaded preview or `nil` if loading wasn't successful.
    func preview(for key: String, parentKey: String, libraryId: LibraryIdentifier, isDark: Bool, completed: @escaping (UIImage?) -> Void) {
        self.queue.async { [weak self] in
            guard let self = self else { return }

            do {
                let data = try self.fileStorage.read(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, isDark: isDark))
                DispatchQueue.main.async {
                    completed(UIImage(data: data))
                }
            } catch {
                DispatchQueue.main.async {
                    completed(nil)
                }
            }
        }
    }

    /// Creates and enqueues a render request for PSPDFKit rendering engine.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of PDF item in which the annotation is stored.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter document: Document to render.
    /// - parameter pageIndex: Page to render.
    /// - parameter rect: Part of page to render.
    /// - parameter imageSize: Size of rendered image.
    /// - parameter imageScale: Scale factor of rendering. 0.0 will result to the PSPDFkit default. Unsupported values will also result to default.
    /// - parameter includeAnnotation: If true, render annotation as well, otherwise render PDF only.
    /// - parameter isDark: `true` if rendered image is in dark mode, `false` otherwise.
    /// - parameter type: Type of preview image. If `temporary`, requested image is temporary and is returned as `Single<UIImage>`. Otherwise image is
    ///                   cached locally and reported through `PublishSubject`.
    private func enqueue(
        key: String,
        parentKey: String,
        libraryId: LibraryIdentifier,
        document: Document,
        pageIndex: PageIndex,
        rect: CGRect,
        imageSize: CGSize,
        imageScale: CGFloat,
        includeAnnotation: Bool = false,
        isDark: Bool = false,
        type: PreviewType
    ) {
        guard let fileURL = document.fileURL else { return }

        let newDocument = Document(url: fileURL)

        if includeAnnotation, let annotation = document.annotations(at: pageIndex).first(where: { $0.previewId == key }) {
            newDocument.add(annotations: [annotation], options: [.suppressNotifications: true])
        }

        let options = RenderOptions()
        options.invertRenderColor = isDark

        let request = MutableRenderRequest(document: newDocument)
        request.pageIndex = pageIndex
        request.pdfRect = rect
        request.imageSize = imageSize
        request.imageScale = [1.0, 2.0, 3.0].contains(imageScale) ? imageScale : 0.0
        request.options = options

        do {
            let task = try RenderTask(request: request)
            task.priority = .userInitiated
            task.completionHandler = { [weak self] image, error in
                let result: Result<UIImage, Swift.Error> = image.flatMap({ .success($0) }) ?? .failure(error ?? Error.imageNotAvailable)
                self?.queue.async {
                    self?.completeRequest(with: result, key: key, parentKey: parentKey, libraryId: libraryId, isDark: isDark, type: type)
                }
            }

            PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
        } catch let error {
            DDLogError("AnnotationPreviewController: can't create task - \(error)")
        }
    }

    private func completeRequest(with result: Result<UIImage, Swift.Error>, key: String, parentKey: String, libraryId: LibraryIdentifier, isDark: Bool, type: PreviewType) {
        switch result {
        case .success(let image):
            switch type {
            case .temporary(let subscriberKey):
                self.perform(event: .success(image), subscriberKey: subscriberKey)

            case .cachedOnly:
                self.cache(image: image, key: key, pdfKey: parentKey, libraryId: libraryId, isDark: isDark)

            case .cachedAndReported:
                self.cache(image: image, key: key, pdfKey: parentKey, libraryId: libraryId, isDark: isDark)
                self.observable.on(.next((key, parentKey, image)))
            }

        case .failure(let error):
            DDLogError("AnnotationPreviewController: could not generate image - \(error)")

            switch type {
            case .temporary(let subscriberKey):
                // Temporary request always needs to return an error if image was not available
                self.perform(event: .failure(error), subscriberKey: subscriberKey)
                
            default:
                break
            }
        }
    }

    private func perform(event: SingleEvent<UIImage>, subscriberKey: SubscriberKey) {
        self.subscribers[subscriberKey]?(event)
        self.subscribers[subscriberKey] = nil
    }

    private func cache(image: UIImage, key: String, pdfKey: String, libraryId: LibraryIdentifier, isDark: Bool) {
        guard let data = image.pngData() else {
            DDLogError("AnnotationPreviewController: can't create data from image")
            return
        }

        do {
            try self.fileStorage.write(data, to: Files.annotationPreview(annotationKey: key, pdfKey: pdfKey, libraryId: libraryId, isDark: isDark), options: .atomicWrite)
        } catch let error {
            DDLogError("AnnotationPreviewController: can't store preview - \(error)")
        }
    }
}
