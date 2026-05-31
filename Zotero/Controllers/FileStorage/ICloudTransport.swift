//
//  ICloudTransport.swift
//  Zotero
//
//  Created by Claude on 30.05.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

/// Low-level helper that talks to the app's iCloud Drive ubiquitous container. All container I/O is funnelled through `NSFileCoordinator`
/// to avoid racing the iCloud sync daemon, and evicted file contents are materialized with `startDownloadingUbiquitousItem` + `NSMetadataQuery`.
///
/// This type is intentionally transport-only: it knows nothing about `<key>.zip`/`<key>.prop` semantics, mtime/hash, or the Zotero API. That
/// lives in `ICloudController`.
protocol ICloudTransport: AnyObject {
    /// Whether an iCloud account is signed in on the device.
    var isAccountAvailable: Bool { get }

    /// Resolves the `Documents/storage` directory inside the ubiquity container, creating it if needed. Blocking — must be called off the main thread.
    func storageDirectory() throws -> URL
    /// Container URL for `name` (e.g. `<KEY>.zip`) inside `Documents/storage`.
    func url(forItemNamed name: String) throws -> URL
    /// Whether the item's contents are present locally (not an evicted placeholder).
    func isDownloaded(name: String) -> Bool
    /// Coordinated write of `data` to `name` (replacing any existing item).
    func write(data: Data, toItemNamed name: String) -> Single<()>
    /// Coordinated read of `name`. Emits `nil` when the item doesn't exist.
    func readData(fromItemNamed name: String) -> Single<Data?>
    /// Coordinated copy of a local file into the container as `name` (replacing any existing item).
    func copy(localFile: URL, toItemNamed name: String) -> Single<()>
    /// Coordinated copy of container item `name` out to a local file (replacing any existing local file). Item must already be materialized.
    func copyItem(named name: String, to localFile: URL) -> Single<()>
    /// Materializes an evicted item, emitting download `Progress` and completing once contents are present.
    func materialize(name: String, queue: DispatchQueue) -> Observable<Progress>
    /// Coordinated removal of `name` (and its placeholder, if any). Reports whether the item existed.
    func remove(itemNamed name: String) -> Single<Bool>
    /// Enumerates item names (logical, e.g. `<KEY>.zip`) currently present in `Documents/storage`.
    func listItemNames() -> Single<[String]>
}

final class ICloudTransportController: ICloudTransport {
    enum Error: Swift.Error {
        case containerUnavailable
        case accountUnavailable
        case materializationTimeout
        case coordination(NSError)
    }

    static let containerIdentifier = "iCloud.org.zotero.ios.Zotero"
    private static let materializationTimeout: DispatchTimeInterval = .seconds(120)

    private let containerIdentifier: String?

    init(containerIdentifier: String? = ICloudTransportController.containerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    var isAccountAvailable: Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    func storageDirectory() throws -> URL {
        guard isAccountAvailable else { throw Error.accountUnavailable }
        // `url(forUbiquityContainerIdentifier:)` is blocking and must run off the main thread.
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw Error.containerUnavailable
        }
        let storage = base.appendingPathComponent("Documents/storage", isDirectory: true)
        if !FileManager.default.fileExists(atPath: storage.path) {
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        }
        return storage
    }

    func url(forItemNamed name: String) throws -> URL {
        return try storageDirectory().appendingPathComponent(name)
    }

    func isDownloaded(name: String) -> Bool {
        guard let url = try? url(forItemNamed: name) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = values?.ubiquitousItemDownloadingStatus {
            return status == .current
        }
        // Non-ubiquitous (or attribute unavailable) but file exists on disk.
        return true
    }

    func write(data: Data, toItemNamed name: String) -> Single<()> {
        return Single.create { [weak self] subscriber in
            guard let self else { return Disposables.create() }
            do {
                let url = try url(forItemNamed: name)
                try coordinatedWrite(to: url, options: .forReplacing) { coordinatedUrl in
                    try data.write(to: coordinatedUrl, options: .atomic)
                }
                subscriber(.success(()))
            } catch let error {
                DDLogError("ICloudTransport: can't write \(name) - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    func readData(fromItemNamed name: String) -> Single<Data?> {
        return Single.create { [weak self] subscriber in
            guard let self else { return Disposables.create() }
            do {
                let url = try url(forItemNamed: name)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    subscriber(.success(nil))
                    return Disposables.create()
                }
                var result: Data?
                try coordinatedRead(at: url) { coordinatedUrl in
                    result = try Data(contentsOf: coordinatedUrl)
                }
                subscriber(.success(result))
            } catch let error {
                DDLogError("ICloudTransport: can't read \(name) - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    func copy(localFile: URL, toItemNamed name: String) -> Single<()> {
        return Single.create { [weak self] subscriber in
            guard let self else { return Disposables.create() }
            do {
                let url = try url(forItemNamed: name)
                try coordinatedWrite(to: url, options: .forReplacing) { coordinatedUrl in
                    if FileManager.default.fileExists(atPath: coordinatedUrl.path) {
                        try FileManager.default.removeItem(at: coordinatedUrl)
                    }
                    try FileManager.default.copyItem(at: localFile, to: coordinatedUrl)
                }
                subscriber(.success(()))
            } catch let error {
                DDLogError("ICloudTransport: can't copy into \(name) - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    func copyItem(named name: String, to localFile: URL) -> Single<()> {
        return Single.create { [weak self] subscriber in
            guard let self else { return Disposables.create() }
            do {
                let url = try url(forItemNamed: name)
                try coordinatedRead(at: url) { coordinatedUrl in
                    if FileManager.default.fileExists(atPath: localFile.path) {
                        try FileManager.default.removeItem(at: localFile)
                    }
                    try FileManager.default.copyItem(at: coordinatedUrl, to: localFile)
                }
                subscriber(.success(()))
            } catch let error {
                DDLogError("ICloudTransport: can't copy out \(name) - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    func remove(itemNamed name: String) -> Single<Bool> {
        return Single.create { [weak self] subscriber in
            guard let self else { return Disposables.create() }
            do {
                let url = try url(forItemNamed: name)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    subscriber(.success(false))
                    return Disposables.create()
                }
                try coordinatedWrite(to: url, options: .forDeleting) { coordinatedUrl in
                    try FileManager.default.removeItem(at: coordinatedUrl)
                }
                subscriber(.success(true))
            } catch let error {
                DDLogError("ICloudTransport: can't remove \(name) - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    func listItemNames() -> Single<[String]> {
        return Single.create { [weak self] subscriber in
            guard let self else { return Disposables.create() }
            do {
                let dir = try storageDirectory()
                let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])
                let names = urls.map { url -> String in
                    var name = url.lastPathComponent
                    // Normalize evicted placeholders: ".<KEY>.zip.icloud" -> "<KEY>.zip"
                    if name.hasSuffix(".icloud") {
                        name = String(name.dropLast(".icloud".count))
                        if name.hasPrefix(".") {
                            name = String(name.dropFirst())
                        }
                    }
                    return name
                }
                subscriber(.success(Array(Set(names))))
            } catch let error {
                DDLogError("ICloudTransport: can't list storage - \(error)")
                subscriber(.failure(error))
            }
            return Disposables.create()
        }
    }

    func materialize(name: String, queue: DispatchQueue) -> Observable<Progress> {
        return Observable.create { [weak self] subscriber in
            guard let self else {
                subscriber.onCompleted()
                return Disposables.create()
            }

            let url: URL
            do {
                url = try self.url(forItemNamed: name)
            } catch let error {
                subscriber.onError(error)
                return Disposables.create()
            }

            if self.isDownloaded(name: name) {
                let progress = Progress(totalUnitCount: 100)
                progress.completedUnitCount = 100
                subscriber.onNext(progress)
                subscriber.onCompleted()
                return Disposables.create()
            }

            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch let error {
                subscriber.onError(error)
                return Disposables.create()
            }

            let observer = ICloudDownloadObserver(url: url, fileName: name) { event in
                switch event {
                case .progress(let fraction):
                    let progress = Progress(totalUnitCount: 100)
                    progress.completedUnitCount = Int64(fraction * 100)
                    subscriber.onNext(progress)

                case .completed:
                    let progress = Progress(totalUnitCount: 100)
                    progress.completedUnitCount = 100
                    subscriber.onNext(progress)
                    subscriber.onCompleted()

                case .failed(let error):
                    subscriber.onError(error)
                }
            }
            observer.start()

            // Timeout in case the file never arrives (offline / removed remotely).
            let timeout = DispatchWorkItem {
                observer.stop()
                subscriber.onError(Error.materializationTimeout)
            }
            queue.asyncAfter(deadline: .now() + ICloudTransportController.materializationTimeout, execute: timeout)

            return Disposables.create {
                timeout.cancel()
                observer.stop()
            }
        }
    }

    // MARK: - NSFileCoordinator helpers

    private func coordinatedWrite(to url: URL, options: NSFileCoordinator.WritingOptions, block: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var blockError: Swift.Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordinatorError) { coordinatedUrl in
            do {
                try block(coordinatedUrl)
            } catch let error {
                blockError = error
            }
        }
        if let coordinatorError {
            throw Error.coordination(coordinatorError)
        }
        if let blockError {
            throw blockError
        }
    }

    private func coordinatedRead(at url: URL, block: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var blockError: Swift.Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedUrl in
            do {
                try block(coordinatedUrl)
            } catch let error {
                blockError = error
            }
        }
        if let coordinatorError {
            throw Error.coordination(coordinatorError)
        }
        if let blockError {
            throw blockError
        }
    }
}

/// Observes download completion of a single ubiquitous item via `NSMetadataQuery`. The query is started on the main run loop (required for
/// notification delivery) and reports progress/completion back through `handler`.
private final class ICloudDownloadObserver {
    enum Event {
        case progress(Double)
        case completed
        case failed(Swift.Error)
    }

    private let url: URL
    private let fileName: String
    private let handler: (Event) -> Void
    private var query: NSMetadataQuery?
    private var tokens: [NSObjectProtocol] = []
    private var finished = false

    init(url: URL, fileName: String, handler: @escaping (Event) -> Void) {
        self.url = url
        self.fileName = fileName
        self.handler = handler
    }

    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
            query.valueListAttributes = [NSMetadataUbiquitousItemDownloadingStatusKey, NSMetadataUbiquitousItemPercentDownloadedKey]

            let center = NotificationCenter.default
            let onUpdate: (Notification) -> Void = { [weak self] _ in self?.evaluate(query: query) }
            tokens.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { note in onUpdate(note) })
            tokens.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { note in onUpdate(note) })

            self.query = query
            query.start()
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            query?.stop()
            query = nil
        }
    }

    private func evaluate(query: NSMetadataQuery) {
        guard !finished else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        guard query.resultCount > 0, let item = query.result(at: 0) as? NSMetadataItem else { return }

        if let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
            handler(.progress(percent / 100))
        }

        if let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
           status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
            finished = true
            handler(.completed)
            stop()
        }
    }
}
