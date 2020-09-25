//
//  SquareAnnotationPreviewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import RxSwift

typealias AnnotationPreviewUpdate = (annotationKey: String, pdfKey: String, image: UIImage)

fileprivate struct SubscriberKey: Hashable {
    let key: String
    let parentKey: String
}

class AnnotationPreviewController: NSObject {
    enum Error: Swift.Error {
        case imageNotAvailable
    }

    /// Type of annotation preview
    /// - temporary: Rendered image is returned by `Single<UIImage>` immediately, no caching is performed.
    /// - cachedAndReported: Rendered image is cached and reported through global observable `PublishSubject<AnnotationPreviewUpdate>`.
    /// - cachedOnly: Rendered image is only cached for later use.
    enum PreviewType: Int {
        case temporary
        case cachedAndReported
        case cachedOnly
    }

    let observable: PublishSubject<AnnotationPreviewUpdate>
    private let size: CGSize
    private let queue: DispatchQueue
    private let fileStorage: FileStorage

    private var subscribers: [SubscriberKey: (SingleEvent<UIImage>) -> Void]

    init(previewSize: CGSize, fileStorage: FileStorage) {
        self.size = previewSize
        self.fileStorage = fileStorage
        self.subscribers = [:]
        self.observable = PublishSubject()
        self.queue = DispatchQueue(label: "org.zotero.AnnotationPreviewController.queue", qos: .userInitiated)
        super.init()
    }
}

#if PDFENABLED

import PSPDFKit

// MARK: - PSPDFKit

extension AnnotationPreviewController {

    /// Renders part of document if it's not cached already and returns as `Single`. Does not write results to cache file.
    /// - parameter document: Document to render.
    /// - parameter page: Page of document to render.
    /// - parameter rect: Part of page of document to render.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of parent of annotation.
    /// - returns: `Single` with rendered image.
    func render(document: Document, page: PageIndex, rect: CGRect, key: String, parentKey: String) -> Single<UIImage> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else { return Disposables.create() }

            self.queue.async(flags: .barrier) {
                self.subscribers[SubscriberKey(key: key, parentKey: parentKey)] = subscriber
            }

            self.enqueue(key: key, parentKey: parentKey, document: document, pageIndex: page, rect: rect, type: .temporary)

            return Disposables.create()
        }
    }

    /// Stores preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be cached.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    func store(for annotation: SquareAnnotation, parentKey: String, isDark: Bool) {
        guard let key = annotation.key, let document = annotation.document else { return }

        // Cache and report original color
        let rect = annotation.boundingBox.insetBy(dx: (annotation.lineWidth + 1), dy: (annotation.lineWidth + 1))
        self.enqueue(key: key, parentKey: parentKey, document: document, pageIndex: annotation.pageIndex, rect: rect,
                     invertColors: false, isDark: isDark, type: .cachedAndReported)
        // If in dark mode, only cache light mode version, which is required for backend upload
        if isDark {
            self.enqueue(key: key, parentKey: parentKey, document: document, pageIndex: annotation.pageIndex, rect: rect,
                         invertColors: true, isDark: !isDark, type: .cachedOnly)
        }
    }

    /// Deletes cached preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be deleted.
    /// - parameter parentKey: Key of PDF item.
    func delete(for annotation: SquareAnnotation, parentKey: String) {
        guard let key = annotation.key else { return }

        self.queue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, isDark: true))
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, isDark: false))
        }
    }

    /// Checks whether preview is available for given annotation.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - returns: `true` if preview is available, `false` otherwise.
    func hasPreview(for key: String, parentKey: String, isDark: Bool) -> Bool {
        return self.fileStorage.has(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, isDark: isDark))
    }

    /// Loads cached preview for given annotation.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - parameter completed: Completion handler which contains loaded preview or `nil` if loading wasn't successful.
    func preview(for key: String, parentKey: String, isDark: Bool, completed: @escaping (UIImage?) -> Void) {
        self.queue.async { [weak self] in
            guard let `self` = self else { return }

            do {
                let data = try self.fileStorage.read(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, isDark: isDark))
                DispatchQueue.main.async {
                    completed(UIImage(data: data))
                }
            } catch let error {
                DDLogWarn("AnnotationPreviewController: can't read preview - \(error)")
                DispatchQueue.main.async {
                    completed(nil)
                }
            }
        }
    }

    /// Creates and enqueues a render request for PSPDFKit rendering engine.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of PDF item in which the annotation is stored.
    /// - parameter document: Document to render.
    /// - parameter pageIndex: Page to render.
    /// - parameter rect: Part of page to render.
    /// - parameter invertColors: `true` if colors should be inverted, false otherwise.
    /// - parameter isDark: `true` if rendered image is in dark mode, `false` otherwise.
    /// - parameter type: Type of preview image. If `temporary`, requested image is temporary and is returned as `Single<UIImage>`. Otherwise image is
    ///                   cached locally and reported through `PublishSubject`.
    private func enqueue(key: String, parentKey: String, document: Document, pageIndex: PageIndex, rect: CGRect, invertColors: Bool = false,
                         isDark: Bool = false, type: PreviewType) {
        let options = RenderOptions()
        options.skipAnnotationArray = document.annotations(at: pageIndex)
        if invertColors {
            if let invertFilter = CIFilter(name: "CIColorInvert") {
                options.additionalCIFilters = [invertFilter]
            }
//            options.filters = [.colorCorrectInverted]
        }
//        options.invertRenderColor = invertColors

        let request = MutableRenderRequest(document: document)
        request.imageSize = self.size
        request.pageIndex = pageIndex
        request.pdfRect = rect
        request.options = options

        do {
            let task = try RenderTask(request: request)
            task.priority = .userInitiated
            task.completionHandler = { [weak self] image, error in
                let result: Result<UIImage, Swift.Error> = image.flatMap({ .success($0) }) ?? .failure(error ?? Error.imageNotAvailable)
                self?.queue.async {
                    self?.completeRequest(with: result, key: key, parentKey: parentKey, isDark: isDark, type: type)
                }

            }

            PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
        } catch let error {
            DDLogError("AnnotationPreviewController: can't create task - \(error)")
        }
    }

    private func completeRequest(with result: Result<UIImage, Swift.Error>, key: String, parentKey: String, isDark: Bool, type: PreviewType) {
        switch result {
        case .success(let image):
            switch type {
            case .temporary:
                self.perform(event: .success(image), key: key, parentKey: parentKey)
            case .cachedOnly:
                self.cache(image: image, key: key, pdfKey: parentKey, isDark: isDark)
            case .cachedAndReported:
                self.cache(image: image, key: key, pdfKey: parentKey, isDark: isDark)
                self.observable.on(.next((key, parentKey, image)))
            }

        case .failure(let error):
            DDLogError("AnnotationPreviewController: could not generate image - \(error)")

            if type == .temporary {
                // Temporary request always needs to return an error if image was not available
                self.perform(event: .error(error), key: key, parentKey: parentKey)
            }
        }
    }

    private func perform(event: SingleEvent<UIImage>, key: String, parentKey: String) {
        let key = SubscriberKey(key: key, parentKey: parentKey)
        self.subscribers[key]?(event)
        self.subscribers[key] = nil
    }

    private func cache(image: UIImage, key: String, pdfKey: String, isDark: Bool) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            DDLogError("AnnotationPreviewController: can't create data from image")
            return
        }

        do {
            try self.fileStorage.write(data, to: Files.annotationPreview(annotationKey: key, pdfKey: pdfKey, isDark: isDark), options: .atomicWrite)
        } catch let error {
            DDLogError("AnnotationPreviewController: can't store preview - \(error)")
        }
    }
}

#endif
