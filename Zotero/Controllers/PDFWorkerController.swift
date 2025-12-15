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
    struct PDFWork: Hashable {
        enum Kind: Hashable {
            case recognizer
            case fullText(pages: [Int]?)
        }

        enum Priority: Hashable {
            case `default`
            case high
        }

        let file: FileData
        let kind: Kind
        let priority: Priority
    }

    struct Update {
        enum Kind {
            case failed
            case cancelled
            case inProgress
            case extractedData(data: [String: Any])
        }

        let work: PDFWork
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
    private static let maxDefaultPriorityConcurrentPDFWorkers: Int = 1
    private static let maxHighPriorityConcurrentPDFWorkers: Int = 3
    private var defaultPriorityQueue: [PDFWork] = []
    private var defaultPriorityRunningCount: Int = 0
    private var highPriorityQueue: [PDFWork] = []
    private var highPriorityRunningCount: Int = 0
    private var subjectsByPDFWork: [PDFWork: PublishSubject<Update>] = [:]
    private var pdfWorkerWebViewHandlersByPDFWork: [PDFWork: PDFWorkerWebViewHandler] = [:]
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
    func queue(work: PDFWork) -> Observable<Update> {
        let subject = PublishSubject<Update>()
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if let existingSubject = subjectsByPDFWork[work] {
                existingSubject.bind(to: subject).disposed(by: disposeBag)
                return
            }
            switch work.priority {
            case .default:
                defaultPriorityQueue.append(work)

            case .high:
                highPriorityQueue.append(work)
            }
            subjectsByPDFWork[work] = subject

            startWorkIfNeeded()
        }
        return subject.asObservable()
    }

    private func startWorkIfNeeded() {
        var work: PDFWork?
        if !highPriorityQueue.isEmpty, highPriorityRunningCount < Self.maxHighPriorityConcurrentPDFWorkers {
            work = highPriorityQueue.removeFirst()
            highPriorityRunningCount += 1
        } else if !defaultPriorityQueue.isEmpty, defaultPriorityRunningCount < Self.maxDefaultPriorityConcurrentPDFWorkers {
            work = defaultPriorityQueue.removeFirst()
            defaultPriorityRunningCount += 1
        }
        guard let work else { return }
        guard let subject = subjectsByPDFWork[work] else {
            startWorkIfNeeded()
            return
        }
        start(work: work, subject: subject)
        startWorkIfNeeded()

        func start(work: PDFWork, subject: PublishSubject<Update>) {
            var pdfWorkerWebViewHandler = pdfWorkerWebViewHandlersByPDFWork[work]
            if pdfWorkerWebViewHandler == nil {
                if let preloadedPDFWorkerWebViewHandler {
                    pdfWorkerWebViewHandler = preloadedPDFWorkerWebViewHandler
                    self.preloadedPDFWorkerWebViewHandler = nil
                } else {
                    pdfWorkerWebViewHandler = createPDFWorkerWebViewHandler()
                }
                pdfWorkerWebViewHandlersByPDFWork[work] = pdfWorkerWebViewHandler
            }
            guard let pdfWorkerWebViewHandler else {
                DDLogError("PDFWorkerController: can't create PDFWorkerWebViewHandler instance")
                cleanupPDFWorker(for: work) { $0?.on(.next(Update(work: work, kind: .failed))) }
                return
            }

            guard copyPDFWorker(file: work.file, to: pdfWorkerWebViewHandler.temporaryDirectory) else {
                cleanupPDFWorker(for: work) { $0?.on(.next(Update(work: work, kind: .failed))) }
                return
            }

            setupObserver(for: pdfWorkerWebViewHandler)
            subject.on(.next(Update(work: work, kind: .inProgress)))
            switch work.kind {
            case .recognizer:
                pdfWorkerWebViewHandler.recognize(fileName: work.file.fileName)

            case .fullText(let pages):
                pdfWorkerWebViewHandler.getFullText(fileName: work.file.fileName, pages: pages)
            }

            func copyPDFWorker(file: FileData, to directory: File) -> Bool {
                let destination = directory.copy(withName: file.name, ext: file.ext)
                do {
                    try fileStorage.copy(from: file.createUrl().path, to: destination)
                } catch {
                    DDLogError("PDFWorkerController: failed to copy file for PDF worker - \(error)")
                    return false
                }
                return true
            }

            func setupObserver(for pdfWorkerWebViewHandler: PDFWorkerWebViewHandler) {
                pdfWorkerWebViewHandler.observable.subscribe(onNext: { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let data):
                        switch data {
                        case .recognizerData(let data), .fullText(let data):
                            cleanupPDFWorker(for: work) { $0?.on(.next(Update(work: work, kind: .extractedData(data: data)))) }
                        }
                        
                    case .failure(let error):
                        DDLogError("PDFWorkerController: recognizer failed - \(error)")
                        cleanupPDFWorker(for: work) { $0?.on(.next(Update(work: work, kind: .failed))) }
                    }
                })
                .disposed(by: disposeBag)
            }
        }
    }

    func cancel(work: PDFWork) {
        DDLogInfo("PDFWorkerController: cancelled \(work)")
        cleanupPDFWorker(for: work) { $0?.on(.next(Update(work: work, kind: .cancelled))) }
    }

    func cancellAllWorks() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            DDLogInfo("PDFWorkerController: cancel all works")
            // Immediatelly release all PDFWorker web views.
            pdfWorkerWebViewHandlersByPDFWork.values.forEach { $0.removeFromSuperviewAsynchronously() }
            pdfWorkerWebViewHandlersByPDFWork = [:]
            // Then cancel actual works, and send cancelled event for each queued work.
            let works = subjectsByPDFWork.keys + highPriorityQueue + defaultPriorityQueue
            for work in works {
                cancel(work: work)
            }
        }
    }

    private func cleanupPDFWorker(for work: PDFWork, completion: ((_ subject: PublishSubject<Update>?) -> Void)?) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            cleanup(for: work, completion: completion, controller: self)
        } else {
            accessQueue.async(flags: .barrier) { [weak self] in
                guard let self else { return }
                cleanup(for: work, completion: completion, controller: self)
            }
        }

        func cleanup(for work: PDFWork, completion: ((_ subject: PublishSubject<Update>?) -> Void)?, controller: PDFWorkerController) {
            let subject = controller.subjectsByPDFWork[work]
            switch work.priority {
            case .default:
                controller.defaultPriorityQueue.removeAll(where: { $0 == work })
                defaultPriorityRunningCount -= 1

            case .high:
                controller.highPriorityQueue.removeAll(where: { $0 == work })
                highPriorityRunningCount -= 1
            }
            controller.subjectsByPDFWork[work] = nil
            DDLogInfo("PDFWorkerController: cleaned up for \(work)")
            controller.pdfWorkerWebViewHandlersByPDFWork.removeValue(forKey: work)?.removeFromSuperviewAsynchronously()
            completion?(subject)
            controller.startWorkIfNeeded()
            controller.preloadPDFWorkerIfIdle()
        }
    }

    private func preloadPDFWorkerIfIdle() {
        guard preloadedPDFWorkerWebViewHandler == nil, pdfWorkerWebViewHandlersByPDFWork.isEmpty else { return }
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
