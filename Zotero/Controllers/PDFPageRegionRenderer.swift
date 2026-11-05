//
//  PDFPageRegionRenderer.swift
//  Zotero
//
//  Created by Michal Rentka on 29.09.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit

/// Renders regions of a PDF page as images. Used by standalone reading mode, where the reader displays the structured
/// text of a PDF it can't render itself and asks the app for the figures, equations and tables it should show inline.
protocol PDFPageRegionRenderer: AnyObject {
    /// - parameter pageIndex: Index of the rendered page.
    /// - parameter rects: Regions to render, in PDF page coordinates, each as `[minX, minY, maxX, maxY]`.
    /// - parameter scale: Requested resolution, in image pixels per PDF point.
    /// - parameter completion: Called with one image data URL per requested region, in the same order. A region which
    ///                         couldn't be rendered is reported as an empty string, so that the order is preserved.
    ///                         Called on a background queue, the images can be large and shouldn't be processed on the main thread.
    func renderPageRegions(pageIndex: Int, rects: [[Double]], scale: Double, completion: @escaping ([String]) -> Void)
}

final class PSPDFKitPageRegionRenderer: PDFPageRegionRenderer {
    private let document: PSPDFKit.Document
    /// Cap on a rendered region, so that a huge region or resolution can't produce an unreasonable image.
    private static let maximumPixelsPerSide: CGFloat = 3000
    /// Render tasks which were scheduled and haven't finished yet. They run on PSPDFKit's shared render queue, which outlives the reader, so they're
    /// cancelled when the renderer is released. Access is guarded by `tasksLock`, since `cancelRendering()` can be called from any thread.
    private var tasks: [ObjectIdentifier: RenderTask] = [:]
    private let tasksLock = NSLock()
    /// Render tasks report their results on the main thread. Encoding a large image takes long enough to block scrolling, so it's moved to this queue.
    private let encodingQueue = DispatchQueue(label: "org.zotero.PSPDFKitPageRegionRenderer.encoding", qos: .userInitiated, attributes: .concurrent)

    init(document: PSPDFKit.Document) {
        self.document = document
    }

    deinit {
        cancelRendering()
    }

    /// Cancels all scheduled render tasks. Their completions aren't reported.
    func cancelRendering() {
        tasksLock.lock()
        let tasks = Array(self.tasks.values)
        self.tasks.removeAll()
        tasksLock.unlock()
        guard !tasks.isEmpty else { return }
        DDLogInfo("PSPDFKitPageRegionRenderer: cancelling \(tasks.count) render tasks")
        for task in tasks {
            task.cancel()
        }
    }

    func renderPageRegions(pageIndex: Int, rects: [[Double]], scale: Double, completion: @escaping ([String]) -> Void) {
        guard !rects.isEmpty else {
            completion([])
            return
        }

        var images = [String](repeating: "", count: rects.count)
        // Render tasks complete on arbitrary threads, so the results are collected under a lock.
        let lock = NSLock()
        let group = DispatchGroup()

        for (index, rect) in rects.enumerated() {
            guard let request = createRequest(pageIndex: pageIndex, rect: rect, scale: scale) else { continue }

            do {
                let task = try RenderTask(request: request)
                task.priority = .userInitiated
                group.enter()
                let taskId = ObjectIdentifier(task)
                task.completionHandler = { [weak self] image, error in
                    guard let self else {
                        group.leave()
                        return
                    }
                    unregisterTask(with: taskId)
                    encodingQueue.async {
                        if let data = image?.pngData() {
                            let url = "data:image/png;base64,\(data.base64EncodedString())"
                            lock.lock()
                            images[index] = url
                            lock.unlock()
                        } else {
                            DDLogError("PSPDFKitPageRegionRenderer: could not render region \(index) of page \(pageIndex) - \(String(describing: error))")
                        }
                        group.leave()
                    }
                }
                registerTask(task, with: taskId)
                PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
            } catch let error {
                DDLogError("PSPDFKitPageRegionRenderer: can't create render task for region \(index) of page \(pageIndex) - \(error)")
            }
        }

        group.notify(queue: encodingQueue) {
            lock.lock()
            let result = images
            lock.unlock()
            completion(result)
        }
    }

    private func registerTask(_ task: RenderTask, with id: ObjectIdentifier) {
        tasksLock.lock()
        tasks[id] = task
        tasksLock.unlock()
    }

    private func unregisterTask(with id: ObjectIdentifier) {
        tasksLock.lock()
        tasks[id] = nil
        tasksLock.unlock()
    }

    private func createRequest(pageIndex: Int, rect: [Double], scale: Double) -> MutableRenderRequest? {
        guard pageIndex >= 0, pageIndex < document.pageCount, rect.count == 4, scale > 0 else {
            DDLogError("PSPDFKitPageRegionRenderer: invalid region request; page=\(pageIndex); rect=\(rect); scale=\(scale)")
            return nil
        }

        let page = PageIndex(pageIndex)
        let rawRect = CGRect(x: rect[0], y: rect[1], width: rect[2] - rect[0], height: rect[3] - rect[1])

        guard rawRect.width > 0, rawRect.height > 0 else {
            DDLogError("PSPDFKitPageRegionRenderer: empty region \(rect) of page \(pageIndex)")
            return nil
        }
        // The reader works in raw PDF coordinates, the same space annotations are stored in, while PSPDFKit renders in
        // normalized PDF coordinates. The conversion also applies the page rotation, so the converted rect is already
        // sized the way the region is rendered.
        guard let pdfRect = document.convertFromDb(rect: rawRect, page: page), pdfRect.width > 0, pdfRect.height > 0 else {
            DDLogError("PSPDFKitPageRegionRenderer: could not convert region \(rect) of page \(pageIndex)")
            return nil
        }

        // Keep the aspect ratio when the requested resolution would exceed the cap.
        let cappedScale = min(CGFloat(scale), Self.maximumPixelsPerSide / max(pdfRect.width, pdfRect.height))
        let imageSize = CGSize(width: (pdfRect.width * cappedScale).rounded(), height: (pdfRect.height * cappedScale).rounded())

        guard imageSize.width >= 1, imageSize.height >= 1 else {
            DDLogError("PSPDFKitPageRegionRenderer: region \(rect) of page \(pageIndex) is too small to render - \(imageSize)")
            return nil
        }

        let request = MutableRenderRequest(document: document)
        request.pageIndex = page
        request.pdfRect = pdfRect
        request.imageSize = imageSize
        // Regions are rendered at an exact pixel size, so the request must not scale them further.
        request.imageScale = 1
        // Reading mode renders the user's annotations itself, these images show the document only.
        request.annotations = []
        return request
    }
}
