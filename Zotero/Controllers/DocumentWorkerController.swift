//
//  DocumentWorkerController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 3/2/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import Darwin
import WebKit
import OrderedCollections

import CocoaLumberjackSwift
import RxSwift

final class DocumentWorkerController {
    // MARK: Types
    enum HandlerRuntime: Hashable {
        case jsContext
        case webView
    }

    private enum WorkerFileCopyStrategy {
        case regular
        case cloneFirst
    }

    enum Result {
        case recognizerData([String: Any])
        case fullText(Work.FullText.Result)
        case structuredDocumentText(Work.StructuredDocumentText.Result)
    }

    struct Configuration {
        let supportedWorkKinds: Set<Work.Kind>
        var usesNativeONNXForStructuredDocumentText: Bool
        var structuredDocumentTextRuntime: HandlerRuntime?

        static let allWorks = Configuration(supportedWorkKinds: Set(Work.Kind.allCases), usesNativeONNXForStructuredDocumentText: false)

        static var mainApp: Configuration {
#if MAINAPP
            return Configuration(supportedWorkKinds: Set(Work.Kind.allCases), usesNativeONNXForStructuredDocumentText: true)
#else
            return allWorks
#endif
        }

        static let shareExtension = Configuration(supportedWorkKinds: [.recognizer], usesNativeONNXForStructuredDocumentText: false)

        fileprivate func supports(_ work: Work) -> Bool {
            supportedWorkKinds.contains(work.kind)
        }

        fileprivate func preferredRuntime(for workKind: Work.Kind) -> HandlerRuntime {
            switch workKind {
            case .structuredDocumentText where usesNativeONNXForStructuredDocumentText:
                return structuredDocumentTextRuntime ?? .jsContext

            case .structuredDocumentText:
                return structuredDocumentTextRuntime ?? .webView

            case .recognizer, .fullText:
                return .jsContext
            }
        }

        fileprivate func shouldPreload(_ runtime: HandlerRuntime) -> Bool {
            supportedWorkKinds.contains(where: { preferredRuntime(for: $0) == runtime })
        }
    }

    enum Priority {
        case `default`
        case high

        var maxConcurrentWorkers: Int {
            switch self {
            case .default:
                return 1

            case .high:
                return 3
            }
        }

        static var inDescendingOrder: [Self] {
            return [.high, .default]
        }
    }

    class Worker: Hashable, CustomStringConvertible {
        enum State: CaseIterable {
            case pending
            case preparing
            case ready
            case queued
            case running
            case failed
        }

        enum Kind {
            case oneOff
            case normal
            case multipleWorks
        }

        let id = UUID()
        let file: FileData
        let kind: Kind
        let priority: Priority
        let password: String?
        fileprivate(set) var state: State = .pending
        fileprivate var isFinished = false
        fileprivate var subjectsByWork: OrderedDictionary<Work, PublishSubject<Update>> = [:]
        fileprivate var handlersByRuntime: [HandlerRuntime: DocumentWorkerHandling] = [:]
        fileprivate var workStartTimes: [Work: CFAbsoluteTime] = [:]
        fileprivate lazy var fileURL: URL = {
            file.createUrl()
        }()

        init(file: FileData, kind: Kind = .normal, priority: Priority = .default, password: String? = nil) {
            self.file = file
            self.kind = kind
            self.priority = priority
            self.password = password
        }

        static func == (lhs: DocumentWorkerController.Worker, rhs: DocumentWorkerController.Worker) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        var description: String {
            "Worker(id: \(id.uuidString), file: \(file.fileName))"
        }

        deinit {
            handlersByRuntime.values.forEach { ($0 as? DocumentWorkerWebViewHandler)?.removeFromSuperviewAsynchronously() }
        }
    }

    enum Work: Hashable {
        enum Kind: CaseIterable, Hashable {
            case recognizer
            case fullText
            case structuredDocumentText
        }

        fileprivate struct CacheLocation {
            let path: String
            let version: Int

            func directoryURL(for fileURL: URL, sourceHash: String) -> URL {
                return derivedSidecarsDirectoryURL(for: fileURL)
                    .appendingPathComponent(sourceHash)
                    .appendingPathComponent(path)
                    .appendingPathComponent(String(version))
            }

            func manifestURL(in directoryURL: URL) -> URL {
                return directoryURL
                    .appendingPathComponent("manifest")
                    .appendingPathExtension("json")
            }

            func fileURLs(for fileURL: URL, fileStorage: FileStorage) -> [URL] {
                guard let sourceHash = cachedMD5(from: fileURL, using: fileStorage.fileManager) else { return [] }
                let directoryURL = directoryURL(for: fileURL, sourceHash: sourceHash)
                guard fileStorage.fileManager.fileExists(atPath: directoryURL.path),
                      let enumerator = fileStorage.fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey])
                else {
                    return []
                }
                return enumerator
                    .compactMap { $0 as? URL }
                    .filter { url in
                        return (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                    }
                    .sorted { $0.path < $1.path }
            }
        }

        fileprivate protocol Cache {
            var location: CacheLocation { get }

            func cachedResult(for work: Work, in worker: Worker, fileStorage: FileStorage) -> Result?
            func writeIfNeeded(_ result: Result, for work: Work, in worker: Worker, fileStorage: FileStorage)
        }

        struct FullText {
            static let pageDelimiter = "\u{000C}"

            struct Result {
                let text: String
                let extractedPagesCount: Int
                let totalPages: Int

                init(text: String, extractedPagesCount: Int, totalPages: Int) {
                    self.text = text
                    self.extractedPagesCount = extractedPagesCount
                    self.totalPages = totalPages
                }

                init?(data: [String: Any]) {
                    guard let totalPages = data["totalPages"] as? Int,
                          let extractedPagesCount = data["extractedPages"] as? Int,
                          let text = data["text"] as? String
                    else { return nil }
                    self.init(text: text, extractedPagesCount: extractedPagesCount, totalPages: totalPages)
                }

                var data: [String: Any] {
                    return ["text": text, "extractedPages": extractedPagesCount, "totalPages": totalPages]
                }
            }

            fileprivate struct Cache: Work.Cache {
                let location = CacheLocation(path: "text", version: 1)

                func cachedResult(for work: Work, in worker: Worker, fileStorage: FileStorage) -> DocumentWorkerController.Result? {
                    guard case .fullText(let pages) = work else { return nil }
                    guard worker.password == nil else {
                        DDLogInfo("DocumentWorkerController: bypassed full text cache for password-protected \(worker)")
                        return nil
                    }
                    guard let sourceHash = cachedMD5(from: worker.fileURL, using: fileStorage.fileManager) else {
                        DDLogInfo("DocumentWorkerController: full text cache miss for \(worker), source hash unavailable")
                        return nil
                    }
                    let directoryURL = location.directoryURL(for: worker.fileURL, sourceHash: sourceHash)
                    let manifestURL = location.manifestURL(in: directoryURL)
                    let manifest: FullText.Manifest
                    do {
                        let data = try Data(contentsOf: manifestURL)
                        manifest = try JSONDecoder().decode(FullText.Manifest.self, from: data)
                    } catch {
                        DDLogInfo("DocumentWorkerController: full text cache miss for \(worker), manifest unavailable at \(manifestURL.lastPathComponent)")
                        return nil
                    }

                    let requestedPages = FullText.pageIndexes(from: pages, pageCount: manifest.pageCount)
                    var pageTexts: [String] = []
                    for pageIndex in requestedPages {
                        let pageURL = FullText.pageURL(in: directoryURL, pageIndex: pageIndex)
                        do {
                            let data = try Data(contentsOf: pageURL)
                            let page = try JSONDecoder().decode(FullText.Page.self, from: data)
                            guard page.totalPages == manifest.pageCount, page.extractedPages == 1 else {
                                DDLogInfo("DocumentWorkerController: full text cache miss for \(worker), stale page \(pageIndex)")
                                return nil
                            }
                            pageTexts.append(page.text)
                        } catch {
                            DDLogInfo("DocumentWorkerController: full text cache miss for \(worker), page \(pageIndex) unavailable")
                            return nil
                        }
                    }

                    let text = pageTexts.joined(separator: FullText.pageDelimiter).trimmingCharacters(in: .whitespacesAndNewlines)
                    DDLogInfo("DocumentWorkerController: full text cache hit for \(worker), pages \(requestedPages), sourceHash \(sourceHash)")
                    return .fullText(Result(text: text, extractedPagesCount: requestedPages.count, totalPages: manifest.pageCount))
                }

                func writeIfNeeded(_ result: DocumentWorkerController.Result, for work: Work, in worker: Worker, fileStorage: FileStorage) {
                    guard case .fullText(let pages) = work else { return }
                    guard worker.password == nil else {
                        DDLogInfo("DocumentWorkerController: skipped full text cache write for password-protected \(worker)")
                        return
                    }
                    guard case .fullText(let fullText) = result else {
                        DDLogInfo("DocumentWorkerController: skipped full text cache write for \(worker), result has unexpected shape")
                        return
                    }
                    guard let sourceHash = cachedMD5(from: worker.fileURL, using: fileStorage.fileManager) else {
                        DDLogInfo("DocumentWorkerController: skipped full text cache write for \(worker), source hash unavailable")
                        return
                    }
                    let directoryURL = location.directoryURL(for: worker.fileURL, sourceHash: sourceHash)
                    let manifestURL = location.manifestURL(in: directoryURL)

                    let requestedPages = FullText.pageIndexes(from: pages, pageCount: fullText.totalPages)
                    let pageTexts = fullText.text.components(separatedBy: FullText.pageDelimiter)
                    do {
                        try fileStorage.fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                        let manifest = FullText.Manifest(pageCount: fullText.totalPages)
                        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
                        guard requestedPages.count == fullText.extractedPagesCount, pageTexts.count == requestedPages.count else {
                            DDLogInfo("DocumentWorkerController: wrote full text cache manifest for \(worker), skipped page files due to unexpected page count")
                            return
                        }
                        for (index, pageIndex) in requestedPages.enumerated() {
                            let page = FullText.Page(totalPages: fullText.totalPages, extractedPages: 1, text: pageTexts[index])
                            try JSONEncoder().encode(page).write(to: FullText.pageURL(in: directoryURL, pageIndex: pageIndex), options: .atomic)
                        }
                        DDLogInfo("DocumentWorkerController: wrote full text cache for \(worker), pages \(requestedPages), sourceHash \(sourceHash)")
                    } catch {
                        DDLogError("DocumentWorkerController: failed to write full text cache for \(worker) - \(error)")
                    }
                }
            }

            fileprivate struct Manifest: Codable {
                let pageCount: Int
            }

            fileprivate struct Page: Codable {
                let totalPages: Int
                let extractedPages: Int
                let text: String
            }

            fileprivate static func pageURL(in directoryURL: URL, pageIndex: Int) -> URL {
                return directoryURL.appendingPathComponent(String(pageIndex)).appendingPathExtension("json")
            }

            fileprivate static func pageIndexes(from pages: [Int]?, pageCount: Int) -> [Int] {
                guard let pages else { return Array(0..<pageCount) }
                return pages.filter { $0 >= 0 && $0 < pageCount }
            }
        }

        struct StructuredDocumentText {
            struct Result {
                let data: Data

                init(data: Data) {
                    self.data = data
                }

                init?(data: [String: Any]) {
                    guard let buf = data["buf"] as? String, let data = Data(base64Encoded: buf) else { return nil }
                    self.init(data: data)
                }

                func pack() throws -> SDTPack {
                    return try SDTPack(data: data)
                }
            }

            fileprivate struct Cache: Work.Cache {
                let location = CacheLocation(path: "sdt", version: 3)

                func cachedResult(for work: Work, in worker: Worker, fileStorage: FileStorage) -> DocumentWorkerController.Result? {
                    guard case .structuredDocumentText = work else { return nil }
                    guard worker.password == nil else {
                        DDLogInfo("DocumentWorkerController: bypassed structured document text cache for password-protected \(worker)")
                        return nil
                    }
                    guard let sourceHash = cachedMD5(from: worker.fileURL, using: fileStorage.fileManager) else {
                        DDLogInfo("DocumentWorkerController: structured document text cache miss for \(worker), source hash unavailable")
                        return nil
                    }
                    let directoryURL = location.directoryURL(for: worker.fileURL, sourceHash: sourceHash)
                    let packURL = StructuredDocumentText.packURL(in: directoryURL)
                    do {
                        let data = try Data(contentsOf: packURL)
                        DDLogInfo("DocumentWorkerController: structured document text cache hit for \(worker), sourceHash \(sourceHash)")
                        return .structuredDocumentText(StructuredDocumentText.Result(data: data))
                    } catch {
                        DDLogInfo("DocumentWorkerController: structured document text cache miss for \(worker), pack unavailable at \(packURL.lastPathComponent)")
                        return nil
                    }
                }

                func writeIfNeeded(_ result: DocumentWorkerController.Result, for work: Work, in worker: Worker, fileStorage: FileStorage) {
                    guard case .structuredDocumentText = work else { return }
                    guard worker.password == nil else {
                        DDLogInfo("DocumentWorkerController: skipped structured document text cache write for password-protected \(worker)")
                        return
                    }
                    guard case .structuredDocumentText(let structuredDocumentText) = result else {
                        DDLogInfo("DocumentWorkerController: skipped structured document text cache write for \(worker), result has unexpected shape")
                        return
                    }
                    guard let sourceHash = cachedMD5(from: worker.fileURL, using: fileStorage.fileManager) else {
                        DDLogInfo("DocumentWorkerController: skipped structured document text cache write for \(worker), source hash unavailable")
                        return
                    }
                    let directoryURL = location.directoryURL(for: worker.fileURL, sourceHash: sourceHash)
                    do {
                        try fileStorage.fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                        try structuredDocumentText.data.write(to: StructuredDocumentText.packURL(in: directoryURL), options: .atomic)
                        DDLogInfo("DocumentWorkerController: wrote structured document text cache for \(worker), sourceHash \(sourceHash)")
                    } catch {
                        DDLogError("DocumentWorkerController: failed to write structured document text cache for \(worker) - \(error)")
                    }
                }
            }

            fileprivate static func packURL(in directoryURL: URL) -> URL {
                return directoryURL.appendingPathComponent("document").appendingPathExtension("sdt")
            }
        }

        case recognizer
        case fullText(pages: [Int]?)
        case structuredDocumentText

        var kind: Kind {
            switch self {
            case .recognizer:
                return .recognizer

            case .fullText:
                return .fullText

            case .structuredDocumentText:
                return .structuredDocumentText
            }
        }

        var id: String {
            switch self {
            case .recognizer:
                return "recognizer"

            case .fullText(let pages):
                guard let pages else { return "fullText(pages: nil)" }
                return "fullText(pages: [\(pages.map(String.init).joined(separator: ", "))])"

            case .structuredDocumentText:
                return "structuredDocumentText"
            }
        }

        init?(id: String) {
            if id == "recognizer" {
                self = .recognizer
                return
            }
            if id == "structuredDocumentText" {
                self = .structuredDocumentText
                return
            }
            let prefix = "fullText(pages: "
            let suffix = ")"
            guard id.hasPrefix(prefix), id.hasSuffix(suffix) else { return nil }
            let pages = id.dropFirst(prefix.count).dropLast(suffix.count)
            if pages == "nil" {
                self = .fullText(pages: nil)
                return
            }
            guard pages.hasPrefix("["), pages.hasSuffix("]") else { return nil }
            var pageIndexes: [Int] = []
            for pageString in pages.dropFirst().dropLast().components(separatedBy: ", ") {
                guard let pageIndex = Int(pageString) else { return nil }
                pageIndexes.append(pageIndex)
            }
            self = .fullText(pages: pageIndexes)
        }
        fileprivate var cache: Cache? {
            switch self {
            case .fullText:
                return FullText.Cache()

            case .structuredDocumentText:
                return StructuredDocumentText.Cache()

            case .recognizer:
                return nil
            }
        }
    }

    struct Update {
        enum Kind {
            case queued
            case failed
            case cancelled
            case inProgress(progress: Double? = nil)
            case extractedData(result: Result, isCached: Bool = false)
        }

        let workerId: UUID?
        let work: Work
        let fileName: String?
        let fileURL: URL?
        let priority: Priority?
        let runtime: HandlerRuntime?
        let kind: Kind
        let startTime: CFAbsoluteTime?
        let duration: CFTimeInterval?

        var startedAt: Date? {
            return startTime.map(Date.init(timeIntervalSinceReferenceDate:))
        }

        init(
            workerId: UUID? = nil,
            work: Work,
            fileName: String? = nil,
            fileURL: URL? = nil,
            priority: Priority? = nil,
            runtime: HandlerRuntime? = nil,
            kind: Kind,
            startTime: CFAbsoluteTime? = nil,
            duration: CFTimeInterval? = nil
        ) {
            self.workerId = workerId
            self.work = work
            self.fileName = fileName
            self.fileURL = fileURL
            self.priority = priority
            self.runtime = runtime
            self.kind = kind
            self.startTime = startTime
            self.duration = duration
        }
    }

    // MARK: Properties
    private let dispatchSpecificKey: DispatchSpecificKey<String>
    private let accessQueueLabel: String
    private let accessQueue: DispatchQueue
    private unowned let fileStorage: FileStorage
    private let disposeBag: DisposeBag
    private let workerFileCopyStrategy: WorkerFileCopyStrategy = .cloneFirst

#if MAINAPP
    let recorder: DocumentWorkerRecorder?
#endif
    private var configuration: Configuration

    weak var webViewProvider: WebViewProvider? {
        didSet {
            accessQueue.async(flags: .barrier) { [weak self] in
                self?.preloadWebViewDocumentWorkerIfNeeded()
            }
        }
    }

    // Accessed only via accessQueue
    private var preparing: Set<Worker> = []
    private var ready: Set<Worker> = []
    private var queuedByPriority: [Priority: OrderedSet<Worker>] = [:]
    private var runningByPriority: [Priority: OrderedSet<Worker>] = [:]
    private var failed: Set<Worker> = []
    private var workersById: [UUID: Worker] = [:]
    private var preloadedDocumentWorkerHandler: DocumentWorkerHandling?
    private var preloadedWebViewDocumentWorkerHandler: DocumentWorkerWebViewHandler?
    private var preparingPreloadedWebViewDocumentWorkerHandler: Bool = false

    // MARK: Object Lifecycle
    init(fileStorage: FileStorage, configuration: Configuration) {
        dispatchSpecificKey = DispatchSpecificKey<String>()
        accessQueueLabel = "org.zotero.DocumentWorkerController.accessQueue"
        accessQueue = DispatchQueue(label: accessQueueLabel, qos: .userInteractive, attributes: .concurrent)
        accessQueue.setSpecific(key: dispatchSpecificKey, value: accessQueueLabel)
        self.fileStorage = fileStorage
#if MAINAPP
        self.configuration = configuration
#else
        var configuration = configuration
        configuration.usesNativeONNXForStructuredDocumentText = false
        self.configuration = configuration
#endif
        disposeBag = DisposeBag()
#if MAINAPP
        recorder = FeatureGates.enabled.contains(.documentWorkerDebugging) ? DocumentWorkerRecorder() : nil
#endif
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.preloadDocumentWorkerIfIdle()
        }
    }

    // MARK: Actions
#if MAINAPP
    func getUsesNativeONNXForStructuredDocumentText(completion: @escaping (Bool) -> Void) {
        accessQueue.async { [weak self] in
            guard let self else { return }
            let value = configuration.usesNativeONNXForStructuredDocumentText
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    func setUsesNativeONNXForStructuredDocumentText(_ newValue: Bool) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self, configuration.usesNativeONNXForStructuredDocumentText != newValue else { return }

            configuration.usesNativeONNXForStructuredDocumentText = newValue
            preloadDocumentWorkerIfIdle()
            preloadWebViewDocumentWorkerIfNeeded()
            DDLogInfo("DocumentWorkerController: structured document text runtime changed to \(configuration.usesNativeONNXForStructuredDocumentText ? "native ONNX" : "WebView")")
        }
    }
#endif

    private func preferredRuntime(for work: Work) -> HandlerRuntime {
        return configuration.preferredRuntime(for: work.kind)
    }

    private func updateStateAndQueues(for worker: Worker, state: Worker.State) {
        // Is called only by callers already in the access queue.
        worker.state = state
        var queued = queuedByPriority[worker.priority, default: []]
        var running = runningByPriority[worker.priority, default: []]
        preparing.remove(worker)
        ready.remove(worker)
        queued.remove(worker)
        running.remove(worker)
        failed.remove(worker)
        switch worker.state {
        case .pending:
            workersById[worker.id] = nil

        case .preparing, .ready, .queued, .running, .failed:
            workersById[worker.id] = worker
        }
        switch worker.state {
        case .pending:
            // Pending workers, i.e. worker that where initialized, but no work has been queued in them yet, and thus not prepared, are not kept in any structure.
            break

        case .preparing:
            preparing.insert(worker)

        case .ready:
            ready.insert(worker)

        case .queued:
            queued.append(worker)

        case .running:
            running.append(worker)

        case .failed:
            failed.insert(worker)
        }
        queuedByPriority[worker.priority] = queued
        runningByPriority[worker.priority] = running
    }

    func queue(work: Work, in worker: Worker) -> Observable<Update> {
        let subject = PublishSubject<Update>()
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            guard configuration.supports(work) else {
                reject(work: work, in: worker, to: subject, reason: "unsupported work")
                return
            }
            if worker.isFinished {
                reject(work: work, in: worker, to: subject, reason: "finished worker")
                return
            }
            if let existingSubject = worker.subjectsByWork[work] {
                existingSubject.bind(to: subject).disposed(by: disposeBag)
                return
            }
            if worker.kind == .oneOff && !worker.subjectsByWork.isEmpty {
                reject(work: work, in: worker, to: subject, reason: "busy one-off worker")
                return
            }
            worker.subjectsByWork[work] = subject
#if MAINAPP
            recorder?.bind(subject)
#endif
            subject.send(work: work, kind: .queued, worker: worker, runtime: preferredRuntime(for: work))
            if let cachedResult = work.cache?.cachedResult(for: work, in: worker, fileStorage: fileStorage) {
                worker.workStartTimes[work] = CFAbsoluteTimeGetCurrent()
                subject.send(work: work, kind: .inProgress(), worker: worker, runtime: preferredRuntime(for: work))
                finishWork(work, in: worker, updateWorkerState: false, finalUpdateKind: .extractedData(result: cachedResult, isCached: true))
                return
            }
            switch worker.state {
            case .pending, .failed:
                // Assign preparing state and place in proper queue, then prepare worker handler.
                updateStateAndQueues(for: worker, state: .preparing)
                prepare(worker: worker, for: work)

            case .preparing:
                // A new work is queued to a worker that is still preparing, do nothing.
                break

            case .ready:
                // A new work is queued to a worker that is ready with no works (e.g. a worker that finished its works, but was kept by the user).
                if worker.handlersByRuntime[preferredRuntime(for: work)] != nil {
                    // Assign queued state, place in proper queue, and start work if needed.
                    updateStateAndQueues(for: worker, state: .queued)
                    startWorkIfNeeded()
                } else {
                    updateStateAndQueues(for: worker, state: .preparing)
                    prepare(worker: worker, for: work)
                }

            case .queued:
                // Already queued, just start work if needed.
                startWorkIfNeeded()

            case .running:
                // Already running, do nothing.
                break
            }
        }
        return subject.asObservable()

        func reject(work: Work, in worker: Worker, to subject: PublishSubject<Update>, reason: String) {
            DDLogWarn("DocumentWorkerController: rejected \(work) in \(worker) - \(reason)")
#if MAINAPP
            recorder?.bind(subject)
#endif
            subject.send(work: work, kind: .failed, worker: worker, runtime: preferredRuntime(for: work))
            subject.onCompleted()
        }
    }

    func clearCachedWorks() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }

            let downloadsURL = Files.downloads.createUrl()
            guard fileStorage.fileManager.fileExists(atPath: downloadsURL.path) else {
                DDLogInfo("DocumentWorkerController: skipped cached work clear, downloads directory missing")
                return
            }
            guard let enumerator = fileStorage.fileManager.enumerator(at: downloadsURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
                DDLogError("DocumentWorkerController: failed to enumerate downloads directory for cached work clear")
                return
            }

            var removedCount = 0
            for case let url as URL in enumerator {
                guard url.lastPathComponent == ".zotero-derived" else { continue }
                enumerator.skipDescendants()
                do {
                    try fileStorage.fileManager.removeItem(at: url)
                    removedCount += 1
                } catch {
                    DDLogError("DocumentWorkerController: failed to clear cached work directory \(url.path) - \(error)")
                }
            }
            DDLogInfo("DocumentWorkerController: cleared \(removedCount) cached document worker directories")
        }
    }

    func cachedWorkFileURLs(for work: Work, fileURL: URL, completion: @escaping ([URL]) -> Void) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            let urls = work.cache?.location.fileURLs(for: fileURL, fileStorage: fileStorage) ?? []
            DispatchQueue.main.async {
                completion(urls)
            }
        }
    }

    private func prepare(worker: Worker, for work: Work) {
        let runtime = preferredRuntime(for: work)
        switch runtime {
        case .jsContext:
            let documentWorkerHandler = preloadedDocumentWorkerHandler ?? createDocumentWorkerJSHandler()
            setup(documentWorkerHandler: documentWorkerHandler, runtime: .jsContext, for: worker)
            preloadedDocumentWorkerHandler = nil
            accessQueue.async(flags: .barrier) { [weak self] in
                self?.preloadDocumentWorkerIfIdle()
            }
            updateStateAndQueues(for: worker, state: .queued)
            startWorkIfNeeded()

        case .webView:
            if let documentWorkerHandler = preloadedWebViewDocumentWorkerHandler {
                DDLogInfo("DocumentWorkerController: using preloaded WebView document worker handler for \(worker)")
                preloadedWebViewDocumentWorkerHandler = nil
                if setup(documentWorkerHandler: documentWorkerHandler, runtime: .webView, for: worker) {
                    updateStateAndQueues(for: worker, state: .queued)
                    startWorkIfNeeded()
                } else {
                    release(documentWorkerHandler)
                    finishWork(work, in: worker, finalUpdateKind: .failed)
                }
                accessQueue.async(flags: .barrier) { [weak self] in
                    self?.preloadWebViewDocumentWorkerIfNeeded()
                }
                return
            }
            if preparingPreloadedWebViewDocumentWorkerHandler {
                DDLogInfo("DocumentWorkerController: waiting for preloaded WebView document worker handler for \(worker)")
                return
            }
            createDocumentWorkerWebViewHandler(fileStorage: fileStorage) { [weak self, weak worker] documentWorkerHandler in
                guard let self, let worker else { return }
                guard let documentWorkerHandler else {
                    finishWork(work, in: worker, finalUpdateKind: .failed)
                    return
                }
                // The work may have been cancelled while the WebView handler was being created.
                guard worker.subjectsByWork[work] != nil else {
                    release(documentWorkerHandler)
                    return
                }
                if setup(documentWorkerHandler: documentWorkerHandler, runtime: .webView, for: worker) {
                    updateStateAndQueues(for: worker, state: .queued)
                    startWorkIfNeeded()
                } else {
                    release(documentWorkerHandler)
                    finishWork(work, in: worker, finalUpdateKind: .failed)
                }
            }
        }
    }

    @discardableResult
    private func setup(documentWorkerHandler: DocumentWorkerHandling, runtime: HandlerRuntime, for worker: Worker) -> Bool {
        documentWorkerHandler.workFile = worker.file
        documentWorkerHandler.shouldCacheWorkInput = worker.kind == .multipleWorks
        if runtime == .webView, !copy(workFile: worker.file, to: documentWorkerHandler) {
            return false
        }
        setupObserver(in: worker, for: documentWorkerHandler)
        worker.handlersByRuntime[runtime] = documentWorkerHandler
        return true

        func copy(workFile file: FileData, to documentWorkerHandler: DocumentWorkerHandling) -> Bool {
            guard let documentWorkerHandler = documentWorkerHandler as? DocumentWorkerWebViewHandler else { return true }
            let destination = documentWorkerHandler.temporaryDirectory.copy(withName: file.name, ext: file.ext)
            do {
                try copyWorkerFile(from: file.createUrl(), to: destination.createUrl(), fileStorage: fileStorage)
            } catch {
                DDLogError("DocumentWorkerController: failed to copy file for document worker - \(error)")
                return false
            }
            return true
        }

        func setupObserver(in worker: Worker, for documentWorkerHandler: DocumentWorkerHandling) {
            documentWorkerHandler.observable.subscribe(onNext: { [weak self, weak worker] event in
                guard let self else { return }
                accessQueue.async(flags: .barrier) { [weak self, weak worker] in
                    guard let self, let worker, let work = Work(id: event.workId), worker.subjectsByWork[work] != nil else { return }
                    switch event.result {
                    case .success(let data):
                        switch data {
                        case .progress(let progress):
                            worker.subjectsByWork[work]?.send(work: work, kind: .inProgress(progress: progress), worker: worker, runtime: preferredRuntime(for: work))

                        case .recognizerData(let data):
                            finishWork(work, in: worker, finalUpdateKind: .extractedData(result: .recognizerData(data)))

                        case .structuredDocumentText(let data):
                            guard let result = Work.StructuredDocumentText.Result(data: data) else {
                                DDLogError("DocumentWorkerController: work \(work.id) failed - structured document text result has unexpected shape")
                                finishWork(work, in: worker, finalUpdateKind: .failed)
                                return
                            }
                            let workResult: Result = .structuredDocumentText(result)
                            work.cache?.writeIfNeeded(workResult, for: work, in: worker, fileStorage: fileStorage)
                            finishWork(work, in: worker, finalUpdateKind: .extractedData(result: workResult))

                        case .fullText(let data):
                            guard let result = Work.FullText.Result(data: data) else {
                                DDLogError("DocumentWorkerController: work \(work.id) failed - full text result has unexpected shape")
                                finishWork(work, in: worker, finalUpdateKind: .failed)
                                return
                            }
                            let workResult = Result.fullText(result)
                            work.cache?.writeIfNeeded(workResult, for: work, in: worker, fileStorage: fileStorage)
                            finishWork(work, in: worker, finalUpdateKind: .extractedData(result: workResult))
                        }

                    case .failure(let error):
                        DDLogError("DocumentWorkerController: work \(work.id) failed - \(error)")
                        finishWork(work, in: worker, finalUpdateKind: .failed)
                    }
                }
            })
            .disposed(by: disposeBag)
        }
    }

    private func startWorkIfNeeded() {
        var worker: Worker?
        for priority in Priority.inDescendingOrder {
            let queued = queuedByPriority[priority, default: []]
            if !queued.isEmpty, runningByPriority[priority, default: []].count < priority.maxConcurrentWorkers {
                worker = queued.first
                // Since queued is not empty, we are certain that worker is not nil, so break from the for loop.
                // The new worker state and queue to be appended to, will be made in a subsequent updateStateAndQueues call.
                break
            }
        }
        guard let worker else { return }
        guard let work = worker.subjectsByWork.keys.first, let subject = worker.subjectsByWork[work] else {
            // This shouldn't happen, move worker back to ready state.
            updateStateAndQueues(for: worker, state: .ready)
            startWorkIfNeeded()
            return
        }
        let runtime = preferredRuntime(for: work)
        guard let documentWorkerHandler = worker.handlersByRuntime[runtime] else {
            updateStateAndQueues(for: worker, state: .preparing)
            prepare(worker: worker, for: work)
            return
        }
        // Set worker state to running and append to proper queue.
        updateStateAndQueues(for: worker, state: .running)
        // Start work.
        worker.workStartTimes[work] = CFAbsoluteTimeGetCurrent()
        DDLogInfo("DocumentWorkerController: started \(work) in \(worker)")
        subject.send(work: work, kind: .inProgress(), worker: worker, runtime: runtime)
        switch work {
        case .recognizer:
            documentWorkerHandler.performAction(.recognizePDF(password: worker.password), workId: work.id)

        case .fullText(let pages):
            documentWorkerHandler.performAction(.getPDFFulltext(pages: pages, password: worker.password), workId: work.id)

        case .structuredDocumentText:
            guard let sourceHash = cachedMD5(from: worker.fileURL, using: fileStorage.fileManager) else {
                DDLogError("DocumentWorkerController: can't create source hash for \(worker)")
                finishWork(work, in: worker, finalUpdateKind: .failed)
                return
            }
            documentWorkerHandler.performAction(.getStructuredDocumentText(contentType: worker.file.mimeType, password: worker.password, sourceHash: sourceHash), workId: work.id)
        }
        // Start another work if needed.
        startWorkIfNeeded()
    }

    private func finishWork(_ work: Work, in worker: Worker, updateWorkerState: Bool = true, finalUpdateKind: Update.Kind, startNextWorkIfNeeded: Bool = true) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            finishWork(work, worker: worker, updateWorkerState: updateWorkerState, finalUpdateKind: finalUpdateKind, startNextWorkIfNeeded: startNextWorkIfNeeded, controller: self)
        } else {
            accessQueue.async(flags: .barrier) { [weak self] in
                guard let self else { return }
                finishWork(work, worker: worker, updateWorkerState: updateWorkerState, finalUpdateKind: finalUpdateKind, startNextWorkIfNeeded: startNextWorkIfNeeded, controller: self)
            }
        }

        func finishWork(_ work: Work, worker: Worker, updateWorkerState: Bool, finalUpdateKind: Update.Kind, startNextWorkIfNeeded: Bool, controller: DocumentWorkerController) {
            let duration = duration(for: work, in: worker)
            let subject = worker.subjectsByWork.removeValue(forKey: work)
            let shouldFinishOneOffWorker = worker.kind == .oneOff && worker.subjectsByWork.isEmpty
            if shouldFinishOneOffWorker {
                worker.isFinished = true
            }
            if updateWorkerState {
                let nextState: Worker.State
                if shouldFinishOneOffWorker {
                    nextState = .pending
                } else {
                    nextState = worker.subjectsByWork.isEmpty ? .ready : .queued
                }
                controller.updateStateAndQueues(for: worker, state: nextState)
            }
            subject?.send(work: work, kind: finalUpdateKind, worker: worker, runtime: preferredRuntime(for: work), duration: duration)
            subject?.onCompleted()
            if shouldFinishOneOffWorker {
                controller.releaseHandlers(for: worker)
            }
            var message = "DocumentWorkerController: finished \(work) in \(worker)"
            if let duration {
                message += " took \(String(format: "%.3f", duration))s"
            }
            DDLogInfo(DDLogMessageFormat(stringLiteral: message))
            guard startNextWorkIfNeeded else { return }
            controller.startWorkIfNeeded()
            if shouldFinishOneOffWorker {
                controller.preloadDocumentWorkerIfIdle()
            }

            func duration(for work: Work, in worker: Worker) -> CFTimeInterval? {
                guard let startTime = worker.workStartTimes.removeValue(forKey: work) else { return nil }
                return CFAbsoluteTimeGetCurrent() - startTime
            }
        }
    }

    func cancelWork(_ work: Work, in worker: Worker) {
        DDLogInfo("DocumentWorkerController: cancelled \(work) in \(worker)")
        finishWork(work, in: worker, finalUpdateKind: .cancelled)
    }

    func cancelWork(_ work: Work, workerId: UUID) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self, let worker = workersById[workerId] else { return }
            guard worker.subjectsByWork[work] != nil else { return }
            cancelWork(work, in: worker)
        }
    }

    func cancelAllWorks(in worker: Worker, startNextWorkIfNeeded: Bool = true) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            cancelAllWorks(in: worker, startNextWorkIfNeeded: startNextWorkIfNeeded, controller: self)
        } else {
            accessQueue.async(flags: .barrier) { [weak self] in
                guard let self else { return }
                cancelAllWorks(in: worker, startNextWorkIfNeeded: startNextWorkIfNeeded, controller: self)
            }
        }

        func cancelAllWorks(in worker: Worker, startNextWorkIfNeeded: Bool, controller: DocumentWorkerController) {
            DDLogInfo("DocumentWorkerController: cancel all works in \(worker)")
            // Immediately release worker handler and assign pending state to worker. If another work is queued for this worker, a new handler will be created.
            releaseHandlers(for: worker)
            controller.updateStateAndQueues(for: worker, state: .pending)
            let cancelledWorks = Array(worker.subjectsByWork.keys)
            for work in cancelledWorks {
                finishWork(work, in: worker, updateWorkerState: false, finalUpdateKind: .cancelled, startNextWorkIfNeeded: false)
            }
            worker.subjectsByWork.removeAll()
            guard startNextWorkIfNeeded else { return }
            controller.startWorkIfNeeded()
            controller.preloadDocumentWorkerIfIdle()
        }
    }

    private func release(_ handler: DocumentWorkerHandling) {
        (handler as? DocumentWorkerWebViewHandler)?.removeFromSuperviewAsynchronously()
    }

    private func releaseHandlers(for worker: Worker) {
        worker.handlersByRuntime.values.forEach { release($0) }
        worker.handlersByRuntime.removeAll()
    }

    func cleanupWorker(_ worker: Worker) {
        cancelAllWorks(in: worker)
    }

    func cancellAllWorks() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            DDLogInfo("DocumentWorkerController: cancel all works")
            var workers: Set<Worker> = []
            workers.formUnion(preparing)
            workers.formUnion(ready)
            for priority in Priority.inDescendingOrder {
                workers.formUnion(queuedByPriority[priority, default: []])
                workers.formUnion(runningByPriority[priority, default: []])
            }
            workers.formUnion(failed)
            for worker in workers {
                cancelAllWorks(in: worker, startNextWorkIfNeeded: false)
            }
        }
    }

    private func preloadDocumentWorkerIfIdle() {
        guard preloadedDocumentWorkerHandler == nil,
              configuration.shouldPreload(.jsContext),
              ready.isEmpty,
              preparing.isEmpty,
              !Priority.inDescendingOrder.contains(where: { !queuedByPriority[$0, default: []].isEmpty || !runningByPriority[$0, default: []].isEmpty })
        else { return }
        preloadedDocumentWorkerHandler = createDocumentWorkerJSHandler()
    }

    private func createDocumentWorkerJSHandler() -> DocumentWorkerJSHandler {
#if MAINAPP
        return DocumentWorkerJSHandler(
            nativeONNXModelDataProvider: { model in
                try nativeONNXModelData(for: model)
            },
            usesNativeONNXForStructuredDocumentText: configuration.usesNativeONNXForStructuredDocumentText
        )

        func nativeONNXModelData(for model: String) throws -> Data {
            let normalizedPath = model.replacingOccurrences(of: "\\", with: "/")
            let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: false)
            let hasUnsafeComponent = components.contains { $0.isEmpty || $0 == ".." }
            guard !normalizedPath.isEmpty,
                  !normalizedPath.hasPrefix("/"),
                  !hasUnsafeComponent else {
                throw DocumentWorkerJSHandler.Error.invalidBundledWorkerDataPath(model)
            }

            let nsPath = normalizedPath as NSString
            let resourceName = nsPath.lastPathComponent
            guard !resourceName.isEmpty, resourceName != "." else {
                throw DocumentWorkerJSHandler.Error.invalidBundledWorkerDataPath(model)
            }
            let directory = nsPath.deletingLastPathComponent
            let subdirectory: String
            if directory.isEmpty || directory == "." {
                subdirectory = "Bundled/document_worker"
            } else {
                subdirectory = "Bundled/document_worker/\(directory)"
            }

            guard let url = Bundle.main.url(forResource: resourceName, withExtension: nil, subdirectory: subdirectory) else {
                throw DocumentWorkerJSHandler.Error.missingBundledWorkerData(model)
            }
            return try Data(contentsOf: url)
        }
#else
        return DocumentWorkerJSHandler()
#endif
    }

    private func preloadWebViewDocumentWorkerIfNeeded() {
        guard webViewProvider != nil,
              configuration.shouldPreload(.webView),
              preloadedWebViewDocumentWorkerHandler == nil,
              !preparingPreloadedWebViewDocumentWorkerHandler
        else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        preparingPreloadedWebViewDocumentWorkerHandler = true
        DDLogInfo("DocumentWorkerController: started preloading WebView document worker handler")
        createDocumentWorkerWebViewHandler(fileStorage: fileStorage) { [weak self] documentWorkerHandler in
            guard let self else { return }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            preparingPreloadedWebViewDocumentWorkerHandler = false
            preloadedWebViewDocumentWorkerHandler = documentWorkerHandler
            if documentWorkerHandler != nil {
                DDLogInfo("DocumentWorkerController: preloaded WebView document worker handler in \(String(format: "%.3f", duration))s")
            } else {
                DDLogError("DocumentWorkerController: failed to preload WebView document worker handler after \(String(format: "%.3f", duration))s")
            }
            prepareWaitingWebViewWorkerIfNeeded()
        }
    }

    private func prepareWaitingWebViewWorkerIfNeeded() {
        guard let worker = preparing.first(where: { worker in
            guard let work = worker.subjectsByWork.keys.first else { return false }
            let runtime = preferredRuntime(for: work)
            return runtime == .webView && worker.handlersByRuntime[runtime] == nil
        }), let work = worker.subjectsByWork.keys.first else { return }
        prepare(worker: worker, for: work)
    }

    private func createDocumentWorkerWebViewHandler(fileStorage: FileStorage, completion: @escaping (DocumentWorkerWebViewHandler?) -> Void) {
        guard let temporaryDirectory = prepareTemporaryWorkerDirectory(fileStorage: fileStorage) else {
            completion(nil)
            return
        }
        let cleanupClosure: () -> Void = { [weak fileStorage] in
            guard let fileStorage else { return }
            removeTemporaryWorkerDirectory(temporaryDirectory, fileStorage: fileStorage)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                cleanupClosure()
                return
            }
            guard let webViewProvider else {
                accessQueue.async(flags: .barrier) {
                    completion(nil)
                }
                cleanupClosure()
                return
            }
            let webViewConfiguration = WKWebViewConfiguration()
            webViewConfiguration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            let webView = webViewProvider.addWebView(configuration: webViewConfiguration)
#if MAINAPP
            let documentWorkerHandler = DocumentWorkerWebViewHandler(
                webView: webView,
                temporaryDirectory: temporaryDirectory,
                cleanup: cleanupClosure,
                nativeONNXModelDataProvider: { model in
                    try nativeONNXModelData(for: model, in: temporaryDirectory)
                },
                usesNativeONNXForStructuredDocumentText: configuration.usesNativeONNXForStructuredDocumentText
            )
#else
            let documentWorkerHandler = DocumentWorkerWebViewHandler(
                webView: webView,
                temporaryDirectory: temporaryDirectory,
                cleanup: cleanupClosure
            )
#endif
            accessQueue.async(flags: .barrier) {
                completion(documentWorkerHandler)
            }
        }

#if MAINAPP
        func nativeONNXModelData(for model: String, in temporaryDirectory: File) throws -> Data {
            guard !model.isEmpty, !model.hasPrefix("/"), !model.split(separator: "/").contains("..") else {
                throw DocumentWorkerWebViewHandler.Error.invalidNativeONNXBridgePayload("invalid model path")
            }
            let directoryURL = temporaryDirectory.createUrl().standardizedFileURL
            let modelURL = directoryURL.appendingPathComponent(model).standardizedFileURL
            guard modelURL.path.hasPrefix(directoryURL.path + "/") else {
                throw DocumentWorkerWebViewHandler.Error.invalidNativeONNXBridgePayload("model path escapes temporary directory")
            }
            return try Data(contentsOf: modelURL)
        }
#endif

        func prepareTemporaryWorkerDirectory(fileStorage: FileStorage) -> File? {
            let startTime = CFAbsoluteTimeGetCurrent()
            guard let workerHtmlUrl = Bundle.main.url(forResource: "document_worker", withExtension: "html") else {
                DDLogError("DocumentWorkerController: document_worker.html not found")
                return nil
            }
            guard let bundledWorkerUrl = Bundle.main.url(forResource: "document_worker", withExtension: nil, subdirectory: "Bundled") else {
                DDLogError("DocumentWorkerController: bundled document worker not found")
                return nil
            }
            let temporaryDirectory = Files.temporaryDirectory
            let temporaryDirectoryUrl = temporaryDirectory.createUrl()
            do {
                try fileStorage.fileManager.createDirectory(at: temporaryDirectoryUrl, withIntermediateDirectories: true)
                try copyWorkerFile(from: workerHtmlUrl, to: temporaryDirectory.copy(withName: "document_worker", ext: "html").createUrl(), fileStorage: fileStorage)
                let contents = try fileStorage.fileManager.contentsOfDirectory(at: bundledWorkerUrl, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                for url in contents {
                    let destination = temporaryDirectoryUrl.appendingPathComponent(url.lastPathComponent)
                    try copyWorkerItem(from: url, to: destination, fileStorage: fileStorage)
                }
            } catch {
                DDLogError("DocumentWorkerController: failed to prepare worker directory - \(error)")
                removeTemporaryWorkerDirectory(temporaryDirectory, fileStorage: fileStorage)
                return nil
            }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            DDLogInfo("DocumentWorkerController: prepared temporary document worker directory in \(String(format: "%.3f", duration))s")
            return temporaryDirectory
        }

        func removeTemporaryWorkerDirectory(_ directory: File, fileStorage: FileStorage) {
            DispatchQueue.global(qos: .background).async { [weak fileStorage] in
                guard let fileStorage else { return }
                do {
                    try fileStorage.remove(directory)
                } catch {
                    DDLogError("DocumentWorkerController: failed to remove worker directory - \(error)")
                }
            }
        }
    }

    private func copyWorkerItem(from sourceUrl: URL, to destinationUrl: URL, fileStorage: FileStorage) throws {
        let values = try sourceUrl.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isDirectory == true && values.isSymbolicLink != true {
            try fileStorage.fileManager.createDirectory(at: destinationUrl, withIntermediateDirectories: true)
            let contents = try fileStorage.fileManager.contentsOfDirectory(at: sourceUrl, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            for url in contents {
                try copyWorkerItem(from: url, to: destinationUrl.appendingPathComponent(url.lastPathComponent), fileStorage: fileStorage)
            }
            return
        }

        try copyWorkerFile(from: sourceUrl, to: destinationUrl, fileStorage: fileStorage)
    }

    private func copyWorkerFile(from sourceUrl: URL, to destinationUrl: URL, fileStorage: FileStorage) throws {
        try fileStorage.fileManager.createDirectory(at: destinationUrl.deletingLastPathComponent(), withIntermediateDirectories: true)

        switch workerFileCopyStrategy {
        case .regular:
            try fileStorage.fileManager.copyItem(at: sourceUrl, to: destinationUrl)

        case .cloneFirst:
            try cloneOrCopyFile(from: sourceUrl, to: destinationUrl, fileStorage: fileStorage)
        }
    }

    private func cloneOrCopyFile(from sourceUrl: URL, to destinationUrl: URL, fileStorage: FileStorage) throws {
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE)
        if copyfile(sourceUrl.path, destinationUrl.path, nil, flags) == 0 {
            return
        }

        let error = errno
        DDLogInfo("DocumentWorkerController: clone copy failed with errno \(error), falling back to regular copy from \(sourceUrl.lastPathComponent) to \(destinationUrl.lastPathComponent)")
        if fileStorage.fileManager.fileExists(atPath: destinationUrl.path) {
            try? fileStorage.fileManager.removeItem(at: destinationUrl)
        }
        try fileStorage.fileManager.copyItem(at: sourceUrl, to: destinationUrl)
    }
}

private extension PublishSubject where Element == DocumentWorkerController.Update {
    func send(
        work: DocumentWorkerController.Work,
        kind: DocumentWorkerController.Update.Kind,
        worker: DocumentWorkerController.Worker,
        runtime: DocumentWorkerController.HandlerRuntime,
        duration: CFTimeInterval? = nil
    ) {
        on(.next(DocumentWorkerController.Update(
            workerId: worker.id,
            work: work,
            fileName: worker.file.fileName,
            fileURL: worker.fileURL,
            priority: worker.priority,
            runtime: runtime,
            kind: kind,
            startTime: worker.workStartTimes[work],
            duration: duration
        )))
    }
}

extension Attachment {
    var supportsStructuredDocumentTextExtraction: Bool {
        switch type {
        case .file(_, let contentType, _, _, _):
            return contentType == "application/pdf" || contentType == "application/epub+zip" || contentType == "text/html" || contentType == "application/xhtml+xml"

        case .url:
            return false
        }
    }
}
