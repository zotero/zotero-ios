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

class AnnotationPreviewController: NSObject {
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

            self.enqueue(key: key, parentKey: parentKey, document: document, pageIndex: page, rect: rect, temporary: true)

            return Disposables.create()
        }
    }

    /// Stores preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be cached.
    /// - parameter parentKey: Key of PDF item.
    func store(for annotation: SquareAnnotation, parentKey: String) {
        guard let key = annotation.key, let document = annotation.document else { return }
        self.enqueue(key: key,
                     parentKey: parentKey,
                     document: document,
                     pageIndex: annotation.pageIndex,
                     rect: annotation.boundingBox.insetBy(dx: (annotation.lineWidth + 1), dy: (annotation.lineWidth + 1)),
                     temporary: false)
    }

    /// Deletes cached preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be deleted.
    /// - parameter parentKey: Key of PDF item.
    func delete(for annotation: SquareAnnotation, parentKey: String) {
        guard let key = annotation.key else { return }

        self.queue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }

            do {
                try self.fileStorage.remove(Files.annotationPreview(annotationKey: key, pdfKey: parentKey))
            } catch let error {
                DDLogError("AnnotationPreviewController: can't remove file - \(error)")
            }
        }
    }

    /// Loads cached preview for given annotation.
    /// - parameter key: Key of annotation.
    /// - parameter parentKey: Key of PDF item.
    /// - parameter completed: Completion handler which contains loaded preview or `nil` if loading wasn't successful.
    func preview(for key: String, parentKey: String, completed: @escaping (UIImage?) -> Void) {
        self.queue.async { [weak self] in
            guard let `self` = self else { return }

            do {
                let data = try self.fileStorage.read(Files.annotationPreview(annotationKey: key, pdfKey: parentKey))
                DispatchQueue.main.async {
                    completed(UIImage(data: data))
                }
            } catch let error {
                DDLogError("AnnotationPreviewController: can't read preview - \(error)")
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
    /// - parameter temporary: True if requested image is temporary and is returned as `Single<UIImage>`. False when image should be cached and
    ///                        reported globally with PublishSubject.
    private func enqueue(key: String, parentKey: String, document: Document, pageIndex: PageIndex, rect: CGRect, temporary: Bool) {
        let request = MutableRenderRequest(document: document)
        request.imageSize = self.size
        request.pageIndex = pageIndex
        request.pdfRect = rect
        request.userInfo["key"] = key
        request.userInfo["parentKey"] = parentKey
        request.userInfo["temporary"] = temporary

        do {
            let task = try RenderTask(request: request)
            task.priority = .userInitiated
            task.delegate = self

            PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
        } catch let error {
            DDLogError("AnnotationPreviewController: can't create task - \(error)")
        }
    }

    private func perform(event: SingleEvent<UIImage>, key: String, parentKey: String) {
        let key = SubscriberKey(key: key, parentKey: parentKey)
        self.subscribers[key]?(event)
        self.subscribers[key] = nil
    }
}

// MARK: - Render delegate

extension AnnotationPreviewController: RenderTaskDelegate {
    func renderTaskDidFinish(_ task: RenderTask) {
        guard let key = task.request.userInfo["key"] as? String,
              let parentKey = task.request.userInfo["parentKey"] as? String,
              let temporary = task.request.userInfo["temporary"] as? Bool,
              let image = task.image else {
            DDLogInfo("AnnotationPreviewController: missing task info - key: \(task.request.userInfo["key"] ?? "")" +
                      "; parentKey: \(task.request.userInfo["parentKey"] ?? ""); image: \(task.image?.size ?? CGSize())")
            return
        }

        self.queue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }

            if temporary {
                // If image is temporary it's returned as `Single<UIImage>`, so find its subscriber and report image.
                self.perform(event: .success(image), key: key, parentKey: parentKey)
                return
            }

            // If image is not temporary, cache it and report globally.
            self.observable.on(.next((key, parentKey, image)))

            do {
                if let data = image.jpegData(compressionQuality: 0.8) {
                    try self.fileStorage.write(data, to: Files.annotationPreview(annotationKey: key, pdfKey: parentKey), options: .atomicWrite)
                }
            } catch let error {
                DDLogError("AnnotationPreviewController: can't store preview - \(error)")
            }
        }
    }

    func renderTask(_ task: RenderTask, didFailWithError error: Error) {
        DDLogError("AnnotationPreviewController: could not generate image - \(error)")

        // Report failure for temporary render requests.
        guard let key = task.request.userInfo["key"] as? String,
              let parentKey = task.request.userInfo["parentKey"] as? String,
              let temporary = task.request.userInfo["temporary"] as? Bool, temporary else { return }

        self.queue.async(flags: .barrier) { [weak self] in
            self?.perform(event: .error(error), key: key, parentKey: parentKey)
        }
    }
}

#endif
