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
            case fullText(pages: [Int])
        }

        let file: FileData
        let kind: Kind
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

    weak var webViewProvider: WebViewProvider?

    // Accessed only via accessQueue
    private static let maxConcurrentPDFWorkers: Int = 1
    private var queue: [PDFWork] = []
    private var subjectsByPDFWork: [PDFWork: PublishSubject<Update>] = [:]
    private var pdfWorkerWebViewHandlersByPDFWork: [PDFWork: PDFWorkerWebViewHandler] = [:]

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
            queue.append(work)
            subjectsByPDFWork[work] = subject

            startWorkIfNeeded()
        }
        return subject.asObservable()
    }

    private func startWorkIfNeeded() {
        guard pdfWorkerWebViewHandlersByPDFWork.count < Self.maxConcurrentPDFWorkers, !queue.isEmpty else { return }
        let work = queue.removeFirst()
        guard let subject = subjectsByPDFWork[work] else {
            startWorkIfNeeded()
            return
        }
        start(work: work, subject: subject)
        startWorkIfNeeded()

        func start(work: PDFWork, subject: PublishSubject<Update>) {
            var pdfWorkerWebViewHandler = pdfWorkerWebViewHandlersByPDFWork[work]
            if pdfWorkerWebViewHandler == nil {
                DispatchQueue.main.sync { [weak webViewProvider] in
                    guard let webViewProvider else { return }
                    let configuration = WKWebViewConfiguration()
                    configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
                    let webView = webViewProvider.addWebView(configuration: configuration)
                    pdfWorkerWebViewHandler = PDFWorkerWebViewHandler(webView: webView, fileStorage: fileStorage)
                }
                pdfWorkerWebViewHandlersByPDFWork[work] = pdfWorkerWebViewHandler
            }
            guard let pdfWorkerWebViewHandler else {
                DDLogError("PDFWorkerController: can't create PDFWorkerWebViewHandler instance")
                cleanupPDFWorker(for: work) { $0?.on(.next(Update(work: work, kind: .failed))) }
                return
            }

            setupObserver(for: pdfWorkerWebViewHandler)
            subject.on(.next(Update(work: work, kind: .inProgress)))
            switch work.kind {
            case .recognizer:
                pdfWorkerWebViewHandler.recognize(file: work.file)

            case .fullText(let pages):
                pdfWorkerWebViewHandler.getFullText(file: work.file, pages: pages)
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
            let works = subjectsByPDFWork.keys + queue
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
            controller.queue.removeAll(where: { $0 == work })
            controller.subjectsByPDFWork[work] = nil
            DDLogInfo("PDFWorkerController: cleaned up for \(work)")
            controller.pdfWorkerWebViewHandlersByPDFWork.removeValue(forKey: work)?.removeFromSuperviewAsynchronously()
            completion?(subject)
            controller.startWorkIfNeeded()
        }
    }
}
