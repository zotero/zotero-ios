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
    fileprivate enum HandlerRuntime: Hashable {
        case jsContext
        case webView
    }

    private enum WorkerFileCopyStrategy {
        case regular
        case cloneFirst
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

        let id = UUID()
        let file: FileData
        let shouldCacheInput: Bool
        let priority: Priority
        let password: String?
        fileprivate(set) var state: State = .pending
        fileprivate var subjectsByWork: OrderedDictionary<Work, PublishSubject<Update>> = [:]
        fileprivate var handlersByRuntime: [HandlerRuntime: DocumentWorkerHandling] = [:]
        fileprivate var workStartTimes: [Work: CFAbsoluteTime] = [:]

        init(file: FileData, shouldCacheInput: Bool, priority: Priority, password: String? = nil) {
            self.file = file
            self.shouldCacheInput = shouldCacheInput
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
        case recognizer
        case fullText(pages: [Int]?)
        case structuredDocumentText

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

        fileprivate var preferredRuntime: HandlerRuntime {
            switch self {
            case .structuredDocumentText:
                return .webView

            case .recognizer, .fullText:
                return .jsContext
            }
        }
    }

    struct Update {
        enum Kind {
            case failed
            case cancelled
            case inProgress
            case extractedData(data: [String: Any])
        }

        let work: Work
        let kind: Kind
    }

    // MARK: Properties
    private let dispatchSpecificKey: DispatchSpecificKey<String>
    private let accessQueueLabel: String
    private let accessQueue: DispatchQueue
    private unowned let fileStorage: FileStorage
    private let disposeBag: DisposeBag
    private let workerFileCopyStrategy: WorkerFileCopyStrategy = .cloneFirst

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
    private var preloadedDocumentWorkerHandler: DocumentWorkerHandling?
    private var preloadedWebViewDocumentWorkerHandler: DocumentWorkerWebViewHandler?
    private var preparingPreloadedWebViewDocumentWorkerHandler: Bool = false

    // MARK: Object Lifecycle
    init(fileStorage: FileStorage) {
        dispatchSpecificKey = DispatchSpecificKey<String>()
        accessQueueLabel = "org.zotero.DocumentWorkerController.accessQueue"
        accessQueue = DispatchQueue(label: accessQueueLabel, qos: .userInteractive, attributes: .concurrent)
        accessQueue.setSpecific(key: dispatchSpecificKey, value: accessQueueLabel)
        self.fileStorage = fileStorage
        disposeBag = DisposeBag()
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.preloadDocumentWorkerIfIdle()
        }
    }

    // MARK: Actions
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
            if let existingSubject = worker.subjectsByWork[work] {
                existingSubject.bind(to: subject).disposed(by: disposeBag)
                return
            }
            worker.subjectsByWork[work] = subject
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
                if worker.handlersByRuntime[work.preferredRuntime] != nil {
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
    }

    private func prepare(worker: Worker, for work: Work) {
        switch work.preferredRuntime {
        case .jsContext:
            let documentWorkerHandler = preloadedDocumentWorkerHandler ?? DocumentWorkerJSHandler()
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
                    updateStateAndQueues(for: worker, state: .failed)
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
                    updateStateAndQueues(for: worker, state: .failed)
                    return
                }
                if setup(documentWorkerHandler: documentWorkerHandler, runtime: .webView, for: worker) {
                    updateStateAndQueues(for: worker, state: .queued)
                    startWorkIfNeeded()
                } else {
                    release(documentWorkerHandler)
                    updateStateAndQueues(for: worker, state: .failed)
                }
            }
        }
    }

    @discardableResult
    private func setup(documentWorkerHandler: DocumentWorkerHandling, runtime: HandlerRuntime, for worker: Worker) -> Bool {
        documentWorkerHandler.workFile = worker.file
        documentWorkerHandler.shouldCacheWorkInput = worker.shouldCacheInput
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
                        case .recognizerData(let data), .fullText(let data), .structuredDocumentText(let data):
                            finishWork(work, in: worker) { $0?.on(.next(Update(work: work, kind: .extractedData(data: data)))) }
                        }

                    case .failure(let error):
                        DDLogError("DocumentWorkerController: work \(work.id) failed - \(error)")
                        finishWork(work, in: worker) { $0?.on(.next(Update(work: work, kind: .failed))) }
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
        guard let documentWorkerHandler = worker.handlersByRuntime[work.preferredRuntime] else {
            updateStateAndQueues(for: worker, state: .preparing)
            prepare(worker: worker, for: work)
            return
        }
        // Set worker state to running and append to proper queue.
        updateStateAndQueues(for: worker, state: .running)
        // Start work.
        worker.workStartTimes[work] = CFAbsoluteTimeGetCurrent()
        DDLogInfo("DocumentWorkerController: started \(work) in \(worker)")
        subject.on(.next(Update(work: work, kind: .inProgress)))
        switch work {
        case .recognizer:
            documentWorkerHandler.performAction(.recognizePDF(password: worker.password), workId: work.id)

        case .fullText(let pages):
            documentWorkerHandler.performAction(.getPDFFulltext(pages: pages, password: worker.password), workId: work.id)

        case .structuredDocumentText:
            documentWorkerHandler.performAction(.getStructuredDocumentText(contentType: worker.file.mimeType, password: worker.password), workId: work.id)
        }
        // Start another work if needed.
        startWorkIfNeeded()
    }

    private func finishWork(_ work: Work, in worker: Worker, completion: ((_ subject: PublishSubject<Update>?) -> Void)?) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            finishWork(work, worker: worker, completion: completion, controller: self)
        } else {
            accessQueue.async(flags: .barrier) { [weak self] in
                guard let self else { return }
                finishWork(work, worker: worker, completion: completion, controller: self)
            }
        }

        func finishWork(_ work: Work, worker: Worker, completion: ((_ subject: PublishSubject<Update>?) -> Void)?, controller: DocumentWorkerController) {
            logWorkDuration(work, worker: worker)
            let subject = worker.subjectsByWork.removeValue(forKey: work)
            controller.updateStateAndQueues(for: worker, state: worker.subjectsByWork.isEmpty ? .ready : .queued)
            DDLogInfo("DocumentWorkerController: finished \(work) in \(worker)")
            completion?(subject)
            controller.startWorkIfNeeded()

            func logWorkDuration(_ work: Work, worker: Worker) {
                guard let startTime = worker.workStartTimes.removeValue(forKey: work) else { return }
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                DDLogInfo("DocumentWorkerController: \(work) in \(worker) took \(String(format: "%.3f", duration))s")
            }
        }
    }

    func cancelWork(_ work: Work, in worker: Worker) {
        DDLogInfo("DocumentWorkerController: cancelled \(work) in \(worker)")
        finishWork(work, in: worker) { $0?.on(.next(Update(work: work, kind: .cancelled))) }
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
            for (work, subject) in worker.subjectsByWork {
                subject.on(.next(Update(work: work, kind: .cancelled)))
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
              ready.isEmpty,
              preparing.isEmpty,
              !Priority.inDescendingOrder.contains(where: { !queuedByPriority[$0, default: []].isEmpty || !runningByPriority[$0, default: []].isEmpty })
        else { return }
        preloadedDocumentWorkerHandler = DocumentWorkerJSHandler()
    }

    private func preloadWebViewDocumentWorkerIfNeeded() {
        guard webViewProvider != nil,
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
            return work.preferredRuntime == .webView && worker.handlersByRuntime[work.preferredRuntime] == nil
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
            let configuration = WKWebViewConfiguration()
            configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            let webView = webViewProvider.addWebView(configuration: configuration)
            let documentWorkerHandler = DocumentWorkerWebViewHandler(webView: webView, temporaryDirectory: temporaryDirectory, cleanup: cleanupClosure)
            accessQueue.async(flags: .barrier) {
                completion(documentWorkerHandler)
            }
        }

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
