//
//  PDFWorkerController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 3/2/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit
import OrderedCollections

import CocoaLumberjackSwift
import RxSwift

final class PDFWorkerController {
    // MARK: Types
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

    class Worker: Hashable {
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
        let priority: Priority
        fileprivate(set) var state: State = .pending
        fileprivate var subjectsByWork: OrderedDictionary<Work, PublishSubject<Update>> = [:]
        fileprivate var webViewHandler: PDFWorkerWebViewHandler?

        init(file: FileData, priority: Priority) {
            self.file = file
            self.priority = priority
        }

        deinit {
            webViewHandler?.removeFromSuperviewAsynchronously()
        }

        static func == (lhs: PDFWorkerController.Worker, rhs: PDFWorkerController.Worker) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    enum Work: Hashable {
        case recognizer
        case fullText(pages: [Int]?)

        var id: String {
            switch self {
            case .recognizer:
                return "recognizer"

            case .fullText(let pages):
                guard let pages else { return "fullText(pages: nil)" }
                return "fullText(pages: [\(pages.map(String.init).joined(separator: ", "))])"
            }
        }

        init?(id: String) {
            if id == "recognizer" {
                self = .recognizer
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

    weak var webViewProvider: WebViewProvider? {
        didSet {
            guard webViewProvider !== oldValue, webViewProvider != nil else { return }
            accessQueue.async(flags: .barrier) { [weak self] in
                self?.preloadPDFWorkerIfIdle()
            }
        }
    }

    // Accessed only via accessQueue
    private var preparing: Set<Worker> = []
    private var ready: Set<Worker> = []
    private var queuedByPriority: [Priority: OrderedSet<Worker>] = [:]
    private var runningByPriority: [Priority: OrderedSet<Worker>] = [:]
    private var failed: Set<Worker> = []
    private var preparingPreloadedPDFWorkerWebViewHandler: Bool = false
    private var preloadedPDFWorkerWebViewHandler: PDFWorkerWebViewHandler?

    // MARK: Object Lifecycle
    init(fileStorage: FileStorage) {
        dispatchSpecificKey = DispatchSpecificKey<String>()
        accessQueueLabel = "org.zotero.PDFWorkerController.accessQueue"
        accessQueue = DispatchQueue(label: accessQueueLabel, qos: .userInteractive, attributes: .concurrent)
        accessQueue.setSpecific(key: dispatchSpecificKey, value: accessQueueLabel)
        self.fileStorage = fileStorage
        disposeBag = DisposeBag()
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
                // Assign preparing state and place in proper queue, then prepare web view handler.
                updateStateAndQueues(for: worker, state: .preparing)
                // Prepare web view handler.
                if let preloadedPDFWorkerWebViewHandler {
                    // There is a preloaded web view handler, worker can finish setup within the access queue.
                    if setup(pdfWorkerWebViewHandler: preloadedPDFWorkerWebViewHandler, for: worker) {
                        // Setup succeded, consume preloaded web view handler, assign queued state and place in proper queue.
                        self.preloadedPDFWorkerWebViewHandler = nil
                        updateStateAndQueues(for: worker, state: .queued)
                        // Start work if needed to run queued worker.
                        startWorkIfNeeded()
                    } else {
                        // Setup failed, assign failed state, so owner can either retry by queueing another work, or can cleanup.
                        updateStateAndQueues(for: worker, state: .failed)
                    }
                } else {
                    // A new web view handler needs to be created asynchronously, if successful.
                    createPDFWorkerWebViewHandler(fileStorage: fileStorage) { [weak self, weak worker] pdfWorkerWebViewHandler in
                        guard let self, let worker else { return }
                        guard let pdfWorkerWebViewHandler else {
                            // Failure happens within the access queue.
                            updateStateAndQueues(for: worker, state: .failed)
                            return
                        }
                        // Otherwise, a web view handler was created asynchronously, and completion is called within a new work in the access queue.
                        // Setup newly created web view handler.
                        if setup(pdfWorkerWebViewHandler: pdfWorkerWebViewHandler, for: worker) {
                            // Setup succeded, assign queued state and place in proper queue.
                            updateStateAndQueues(for: worker, state: .queued)
                            // Start work if needed to run queued worker.
                            startWorkIfNeeded()
                        } else {
                            // Setup failed, assign failed state, so owner can either retry by queueing another work, or can cleanup.
                            updateStateAndQueues(for: worker, state: .failed)
                        }
                    }
                }

            case .preparing:
                // A new work is queued to a worker that is still preparing, do nothing.
                break

            case .ready:
                // A new work is queued to a worker that is ready with no works (e.g. a worker that finished its works, but was kept by the user).
                // Assign queued state, place in proper queue, and start work if needed.
                updateStateAndQueues(for: worker, state: .queued)
                startWorkIfNeeded()

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

    private func setup(pdfWorkerWebViewHandler: PDFWorkerWebViewHandler, for worker: Worker) -> Bool {
        guard copy(workFile: worker.file, to: pdfWorkerWebViewHandler) else { return false }
        setupObserver(in: worker, for: pdfWorkerWebViewHandler)
        worker.webViewHandler = pdfWorkerWebViewHandler
        return true

        func copy(workFile file: FileData, to pdfWorkerWebViewHandler: PDFWorkerWebViewHandler) -> Bool {
            if pdfWorkerWebViewHandler.workFile != nil {
                // This shouldn't happen
                DDLogWarn("PDFWorkerController: PDFWorkerWebViewHandler work file already set")
                return true
            }
            let destination = pdfWorkerWebViewHandler.temporaryDirectory.copy(withName: file.name, ext: file.ext)
            do {
                try fileStorage.copy(from: file.createUrl().path, to: destination)
            } catch {
                DDLogError("PDFWorkerController: failed to copy file for PDF worker - \(error)")
                return false
            }
            pdfWorkerWebViewHandler.workFile = file
            return true
        }

        func setupObserver(in worker: Worker, for pdfWorkerWebViewHandler: PDFWorkerWebViewHandler) {
            pdfWorkerWebViewHandler.observable.subscribe(onNext: { [weak self, weak worker] event in
                guard let self else { return }
                accessQueue.async(flags: .barrier) { [weak self, weak worker] in
                    guard let self, let worker, let work = Work(id: event.workId), worker.subjectsByWork[work] != nil else { return }
                    switch event.result {
                    case .success(let data):
                        switch data {
                        case .recognizerData(let data), .fullText(let data):
                            finishWork(work, in: worker) { $0?.on(.next(Update(work: work, kind: .extractedData(data: data)))) }
                        }

                    case .failure(let error):
                        DDLogError("PDFWorkerController: recognizer failed - \(error)")
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
        guard let pdfWorkerWebViewHandler = worker.webViewHandler, let work = worker.subjectsByWork.keys.first, let subject = worker.subjectsByWork[work] else {
            // This shouldn't happen, move worker back to ready state.
            updateStateAndQueues(for: worker, state: .ready)
            startWorkIfNeeded()
            return
        }
        // Set worker state to running and append to proper queue.
        updateStateAndQueues(for: worker, state: .running)
        // Start work.
        subject.on(.next(Update(work: work, kind: .inProgress)))
        switch work {
        case .recognizer:
            pdfWorkerWebViewHandler.recognize(workId: work.id)

        case .fullText(let pages):
            pdfWorkerWebViewHandler.getFullText(pages: pages, workId: work.id)
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

        func finishWork(_ work: Work, worker: Worker, completion: ((_ subject: PublishSubject<Update>?) -> Void)?, controller: PDFWorkerController) {
            let subject = worker.subjectsByWork.removeValue(forKey: work)
            controller.updateStateAndQueues(for: worker, state: worker.subjectsByWork.isEmpty ? .ready : .queued)
            DDLogInfo("PDFWorkerController: finished \(work) in \(worker)")
            completion?(subject)
            controller.startWorkIfNeeded()
        }
    }

    func cancelWork(_ work: Work, in worker: Worker) {
        DDLogInfo("PDFWorkerController: cancelled \(work) in \(worker)")
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

        func cancelAllWorks(in worker: Worker, startNextWorkIfNeeded: Bool, controller: PDFWorkerController) {
            DDLogInfo("PDFWorkerController: cancel all works in \(worker)")
            // Immediatelly release worker web view handler and assign pending state to worker. If another work is queued for this worker, a new handler will be created.
            worker.webViewHandler?.removeFromSuperviewAsynchronously()
            worker.webViewHandler = nil
            controller.updateStateAndQueues(for: worker, state: .pending)
            for (work, subject) in worker.subjectsByWork {
                subject.on(.next(Update(work: work, kind: .cancelled)))
            }
            worker.subjectsByWork.removeAll()
            guard startNextWorkIfNeeded else { return }
            controller.startWorkIfNeeded()
            controller.preloadPDFWorkerIfIdle()
        }
    }

    func cleanupWorker(_ worker: Worker) {
        cancelAllWorks(in: worker)
    }

    func cancellAllWorks() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            DDLogInfo("PDFWorkerController: cancel all works")
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

    private func preloadPDFWorkerIfIdle() {
        guard preloadedPDFWorkerWebViewHandler == nil,
              !preparingPreloadedPDFWorkerWebViewHandler,
              ready.isEmpty,
              preparing.isEmpty,
              !Priority.inDescendingOrder.contains(where: { !queuedByPriority[$0, default: []].isEmpty || !runningByPriority[$0, default: []].isEmpty })
        else { return }
        preparingPreloadedPDFWorkerWebViewHandler = true
        createPDFWorkerWebViewHandler(fileStorage: fileStorage) { [weak self] pdfWebViewHandler in
            guard let self else { return }
            preloadedPDFWorkerWebViewHandler = pdfWebViewHandler
            preparingPreloadedPDFWorkerWebViewHandler = false
        }
    }

    private func createPDFWorkerWebViewHandler(fileStorage: FileStorage, completion: @escaping (PDFWorkerWebViewHandler?) -> Void) {
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
            let pdfWorkerWebViewHandler = PDFWorkerWebViewHandler(webView: webView, temporaryDirectory: temporaryDirectory, cleanup: cleanupClosure)
            accessQueue.async(flags: .barrier) {
                completion(pdfWorkerWebViewHandler)
            }
        }

        func prepareTemporaryWorkerDirectory(fileStorage: FileStorage) -> File? {
            guard let workerHtmlUrl = Bundle.main.url(forResource: "worker", withExtension: "html") else {
                DDLogError("PDFWorkerController: worker.html not found")
                return nil
            }
            guard let workerJsUrl = Bundle.main.url(forResource: "worker", withExtension: "js", subdirectory: "Bundled/pdf_worker") else {
                DDLogError("PDFWorkerController: worker.js not found")
                return nil
            }
            let temporaryDirectory = Files.temporaryDirectory
            do {
                try fileStorage.copy(from: workerHtmlUrl.path, to: temporaryDirectory.copy(withName: "worker", ext: "html"))
                try fileStorage.copy(from: workerJsUrl.path, to: temporaryDirectory.copy(withName: "worker", ext: "js"))
                let cmapsDirectory = Files.file(from: workerJsUrl).directory.appending(relativeComponent: "cmaps")
                try fileStorage.copyContents(of: cmapsDirectory, to: temporaryDirectory.appending(relativeComponent: "cmaps"))
                let standardFontsDirectory = Files.file(from: workerJsUrl).directory.appending(relativeComponent: "standard_fonts")
                try fileStorage.copyContents(of: standardFontsDirectory, to: temporaryDirectory.appending(relativeComponent: "standard_fonts"))
            } catch {
                DDLogError("PDFWorkerController: failed to prepare worker directory - \(error)")
                removeTemporaryWorkerDirectory(temporaryDirectory, fileStorage: fileStorage)
                return nil
            }
            return temporaryDirectory
        }

        func removeTemporaryWorkerDirectory(_ directory: File, fileStorage: FileStorage) {
            DispatchQueue.global(qos: .background).async { [weak fileStorage] in
                guard let fileStorage else { return }
                do {
                    try fileStorage.remove(directory)
                } catch {
                    DDLogError("PDFWorkerController: failed to remove worker directory - \(error)")
                }
            }
        }
    }
}
