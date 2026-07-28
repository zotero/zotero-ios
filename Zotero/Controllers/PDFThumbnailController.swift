//
//  PDFThumbnailController.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import PSPDFKit
import RxSwift

final class PDFThumbnailController: NSObject {
    enum Error: Swift.Error {
        case imageNotAvailable
        case invalidImageData
    }

    private struct DocumentKey: Hashable {
        let key: String
        let libraryId: LibraryIdentifier
    }

    fileprivate struct RequestKey: Hashable {
        let key: String
        let libraryId: LibraryIdentifier
        let page: UInt
        let size: CGSize
        let appearance: Appearance
    }

    struct Request {
        enum Priority: Int {
            case prefetch
            case visible
        }

        fileprivate let key: RequestKey
        fileprivate let document: Document
        fileprivate var priority: Priority
    }

    private enum DiskLoadResult {
        case image(UIImage)
        case notFound
        case unreadable(Swift.Error)
    }

    private struct Entry {
        enum State {
            case loadingFromDisk
            case rendering(RenderTask)
            case savingToDisk(UIImage)
        }

        let id: UUID
        var request: Request
        var state: State
        var subscribers: [UUID: (SingleEvent<UIImage>) -> Void]
    }

    private let accessQueue: DispatchQueue
    private let accessQueueKey: DispatchSpecificKey<Void>
    private let ioQueue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let fileStorage: FileStorage

    private var entries: [RequestKey: Entry]
    private var activeSessionCounts: [DocumentKey: Int]

    init(fileStorage: FileStorage) {
        accessQueue = DispatchQueue(label: "org.zotero.PDFThumbnailController.accessQueue", qos: .default)
        accessQueueKey = DispatchSpecificKey<Void>()
        accessQueue.setSpecific(key: accessQueueKey, value: ())
        ioQueue = DispatchQueue(label: "org.zotero.PDFThumbnailController.ioQueue", qos: .default)
        scheduler = SerialDispatchQueueScheduler(queue: accessQueue, internalSerialQueueName: "org.zotero.PDFThumbnailController.scheduler")
        self.fileStorage = fileStorage
        entries = [:]
        activeSessionCounts = [:]
        super.init()
    }
}

// MARK: - PSPDFKit

extension PDFThumbnailController {
    private func performOnAccessQueue<Result>(_ work: () -> Result) -> Result {
        if DispatchQueue.getSpecific(key: accessQueueKey) != nil {
            return work()
        }
        return accessQueue.sync(execute: work)
    }

    func start(forKey key: String, libraryId: LibraryIdentifier) {
        performOnAccessQueue {
            let documentKey = DocumentKey(key: key, libraryId: libraryId)
            activeSessionCounts[documentKey, default: 0] += 1
        }
    }

    func stop(forKey key: String, libraryId: LibraryIdentifier) {
        accessQueue.async { [weak self] in
            guard let self else { return }

            let documentKey = DocumentKey(key: key, libraryId: libraryId)
            guard activeSessionCounts[documentKey, default: 0] > 0 else {
                DDLogWarn("PDFThumbnailController: ignored stop without active session; key=\(key); library=\(libraryId)")
                return
            }
            activeSessionCounts[documentKey, default: 0] -= 1

            guard activeSessionCounts[documentKey, default: 0] == 0 else { return }
            deleteDiskCache(for: documentKey)
        }
    }

    /// Loads a thumbnail from disk or renders and caches it if needed. Concurrent requests for the same thumbnail share one operation.
    func thumbnail(
        page: UInt,
        key: String,
        libraryId: LibraryIdentifier,
        document: Document,
        imageSize: CGSize,
        appearance: Appearance,
        priority: Request.Priority
    ) -> Single<UIImage> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let self else { return Disposables.create() }

            let requestKey = RequestKey(key: key, libraryId: libraryId, page: page, size: imageSize, appearance: appearance)
            let subscriberId = UUID()
            performOnAccessQueue {
                add(
                    subscriber: subscriber,
                    id: subscriberId,
                    request: Request(key: requestKey, document: document, priority: priority)
                )
            }

            return Disposables.create { [weak self] in
                self?.accessQueue.async { [weak self] in
                    self?.removeSubscriber(with: subscriberId, requestKey: requestKey)
                }
            }
        }
        .subscribe(on: scheduler)

        func add(subscriber: @escaping (SingleEvent<UIImage>) -> Void, id subscriberId: UUID, request: Request) {
            let documentKey = DocumentKey(key: request.key.key, libraryId: request.key.libraryId)
            guard (activeSessionCounts[documentKey, default: 0]) > 0 else {
                DDLogWarn("PDFThumbnailController: ignored request without active session; key=\(request.key.key); library=\(request.key.libraryId); page=\(request.key.page)")
                return
            }

            if var entry = entries[request.key] {
                switch entry.state {
                case .loadingFromDisk:
                    promote(&entry, to: request.priority)
                    entry.subscribers[subscriberId] = subscriber
                    entries[request.key] = entry

                case .rendering:
                    promote(&entry, to: request.priority)
                    entry.subscribers[subscriberId] = subscriber
                    entries[request.key] = entry

                case .savingToDisk(let image):
                    subscriber(.success(image))
                }
                return
            }

            let entry = Entry(
                id: UUID(),
                request: request,
                state: .loadingFromDisk,
                subscribers: [subscriberId: subscriber]
            )
            entries[request.key] = entry
            loadFromDisk(requestKey: request.key, entryId: entry.id)

            func promote(_ entry: inout Entry, to priority: Request.Priority) {
                guard priority.rawValue > entry.request.priority.rawValue else { return }
                entry.request.priority = priority
                if case .rendering(let task) = entry.state {
                    task.priority = .userInitiated
                }
            }

            func loadFromDisk(requestKey: RequestKey, entryId: UUID) {
                ioQueue.async { [weak self] in
                    guard let self else { return }

                    let file = Files.pageThumbnail(
                        pageIndex: requestKey.page,
                        key: requestKey.key,
                        libraryId: requestKey.libraryId,
                        appearance: requestKey.appearance
                    )
                    let result: DiskLoadResult
                    if fileStorage.has(file) {
                        do {
                            let data = try fileStorage.read(file)
                            if let image = UIImage(data: data) {
                                result = .image(image)
                            } else {
                                result = .unreadable(Error.invalidImageData)
                            }
                        } catch let error {
                            result = .unreadable(error)
                        }
                    } else {
                        result = .notFound
                    }
                    accessQueue.async { [weak self] in
                        self?.completeDiskLoad(with: result, requestKey: requestKey, entryId: entryId)
                    }
                }
            }
        }
    }

    /// Deletes cached thumbnails for given PDF document.
    /// - parameter key: Attachment item key.
    /// - parameter libraryId: Library identifier of item.
    func deleteAll(forKey key: String, libraryId: LibraryIdentifier) {
        accessQueue.async { [weak self] in
            guard let self else { return }

            let documentKey = DocumentKey(key: key, libraryId: libraryId)
            deleteDiskCache(for: documentKey)
        }
    }

    /// Deletes cached thumbnails for specific pages of a PDF document.
    /// - parameter pages: Page indices to delete.
    /// - parameter key: Attachment item key.
    /// - parameter libraryId: Library identifier of item.
    func delete(pages: Set<Int>, forKey key: String, libraryId: LibraryIdentifier) {
        let pageIndices = Set(pages.compactMap({ UInt(exactly: $0) }))
        guard !pageIndices.isEmpty else { return }

        accessQueue.async { [weak self] in
            guard let self else { return }

            let requestKeys = entries.keys.filter({
                $0.key == key && $0.libraryId == libraryId && pageIndices.contains($0.page)
            })
            for requestKey in requestKeys {
                if case .rendering(let task) = entries[requestKey]?.state {
                    task.cancel()
                }
                entries[requestKey] = nil
            }

            ioQueue.async { [weak self] in
                guard let self else { return }

                for page in pageIndices {
                    for appearance in [Appearance.light, .dark, .sepia] {
                        do {
                            try fileStorage.remove(
                                Files.pageThumbnail(
                                    pageIndex: page,
                                    key: key,
                                    libraryId: libraryId,
                                    appearance: appearance
                                )
                            )
                        } catch {
                            DDLogError("PDFThumbnailController: can't delete cached page thumbnail; key=\(key); library=\(libraryId); page=\(page); appearance=\(appearance); error=\(error)")
                        }
                    }
                }
            }
        }
    }

    private func removeSubscriber(with subscriberId: UUID, requestKey: RequestKey) {
        guard var entry = entries[requestKey], entry.subscribers.removeValue(forKey: subscriberId) != nil else { return }
        guard entry.subscribers.isEmpty else {
            entries[requestKey] = entry
            return
        }

        if case .rendering(let task) = entry.state {
            task.cancel()
        }
        entries[requestKey] = nil
    }

    private func deleteDiskCache(for documentKey: DocumentKey) {
        // First invalidate any pending entries.
        let requestKeys = entries.keys.filter({
            $0.key == documentKey.key && $0.libraryId == documentKey.libraryId
        })

        for requestKey in requestKeys {
            guard let entry = entries[requestKey] else { continue }

            if case .rendering(let task) = entry.state {
                task.cancel()
            }
            entries[requestKey] = nil
        }

        ioQueue.async { [weak self] in
            guard let self else { return }

            let thumbnails = Files.pageThumbnails(for: documentKey.key, libraryId: documentKey.libraryId)
            guard fileStorage.has(thumbnails) else { return }
            do {
                try fileStorage.remove(thumbnails)
            } catch {
                DDLogError("PDFThumbnailController: can't delete disk cache; key=\(documentKey.key); library=\(documentKey.libraryId); error=\(error)")
            }
        }
    }

    private func completeDiskLoad(with result: DiskLoadResult, requestKey: RequestKey, entryId: UUID) {
        guard let entry = entries[requestKey], entry.id == entryId else { return }

        switch result {
        case .image(let image):
            entries[requestKey] = nil
            perform(event: .success(image), subscribers: entry.subscribers)

        case .notFound:
            enqueue(entry: entry)

        case .unreadable(let error):
            DDLogWarn("PDFThumbnailController: can't load cached thumbnail; key=\(requestKey.key); library=\(requestKey.libraryId); page=\(requestKey.page); error=\(error)")
            ioQueue.async { [weak self] in
                guard let self else { return }
                try? fileStorage.remove(
                    Files.pageThumbnail(
                        pageIndex: requestKey.page,
                        key: requestKey.key,
                        libraryId: requestKey.libraryId,
                        appearance: requestKey.appearance
                    )
                )
            }
            enqueue(entry: entry)
        }
    }

    /// Creates and enqueues a render request for PSPDFKit rendering engine.
    /// - parameter entry: Entry identifying this request and its subscribers.
    private func enqueue(entry: Entry) {
        let options = RenderOptions()
        switch entry.request.key.appearance {
        case .dark:
            options.invertRenderColor = true
            options.filters = [.colorCorrectInverted]

        case .sepia:
            options.filters = [.sepia]

        case .light:
            break
        }

        let request = MutableRenderRequest(document: entry.request.document)
        request.pageIndex = entry.request.key.page
        request.imageSize = entry.request.key.size
        request.options = options

        do {
            let task = try RenderTask(request: request)
            task.priority = entry.request.priority == .visible ? .userInitiated : .utility
            task.completionHandler = { [weak self] image, error in
                let result: Result<UIImage, Swift.Error> = image.flatMap({ .success($0) }) ?? .failure(error ?? Error.imageNotAvailable)
                self?.accessQueue.async {
                    self?.completeRender(with: result, requestKey: entry.request.key, entryId: entry.id)
                }
            }
            var updatedEntry = entry
            updatedEntry.state = .rendering(task)
            entries[entry.request.key] = updatedEntry
            PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
        } catch let error {
            DDLogError("PDFThumbnailController: can't create render task; key=\(entry.request.key.key); library=\(entry.request.key.libraryId); page=\(entry.request.key.page); error=\(error)")
            entries[entry.request.key] = nil
            perform(event: .failure(error), subscribers: entry.subscribers)
        }
    }

    private func completeRender(with result: Result<UIImage, Swift.Error>, requestKey: RequestKey, entryId: UUID) {
        guard var entry = entries[requestKey], entry.id == entryId else { return }

        switch result {
        case .success(let image):
            let subscribers = entry.subscribers
            entry.state = .savingToDisk(image)
            entry.subscribers.removeAll()
            entries[requestKey] = entry
            perform(event: .success(image), subscribers: subscribers)
            cache(image: image, requestKey: requestKey, entryId: entryId)

        case .failure(let error):
            DDLogError("PDFThumbnailController: could not generate image; key=\(requestKey.key); library=\(requestKey.libraryId); page=\(requestKey.page); error=\(error)")
            entries[requestKey] = nil
            perform(event: .failure(error), subscribers: entry.subscribers)
        }
    }

    private func perform(event: SingleEvent<UIImage>, subscribers: [UUID: (SingleEvent<UIImage>) -> Void]) {
        subscribers.values.forEach { $0(event) }
    }

    private func cache(image: UIImage, requestKey: RequestKey, entryId: UUID) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard performOnAccessQueue({ [weak self] in self?.entries[requestKey]?.id == entryId }) else {
                return
            }
            autoreleasepool { [weak self] in
                guard let self else { return }
                guard let data = image.pngData() else {
                    DDLogError("PDFThumbnailController: can't create image data; key=\(requestKey.key); library=\(requestKey.libraryId); page=\(requestKey.page)")
                    return
                }
                do {
                    try fileStorage.write(
                        data,
                        to: Files.pageThumbnail(
                            pageIndex: requestKey.page,
                            key: requestKey.key,
                            libraryId: requestKey.libraryId,
                            appearance: requestKey.appearance
                        ),
                        options: .atomicWrite
                    )
                } catch let error {
                    DDLogError("PDFThumbnailController: can't store thumbnail; key=\(requestKey.key); library=\(requestKey.libraryId); page=\(requestKey.page); error=\(error)")
                }
            }
            accessQueue.async { [weak self] in
                guard let self, let entry = entries[requestKey], entry.id == entryId else { return }
                entries[requestKey] = nil
            }
        }
    }
}
