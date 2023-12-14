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
    }

    struct SubscriberKey: Hashable {
        let key: String
        let libraryId: LibraryIdentifier
        let page: UInt
        let size: CGSize
        let isDark: Bool
    }

    private let queue: DispatchQueue
    private unowned let fileStorage: FileStorage

    private var subscribers: [SubscriberKey: (SingleEvent<UIImage>) -> Void]

    init(fileStorage: FileStorage) {
        self.fileStorage = fileStorage
        self.subscribers = [:]
        self.queue = DispatchQueue(label: "org.zotero.PdfThumbnailController.queue", qos: .userInitiated)
        super.init()
    }
}

// MARK: - PSPDFKit

extension PDFThumbnailController {
    /// Start rendering process of multiple thumbnails per document.
    /// - parameter pages: Page indices which should be rendered.
    /// - parameter 
    func cache(pages: [UInt], key: String, libraryId: LibraryIdentifier, document: Document, imageSize: CGSize, isDark: Bool) -> Observable<()> {
        let observables = pages.map({
            cache(page: $0, key: key, libraryId: libraryId, document: document, imageSize: imageSize, isDark: isDark).flatMap({ _ in return Single.just(()) }).asObservable()
        })
        return Observable.merge(observables)
    }

    func cache(page: UInt, key: String, libraryId: LibraryIdentifier, document: Document, imageSize: CGSize, isDark: Bool) -> Single<UIImage> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let self else { return Disposables.create() }
            let subscriberKey = SubscriberKey(key: key, libraryId: libraryId, page: page, size: imageSize, isDark: isDark)
            self.queue.async(flags: .barrier) { [weak self] in
                self?.subscribers[subscriberKey] = subscriber
            }
            self.enqueue(subscriberKey: subscriberKey, document: document, imageSize: imageSize)
            return Disposables.create()
        }
    }

    /// Deletes cached thumbnails for given PDF document.
    /// - parameter key: Attachment item key.
    /// - parameter libraryId: Library identifier of item.
    func deleteAll(forKey key: String, libraryId: LibraryIdentifier) {
        self.queue.async(flags: .barrier) { [weak self] in
            try? self?.fileStorage.remove(Files.pageThumbnails(for: key, libraryId: libraryId))
        }
    }

    /// Checks whether thumbnail is available for given page in document.
    /// - parameter page: Page index..
    /// - parameter key: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - returns: `true` if thumbnail is available, `false` otherwise.
    func hasThumbnail(page: UInt, key: String, libraryId: LibraryIdentifier, isDark: Bool) -> Bool {
        return fileStorage.has(Files.pageThumbnail(pageIndex: page, key: key, libraryId: libraryId, isDark: isDark))
    }

    /// Loads thumbnail from cached file
    /// - parameter page: Page index.
    /// - parameter key: Key of PDF item.
    /// - parameter libraryId: Library identifier of item.
    /// - parameter isDark: `true` if dark mode is on, `false` otherwise.
    /// - returns: UIImage of given page thumbnail.
    func thumbnail(page: UInt, key: String, libraryId: LibraryIdentifier, isDark: Bool) -> UIImage? {
        do {
            let data = try fileStorage.read(Files.pageThumbnail(pageIndex: page, key: key, libraryId: libraryId, isDark: isDark))
            return try UIImage(imageData: data)
        } catch let error {
            DDLogError("PdfThumbnailController: can't load thumbnail - \(error)")
            return nil
        }
    }

    /// Creates and enqueues a render request for PSPDFKit rendering engine.
    /// - parameter subscriberKey: Subscriber key identifying this request.
    /// - parameter document: Document to render.
    /// - parameter imageSize: Size of rendered image.
    private func enqueue(subscriberKey: SubscriberKey, document: Document, imageSize: CGSize) {
        let request = MutableRenderRequest(document: document)
        request.pageIndex = subscriberKey.page
        request.imageSize = imageSize
        request.options = RenderOptions()

        do {
            let task = try RenderTask(request: request)
            task.priority = .userInitiated
            task.completionHandler = { [weak self] image, error in
                let result: Result<UIImage, Swift.Error> = image.flatMap({ .success($0) }) ?? .failure(error ?? Error.imageNotAvailable)
                self?.queue.async(flags: .barrier) {
                    self?.completeRequest(with: result, subscriberKey: subscriberKey)
                }
            }
            PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
        } catch let error {
            DDLogError("PdfThumbnailController: can't create task - \(error)")
        }
    }

    private func completeRequest(with result: Result<UIImage, Swift.Error>, subscriberKey: SubscriberKey) {
        switch result {
        case .success(let image):
            perform(event: .success(image), subscriberKey: subscriberKey)
            cache(image: image, page: subscriberKey.page, key: subscriberKey.key, libraryId: subscriberKey.libraryId, isDark: subscriberKey.isDark)

        case .failure(let error):
            DDLogError("PdfThumbnailController: could not generate image - \(error)")
            perform(event: .failure(error), subscriberKey: subscriberKey)
        }

        func perform(event: SingleEvent<UIImage>, subscriberKey: SubscriberKey) {
            self.subscribers[subscriberKey]?(event)
            self.subscribers[subscriberKey] = nil
        }

        func cache(image: UIImage, page: UInt, key: String, libraryId: LibraryIdentifier, isDark: Bool) {
            guard let data = image.pngData() else {
                DDLogError("PdfThumbnailController: can't create data from image")
                return
            }
            do {
                try self.fileStorage.write(data, to: Files.pageThumbnail(pageIndex: page, key: key, libraryId: libraryId, isDark: isDark), options: .atomicWrite)
            } catch let error {
                DDLogError("PdfThumbnailController: can't store preview - \(error)")
            }
        }
    }
}
