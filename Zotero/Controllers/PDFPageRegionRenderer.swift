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
    /// Regions requested together. They're reported together when all of their render tasks finish, or not at all when they're cancelled.
    private final class Batch {
        let group = DispatchGroup()
        private let lock = NSLock()
        private var images: [String]
        private var isCancelled = false

        init(count: Int) {
            images = [String](repeating: "", count: count)
        }

        func set(image: String, at index: Int) {
            lock.lock()
            images[index] = image
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            lock.unlock()
        }

        /// Rendered images, `nil` if the batch was cancelled.
        var result: [String]? {
            lock.lock()
            defer { lock.unlock() }
            return isCancelled ? nil : images
        }
    }

    private let document: PSPDFKit.Document
    /// Cap on a rendered region, so that a huge region or resolution can't produce an unreasonable image.
    private static let maximumPixelsPerSide: CGFloat = 3000
    /// Render tasks which were scheduled and haven't finished yet, with the batch they belong to. They run on PSPDFKit's shared render queue, which
    /// outlives the reader, so they're cancelled when the renderer is released. Each task holds its batch's dispatch group entered until it's removed from
    /// here, either by its completion handler or by `cancelRendering()`, so that whichever removes it leaves the group exactly once. Access is guarded by
    /// `tasksLock`, since `cancelRendering()` can be called from any thread.
    private var tasks: [ObjectIdentifier: (task: RenderTask, batch: Batch)] = [:]
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
        let entries = Array(tasks.values)
        tasks.removeAll()
        tasksLock.unlock()
        guard !entries.isEmpty else { return }
        DDLogInfo("PSPDFKitPageRegionRenderer: cancelling \(entries.count) render tasks")
        for (task, batch) in entries {
            task.cancel()
            // PSPDFKit doesn't call the completion handler of a cancelled task, so its batch is finished here.
            batch.cancel()
            batch.group.leave()
        }
    }

    func renderPageRegions(pageIndex: Int, rects: [[Double]], scale: Double, completion: @escaping ([String]) -> Void) {
        guard !rects.isEmpty else {
            completion([])
            return
        }

        let batch = Batch(count: rects.count)

        for (index, rect) in rects.enumerated() {
            guard let request = createRequest(pageIndex: pageIndex, rect: rect, scale: scale) else { continue }

            do {
                let task = try RenderTask(request: request)
                task.priority = .userInitiated
                let taskId = ObjectIdentifier(task)
                task.completionHandler = { [weak self] image, error in
                    // The task is missing when it was cancelled, its batch is already finished then.
                    guard let self, takeTask(with: taskId) != nil else { return }
                    encodingQueue.async {
                        if let data = image?.pngData() {
                            batch.set(image: "data:image/png;base64,\(data.base64EncodedString())", at: index)
                        } else {
                            DDLogError("PSPDFKitPageRegionRenderer: could not render region \(index) of page \(pageIndex) - \(String(describing: error))")
                        }
                        batch.group.leave()
                    }
                }
                batch.group.enter()
                register(task: task, batch: batch, with: taskId)
                PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
            } catch let error {
                DDLogError("PSPDFKitPageRegionRenderer: can't create render task for region \(index) of page \(pageIndex) - \(error)")
            }
        }

        batch.group.notify(queue: encodingQueue) {
            guard let result = batch.result else { return }
            completion(result)
        }
    }

    private func register(task: RenderTask, batch: Batch, with id: ObjectIdentifier) {
        tasksLock.lock()
        tasks[id] = (task, batch)
        tasksLock.unlock()
    }

    /// Removes a task which finished. Returns `nil` if it was already removed by `cancelRendering()`.
    private func takeTask(with id: ObjectIdentifier) -> (task: RenderTask, batch: Batch)? {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return tasks.removeValue(forKey: id)
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
