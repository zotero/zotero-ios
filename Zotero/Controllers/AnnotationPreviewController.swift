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
    fileprivate struct EnqueuedData {
        let key: String
        let parentKey: String
        let libraryId: LibraryIdentifier
        let document: Document
        let pageIndex: PageIndex
        let rect: CGRect
        let imageSize: CGSize
        let imageScale: CGFloat
        let includeAnnotation: Bool
        let appearance: Appearance
        let type: PreviewType

        init(
            document: Document,
            page: PageIndex,
            rect: CGRect,
            imageSize: CGSize,
            imageScale: CGFloat,
            key: String,
            parentKey: String,
            libraryId: LibraryIdentifier,
            includeAnnotation: Bool = false,
            appearance: Appearance,
            type: PreviewType
        ) {
            self.key = key
            self.parentKey = parentKey
            self.libraryId = libraryId
            self.document = document
            pageIndex = page
            self.rect = rect
            self.imageSize = imageSize
            self.imageScale = imageScale
            self.includeAnnotation = includeAnnotation
            self.appearance = appearance
            self.type = type
        }

        init?(annotation: PSPDFKit.Annotation, parentKey: String, libraryId: LibraryIdentifier, imageSize: CGSize, imageScale: CGFloat, appearance: Appearance, type: PreviewType) {
            guard annotation.shouldRenderPreview, let document = annotation.document else { return nil }
            key = annotation.previewId
            self.parentKey = parentKey
            self.libraryId = libraryId
            self.document = document
            pageIndex = annotation.pageIndex
            rect = annotation.previewBoundingBox
            self.imageSize = imageSize
            self.imageScale = imageScale
            includeAnnotation = annotation is PSPDFKit.InkAnnotation || annotation is PSPDFKit.FreeTextAnnotation
            self.appearance = appearance
            self.type = type
        }
    }

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
    private let scheduler: SerialDispatchQueueScheduler
    private unowned let fileStorage: FileStorage

    private var subscribers: [SubscriberKey: (SingleEvent<UIImage>) -> Void]

    init(previewSize: CGSize, fileStorage: FileStorage) {
        let queue = DispatchQueue(label: "org.zotero.AnnotationPreviewController.queue", qos: .userInitiated)
        self.previewSize = previewSize
        self.fileStorage = fileStorage
        self.queue = queue
        scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.AnnotationPreviewController.scheduler")
        subscribers = [:]
        observable = PublishSubject()
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
            guard let self else { return Disposables.create() }

            let subscriberKey = SubscriberKey(key: key, parentKey: parentKey, size: imageSize, scale: imageScale)
            subscribers[subscriberKey] = subscriber
            enqueue(data:
                .init(
                    document: document,
                    page: page,
                    rect: rect,
                    imageSize: imageSize,
                    imageScale: imageScale,
                    key: key,
                    parentKey: parentKey,
                    libraryId: libraryId,
                    appearance: .light,
                    type: .temporary(subscriberKey: subscriberKey)
                )
            )

            return Disposables.create()
        }
        .subscribe(on: scheduler)
    }

    /// Stores preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be cached.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    func store(for annotation: PSPDFKit.Annotation, parentKey: String, libraryId: LibraryIdentifier, appearance: Appearance) {
        queue.async { [weak self] in
            guard
                let self,
                let data = EnqueuedData(annotation: annotation, parentKey: parentKey, libraryId: libraryId, imageSize: previewSize, imageScale: 0, appearance: appearance, type: .cachedAndReported)
            else { return }
            enqueue(data: data)
        }
    }

    func store(annotations: [PSPDFKit.Annotation], parentKey: String, libraryId: LibraryIdentifier, appearance: Appearance) {
        queue.async { [weak self] in
            guard let self else { return }
            for annotation in annotations {
                guard
                    let data = EnqueuedData(annotation: annotation, parentKey: parentKey, libraryId: libraryId, imageSize: previewSize, imageScale: 0, appearance: appearance, type: .cachedOnly)
                else { continue }
                enqueue(data: data)
            }
        }
    }

    /// Deletes cached preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be deleted.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    func delete(for annotation: PSPDFKit.Annotation, parentKey: String, libraryId: LibraryIdentifier) {
        delete(annotations: [annotation], parentKey: parentKey, libraryId: libraryId)
    }

    func delete(annotations: [PSPDFKit.Annotation], parentKey: String, libraryId: LibraryIdentifier) {
        let keys: [String] = annotations.compactMap({ annotation in
            guard annotation.shouldRenderPreview && annotation.isZoteroAnnotation else { return nil }
            return annotation.previewId
        })
        queue.async { [weak self] in
            guard let self else { return }
            for key in keys {
                try? fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, appearance: .dark))
                try? fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, appearance: .light))
                try? fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, appearance: .sepia))
            }
        }
    }

    func deleteAll(parentKey: String, libraryId: LibraryIdentifier) {
        queue.async { [weak self] in
            try? self?.fileStorage.remove(Files.annotationPreviews(for: parentKey, libraryId: libraryId))
        }
    }

    /// Checks whether preview is available for given annotation.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - returns: `true` if preview is available, `false` otherwise.
    func hasPreview(for key: String, parentKey: String, libraryId: LibraryIdentifier, appearance: Appearance) -> Bool {
        return fileStorage.has(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, appearance: appearance))
    }

    /// Loads cached preview for given annotation.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - parameter completed: Completion handler which contains loaded preview or `nil` if loading wasn't successful.
    func preview(for key: String, parentKey: String, libraryId: LibraryIdentifier, appearance: Appearance, completed: @escaping (UIImage?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }

            do {
                let data = try fileStorage.read(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, appearance: appearance))
                let image = UIImage(data: data)
                DispatchQueue.main.async {
                    completed(image)
                }
            } catch {
                DispatchQueue.main.async {
                    completed(nil)
                }
            }
        }
    }

    /// Creates and enqueues a render request for PSPDFKit rendering engine.
    private func enqueue(data: EnqueuedData) {
        let options = RenderOptions()
        switch data.appearance {
        case .dark:
            options.invertRenderColor = true
            options.filters = [.colorCorrectInverted]

        case .sepia:
            options.filters = [.sepia]

        case .light:
            break
        }

        let request = MutableRenderRequest(document: data.document)
        request.pageIndex = data.pageIndex
        request.pdfRect = data.rect
        request.imageSize = data.imageSize
        request.annotations = data.includeAnnotation ? data.document.annotations(at: data.pageIndex).filter({ $0.previewId == data.key }) : []
        request.imageScale = [1.0, 2.0, 3.0].contains(data.imageScale) ? data.imageScale : 0.0
        request.options = options

        do {
            let task = try RenderTask(request: request)
            task.priority = .userInitiated
            task.completionHandler = { [weak self] image, error in
                let result: Result<UIImage, Swift.Error> = image.flatMap({ .success($0) }) ?? .failure(error ?? Error.imageNotAvailable)
                self?.queue.async {
                    self?.completeRequest(with: result, key: data.key, parentKey: data.parentKey, libraryId: data.libraryId, appearance: data.appearance, type: data.type)
                }
            }

            PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
        } catch let error {
            DDLogError("AnnotationPreviewController: can't create task - \(error)")
        }
    }

    private func completeRequest(with result: Result<UIImage, Swift.Error>, key: String, parentKey: String, libraryId: LibraryIdentifier, appearance: Appearance, type: PreviewType) {
        switch result {
        case .success(let image):
            switch type {
            case .temporary(let subscriberKey):
                perform(event: .success(image), subscriberKey: subscriberKey)

            case .cachedOnly:
                cache(image: image, key: key, pdfKey: parentKey, libraryId: libraryId, appearance: appearance)

            case .cachedAndReported:
                cache(image: image, key: key, pdfKey: parentKey, libraryId: libraryId, appearance: appearance)
                observable.on(.next((key, parentKey, image)))
            }

        case .failure(let error):
            DDLogError("AnnotationPreviewController: could not generate image - \(error)")

            switch type {
            case .temporary(let subscriberKey):
                // Temporary request always needs to return an error if image was not available
                perform(event: .failure(error), subscriberKey: subscriberKey)
                
            default:
                break
            }
        }
    }

    private func perform(event: SingleEvent<UIImage>, subscriberKey: SubscriberKey) {
        subscribers[subscriberKey]?(event)
        subscribers[subscriberKey] = nil
    }

    private func cache(image: UIImage, key: String, pdfKey: String, libraryId: LibraryIdentifier, appearance: Appearance) {
        autoreleasepool {
            guard let data = image.pngData() else {
                DDLogError("AnnotationPreviewController: can't create data from image")
                return
            }
            
            do {
                try fileStorage.write(data, to: Files.annotationPreview(annotationKey: key, pdfKey: pdfKey, libraryId: libraryId, appearance: appearance), options: .atomicWrite)
            } catch let error {
                DDLogError("AnnotationPreviewController: can't store preview - \(error)")
            }
        }
    }
}
