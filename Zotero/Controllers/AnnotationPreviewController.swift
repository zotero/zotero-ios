//
//  SquareAnnotationPreviewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import Foundation

import CocoaLumberjack
import PSPDFKit

class AnnotationPreviewController: NSObject {
    private static let maxSize = CGSize(width: 200, height: 200)

    private let queue: DispatchQueue
    private let fileStorage: FileStorage

    init(fileStorage: FileStorage) {
        self.queue = DispatchQueue(label: "org.zotero.AnnotationPreviewController.queue", qos: .userInitiated)
        self.fileStorage = fileStorage
        super.init()
    }

    func cache(key: String, document: Document, documentKey: String, pageIndex: PageIndex, rect: CGRect) {
        self.queue.async { [weak self] in
            self?._cache(key: key, document: document, documentKey: documentKey, pageIndex: pageIndex, rect: rect)
        }
    }

    private func _cache(key: String, document: Document, documentKey: String, pageIndex: PageIndex, rect: CGRect) {
        guard !self.fileStorage.has(Files.annotationPreview(key: key, documentKey: documentKey)) else { return }

    }

    private func enqueue(id: String, document: Document, pageIndex: PageIndex, rect: CGRect) {
        let request = MutableRenderRequest(document: document)
        request.imageSize = AnnotationPreviewController.maxSize
        request.pageIndex = pageIndex
        request.pdfRect = rect
        request.userInfo["id"] = id

        do {
            let task = try RenderTask(request: request)
            task.priority = .utility
            task.delegate = self

            PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
        } catch let error {
            DDLogError("AnnotationPreviewController: can't create task - \(error)")
        }
    }
}

extension AnnotationPreviewController: RenderTaskDelegate {
    func renderTaskDidFinish(_ task: RenderTask) {
        guard let image = task.image else { return }
    }

    func renderTask(_ task: RenderTask, didFailWithError error: Error) {

    }
}

#endif
