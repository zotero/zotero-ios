//
//  SquareAnnotationPreviewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import CocoaLumberjack
import PSPDFKit
import RxSwift

typealias AnnotationPreviewUpdate = (annotationKey: String, pdfKey: String, image: UIImage)

class AnnotationPreviewController: NSObject {
    private static let maxSize = CGSize(width: 200, height: 200)

    let observable: PublishSubject<AnnotationPreviewUpdate>
    private let queue: DispatchQueue
    private let fileStorage: FileStorage

    init(fileStorage: FileStorage) {
        self.observable = PublishSubject()
        self.queue = DispatchQueue(label: "org.zotero.AnnotationPreviewController.queue", qos: .userInitiated)
        self.fileStorage = fileStorage
        super.init()
    }

    /// Stores preview for given annotation if there is no existing preview.
    /// - parameter annotation: Area annotation for which the preview is to be cached.
    /// - parameter parentKey: Key of PDF item. 
    func storeIfNeeded(for annotation: SquareAnnotation, parentKey: String) {
        guard let key = annotation.key, !self.fileStorage.has(Files.annotationPreview(annotationKey: key, pdfKey: parentKey)) else { return }
        self.store(for: annotation, parentKey: parentKey)
    }

    /// Stores preview for given annotation.
    /// - parameter annotation: Area annotation for which the preview is to be cached.
    /// - parameter parentKey: Key of PDF item.
    func store(for annotation: SquareAnnotation, parentKey: String) {
        guard let key = annotation.key, let document = annotation.document else { return }
        self.enqueue(key: key, parentKey: parentKey, document: document, pageIndex: annotation.pageIndex, rect: annotation.boundingBox)
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
    private func enqueue(key: String, parentKey: String, document: Document, pageIndex: PageIndex, rect: CGRect) {
        let request = MutableRenderRequest(document: document)
        request.imageSize = AnnotationPreviewController.maxSize
        request.pageIndex = pageIndex
        request.pdfRect = rect
        request.userInfo["key"] = key
        request.userInfo["parentKey"] = parentKey

        do {
            let task = try RenderTask(request: request)
            task.priority = .userInitiated
            task.delegate = self

            PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
        } catch let error {
            DDLogError("AnnotationPreviewController: can't create task - \(error)")
        }
    }
}

extension AnnotationPreviewController: RenderTaskDelegate {
    func renderTaskDidFinish(_ task: RenderTask) {

        guard let key = task.request.userInfo["key"] as? String,
              let parentKey = task.request.userInfo["parentKey"] as? String,
              let image = task.image else {
            DDLogInfo("AnnotationPreviewController: missing task info - key: \(task.request.userInfo["key"] ?? "")" +
                      "; parentKey: \(task.request.userInfo["parentKey"] ?? ""); image: \(task.image?.size ?? CGSize())")
            return
        }

        self.queue.async(flags: .barrier) { [weak self] in
            guard let `self` = self, let data = image.jpegData(compressionQuality: 0.8) else { return }

            do {
                try self.fileStorage.write(data, to: Files.annotationPreview(annotationKey: key, pdfKey: parentKey), options: .atomicWrite)
                self.observable.on(.next((key, parentKey, image)))
            } catch let error {
                DDLogError("AnnotationPreviewController: can't store preview - \(error)")
            }
        }
    }

    func renderTask(_ task: RenderTask, didFailWithError error: Error) {
        DDLogError("AnnotationPreviewController: could not generate image - \(error)")
    }
}

#endif
