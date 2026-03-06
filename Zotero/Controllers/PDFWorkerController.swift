//
//  PDFWorkerController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 3/2/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
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
        let shouldCacheData: Bool
        let priority: Priority
        fileprivate(set) var state: State = .pending
        fileprivate var subjectsByWork: OrderedDictionary<Work, PublishSubject<Update>> = [:]
        fileprivate var handler: PDFWorkerJSHandler?

        init(file: FileData, shouldCacheData: Bool, priority: Priority) {
            self.file = file
            self.shouldCacheData = shouldCacheData
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

    // Accessed only via accessQueue
    private var preparing: Set<Worker> = []
    private var ready: Set<Worker> = []
    private var queuedByPriority: [Priority: OrderedSet<Worker>] = [:]
    private var runningByPriority: [Priority: OrderedSet<Worker>] = [:]
    private var failed: Set<Worker> = []
    private var preloadedPDFWorkerHandler: PDFWorkerJSHandler?

    // MARK: Object Lifecycle
    init(fileStorage: FileStorage) {
        dispatchSpecificKey = DispatchSpecificKey<String>()
        accessQueueLabel = "org.zotero.PDFWorkerController.accessQueue"
        accessQueue = DispatchQueue(label: accessQueueLabel, qos: .userInteractive, attributes: .concurrent)
        accessQueue.setSpecific(key: dispatchSpecificKey, value: accessQueueLabel)
        self.fileStorage = fileStorage
        disposeBag = DisposeBag()
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.preloadPDFWorkerIfIdle()
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
                // Prepare worker handler.
                let pdfWorkerHandler = preloadedPDFWorkerHandler ?? PDFWorkerJSHandler()
                // Setup handler for worker, consume preloaded handler, just in case it was used, assign queued state and place in proper queue.
                setup(pdfWorkerHandler: pdfWorkerHandler, for: worker)
                preloadedPDFWorkerHandler = nil
                accessQueue.async(flags: .barrier) { [weak self] in
                    self?.preloadPDFWorkerIfIdle()
                }
                updateStateAndQueues(for: worker, state: .queued)
                // Start work if needed to run queued worker.
                startWorkIfNeeded()

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

    private func setup(pdfWorkerHandler: PDFWorkerJSHandler, for worker: Worker) {
        pdfWorkerHandler.workFile = worker.file
        pdfWorkerHandler.shouldCacheWorkData = worker.shouldCacheData
        setupObserver(in: worker, for: pdfWorkerHandler)
        worker.handler = pdfWorkerHandler

        func setupObserver(in worker: Worker, for pdfWorkerHandler: PDFWorkerJSHandler) {
            pdfWorkerHandler.observable.subscribe(onNext: { [weak self, weak worker] event in
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
        guard let pdfWorkerHandler = worker.handler, let work = worker.subjectsByWork.keys.first, let subject = worker.subjectsByWork[work] else {
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
            pdfWorkerHandler.recognize(workId: work.id)

        case .fullText(let pages):
            pdfWorkerHandler.getFullText(pages: pages, workId: work.id)
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
            // Immediately release worker handler and assign pending state to worker. If another work is queued for this worker, a new handler will be created.
            worker.handler = nil
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
        guard preloadedPDFWorkerHandler == nil,
              ready.isEmpty,
              preparing.isEmpty,
              !Priority.inDescendingOrder.contains(where: { !queuedByPriority[$0, default: []].isEmpty || !runningByPriority[$0, default: []].isEmpty })
        else { return }
        preloadedPDFWorkerHandler = PDFWorkerJSHandler()
    }
}
