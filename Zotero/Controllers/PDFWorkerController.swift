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
        enum State {
            case pending
            case queued
            case running
        }

        let id = UUID()
        let file: FileData
        let priority: Priority
        fileprivate var state: State = .pending
        fileprivate var subjectsByWork: OrderedDictionary<Work, PublishSubject<Update>> = [:]

        init(file: FileData, priority: Priority) {
            self.file = file
            self.priority = priority
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
    private var queuesByPriority: [Priority: OrderedSet<Worker>] = [:]
    private var runningByPriority: [Priority: OrderedSet<Worker>] = [:]
    private var pdfWorkerWebViewHandlersByWorker: [Worker: PDFWorkerWebViewHandler] = [:]
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
            case .pending:
                // Add to proper priority queue and start work if needed.
                var queue = queuesByPriority[worker.priority, default: []]
                queue.append(worker)
                queuesByPriority[worker.priority] = queue
                worker.state = .queued
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

    private func startWorkIfNeeded() {
        var worker: Worker?
        var running: OrderedSet<Worker>!
        for priority in Priority.inDescendingOrder {
            var queue = queuesByPriority[priority, default: []]
            running = runningByPriority[priority, default: []]
            if !queue.isEmpty, running.count < priority.maxConcurrentWorkers {
                worker = queue.removeFirst()
                queuesByPriority[priority] = queue
                break
            }
        }
        guard let worker else { return }
        guard let work = worker.subjectsByWork.keys.first, let subject = worker.subjectsByWork[work] else {
            // This shouldn't happen, move worker back to pending state.
            worker.state = .pending
            startWorkIfNeeded()
            return
        }
        guard let pdfWorkerWebViewHandler = pdfWorkerWebViewHandler(for: worker), copyIfNeeded(workFile: worker.file, to: pdfWorkerWebViewHandler) else {
            // Set worker to pending, so owner can retry to queue another work, or end its session.
            finishWork(work, in: worker, explicitNextState: .pending) { $0?.on(.next(Update(work: work, kind: .failed))) }
            worker.state = .pending
            startWorkIfNeeded()
            return
        }
        running.append(worker)
        runningByPriority[worker.priority] = running
        worker.state = .running
        start(work: work, in: worker, using: pdfWorkerWebViewHandler, subject: subject)
        startWorkIfNeeded()

        func pdfWorkerWebViewHandler(for worker: Worker) -> PDFWorkerWebViewHandler? {
            var pdfWorkerWebViewHandler = pdfWorkerWebViewHandlersByWorker[worker]
            if pdfWorkerWebViewHandler == nil {
                if let preloadedPDFWorkerWebViewHandler {
                    pdfWorkerWebViewHandler = preloadedPDFWorkerWebViewHandler
                    self.preloadedPDFWorkerWebViewHandler = nil
                } else {
                    pdfWorkerWebViewHandler = createPDFWorkerWebViewHandler()
                }
                if let pdfWorkerWebViewHandler {
                    setupObserver(in: worker, for: pdfWorkerWebViewHandler)
                }
                pdfWorkerWebViewHandlersByWorker[worker] = pdfWorkerWebViewHandler
            }
            guard let pdfWorkerWebViewHandler else {
                DDLogError("PDFWorkerController: can't create PDFWorkerWebViewHandler instance")
                return nil
            }
            return pdfWorkerWebViewHandler

            func setupObserver(in worker: Worker, for pdfWorkerWebViewHandler: PDFWorkerWebViewHandler) {
                pdfWorkerWebViewHandler.observable.subscribe(onNext: { [weak self, weak worker] event in
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
                })
                .disposed(by: disposeBag)
            }
        }

        func copyIfNeeded(workFile file: FileData, to pdfWorkerWebViewHandler: PDFWorkerWebViewHandler) -> Bool {
            if pdfWorkerWebViewHandler.workFile != nil {
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

        func start(work: Work, in worker: Worker, using pdfWorkerWebViewHandler: PDFWorkerWebViewHandler, subject: PublishSubject<Update>) {
            subject.on(.next(Update(work: work, kind: .inProgress)))
            switch work {
            case .recognizer:
                pdfWorkerWebViewHandler.recognize(workId: work.id)

            case .fullText(let pages):
                pdfWorkerWebViewHandler.getFullText(pages: pages, workId: work.id)
            }
        }
    }

    private func updateQueues(for worker: Worker) {
        // Is called only by callers already in access queue.
        var queue = queuesByPriority[worker.priority, default: []]
        var running = runningByPriority[worker.priority, default: []]
        switch worker.state {
        case .pending:
            queue.remove(worker)
            running.remove(worker)

        case .queued:
            queue.append(worker)
            running.remove(worker)

        case .running:
            queue.remove(worker)
            running.append(worker)
        }
        queuesByPriority[worker.priority] = queue
        runningByPriority[worker.priority] = running
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
            // Immediatelly release worker web view handler. If another work is queued for this worker, a new handler will be created.
            controller.pdfWorkerWebViewHandlersByWorker.removeValue(forKey: worker)?.removeFromSuperviewAsynchronously()
            worker.state = .pending
            controller.updateQueues(for: worker)
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
            // Immediatelly release all werker web view handlers.
            pdfWorkerWebViewHandlersByWorker.values.forEach { $0.removeFromSuperviewAsynchronously() }
            pdfWorkerWebViewHandlersByWorker = [:]
            var workers: OrderedSet<Worker> = []
            for priority in Priority.inDescendingOrder {
                workers.formUnion(queuesByPriority[priority, default: []])
                workers.formUnion(runningByPriority[priority, default: []])
            }
            for worker in workers {
                cancelAllWorks(in: worker, startNextWorkIfNeeded: false)
            }
        }
    }

    private func finishWork(_ work: Work, in worker: Worker, explicitNextState: Worker.State? = nil, completion: ((_ subject: PublishSubject<Update>?) -> Void)?) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            finishWork(work, worker: worker, explicitNextState: explicitNextState, completion: completion, controller: self)
        } else {
            accessQueue.async(flags: .barrier) { [weak self] in
                guard let self else { return }
                finishWork(work, worker: worker, explicitNextState: explicitNextState, completion: completion, controller: self)
            }
        }

        func finishWork(_ work: Work, worker: Worker, explicitNextState: Worker.State?, completion: ((_ subject: PublishSubject<Update>?) -> Void)?, controller: PDFWorkerController) {
            let subject = worker.subjectsByWork.removeValue(forKey: work)
            worker.state = explicitNextState ?? (worker.subjectsByWork.isEmpty ? .pending : .queued)
            // Update queues according to new worker state.
            controller.updateQueues(for: worker)
            DDLogInfo("PDFWorkerController: finished \(work) in \(worker)")
            completion?(subject)
            controller.startWorkIfNeeded()
        }
    }

    private func preloadPDFWorkerIfIdle() {
        guard preloadedPDFWorkerWebViewHandler == nil, pdfWorkerWebViewHandlersByWorker.isEmpty else { return }
        preloadedPDFWorkerWebViewHandler = createPDFWorkerWebViewHandler()
    }

    private func createPDFWorkerWebViewHandler() -> PDFWorkerWebViewHandler? {
        guard let temporaryDirectory = prepareTemporaryWorkerDirectory(fileStorage: fileStorage) else { return nil }
        let cleanupClosure: () -> Void = { [weak fileStorage] in
            guard let fileStorage else { return }
            removeTemporaryWorkerDirectory(temporaryDirectory, fileStorage: fileStorage)
        }

        var pdfWorkerWebViewHandler: PDFWorkerWebViewHandler?
        DispatchQueue.main.sync { [weak self] in
            guard let self, let webViewProvider else { return }
            let configuration = WKWebViewConfiguration()
            configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            let webView = webViewProvider.addWebView(configuration: configuration)
            pdfWorkerWebViewHandler = PDFWorkerWebViewHandler(webView: webView, temporaryDirectory: temporaryDirectory, cleanup: cleanupClosure)
        }
        if pdfWorkerWebViewHandler == nil {
            removeTemporaryWorkerDirectory(temporaryDirectory, fileStorage: fileStorage)
        }
        return pdfWorkerWebViewHandler

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
