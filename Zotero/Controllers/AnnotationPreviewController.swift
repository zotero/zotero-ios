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

fileprivate struct SubscriberKey: Hashable {
    let key: String
    let parentKey: String
}

final class AnnotationPreviewController: NSObject {
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
    /// - parameter libraryId: Library identifier of item.
    /// - returns: `Single` with rendered image.
    func render(document: Document, page: PageIndex, rect: CGRect, key: String, parentKey: String, libraryId: LibraryIdentifier) -> Single<UIImage> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else { return Disposables.create() }

            self.queue.async(flags: .barrier) {
                self.subscribers[SubscriberKey(key: key, parentKey: parentKey)] = subscriber
            }

            self.enqueue(key: key, parentKey: parentKey, libraryId: libraryId, document: document, pageIndex: page, rect: rect, type: .temporary)

            return Disposables.create()
        }
    }

    /// Stores preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be cached.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    func store(for annotation: PSPDFKit.SquareAnnotation, parentKey: String, libraryId: LibraryIdentifier, isDark: Bool) {
        guard annotation.isImageAnnotation, let document = annotation.document else { return }

        // Cache and report original color
        let key = annotation.key ?? annotation.uuid
        let rect = annotation.previewBoundingBox
        self.enqueue(key: key, parentKey: parentKey, libraryId: libraryId, document: document, pageIndex: annotation.pageIndex,
                     rect: rect, invertColors: false, isDark: isDark, type: .cachedAndReported)
//        // If in dark mode, only cache light mode version, which is required for backend upload
//        if isDark {
//            self.enqueue(key: key, parentKey: parentKey, document: document, pageIndex: annotation.pageIndex, rect: rect,
//                         invertColors: true, isDark: !isDark, type: .cachedOnly)
//        }
    }

    /// Deletes cached preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be deleted.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    func delete(for annotation: PSPDFKit.SquareAnnotation, parentKey: String, libraryId: LibraryIdentifier) {
        guard annotation.isImageAnnotation else { return }

        let key = annotation.key ?? annotation.uuid
        self.queue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, isDark: true))
            try? self.fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey, libraryId: libraryId, isDark: false))
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
            guard let `self` = self else { return }

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
    /// - parameter invertColors: `true` if colors should be inverted, false otherwise.
    /// - parameter isDark: `true` if rendered image is in dark mode, `false` otherwise.
    /// - parameter type: Type of preview image. If `temporary`, requested image is temporary and is returned as `Single<UIImage>`. Otherwise image is
    ///                   cached locally and reported through `PublishSubject`.
    private func enqueue(key: String, parentKey: String, libraryId: LibraryIdentifier, document: Document, pageIndex: PageIndex, rect: CGRect, invertColors: Bool = false, isDark: Bool = false, type: PreviewType) {
        /*
         Workaround for PSPDFKit issue.

         The way these render options work is that they are applied on top of the original document page colors.

         So if the appearance mode of a PDFViewController is set to night mode and enabling invertRenderColor at that point for a render request of a document displayed in that PDFViewController
         will not result into reverting the rendering back to light mode. You will have to not enable invertRenderColor option when
         PDFViewController.appearanceModeManager.appearanceMode is set to night.

         However, even while setting invertRenderColor to false with the appearance mode set to night results in the rendering to be inverted. This should not be the case. So create a dummy document
         just for rendering and invert only when inverting from light to dark mode
         */
//        let newDoc = Document(url: document.fileURL!)

        let options = RenderOptions()
        options.skipAnnotationArray = document.annotations(at: pageIndex)
        // Color inversion disabled because of PSPDFKit rendering issues. It's not needed now, but just in case this is needed later let's keep it here.
//        options.invertRenderColor = !invertColors && isDark

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
            case .temporary:
                self.perform(event: .success(image), key: key, parentKey: parentKey)
            case .cachedOnly:
                self.cache(image: image, key: key, pdfKey: parentKey, libraryId: libraryId, isDark: isDark)
            case .cachedAndReported:
                self.cache(image: image, key: key, pdfKey: parentKey, libraryId: libraryId, isDark: isDark)
                self.observable.on(.next((key, parentKey, image)))
            }

        case .failure(let error):
            DDLogError("AnnotationPreviewController: could not generate image - \(error)")

            if type == .temporary {
                // Temporary request always needs to return an error if image was not available
                self.perform(event: .failure(error), key: key, parentKey: parentKey)
            }
        }
    }

    private func perform(event: SingleEvent<UIImage>, key: String, parentKey: String) {
        let key = SubscriberKey(key: key, parentKey: parentKey)
        self.subscribers[key]?(event)
        self.subscribers[key] = nil
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

#endif
