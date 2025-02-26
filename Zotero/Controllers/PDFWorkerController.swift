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
        enum Kind {
            case recognizer
            case fullText
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

    enum PDFWorkState {
        case enqueued
        case inProgress
    }

    // MARK: Properties
    private let dispatchSpecificKey: DispatchSpecificKey<String>
    private let accessQueueLabel: String
    private let accessQueue: DispatchQueue
    private let disposeBag: DisposeBag

    weak var webViewProvider: WebViewProvider?

    // Accessed only via accessQueue
    private static let maxConcurrentPDFWorkers: Int = 1
    // Using an OrderedDictionary instead of an Array, so we can O(1) when cancelling a work that is still queued.
    private var queue: OrderedDictionary<PDFWork, PublishSubject<Update>> = [:]
    private var subjectsByPDFWork: [PDFWork: PublishSubject<Update>] = [:]
    private var pdfWorkerWebViewHandlersByPDFWork: [PDFWork: PDFWorkerWebViewHandler] = [:]
    private var statesByPDFWork: [PDFWork: PDFWorkState] = [:]

    // MARK: Object Lifecycle
    init() {
        dispatchSpecificKey = DispatchSpecificKey<String>()
        accessQueueLabel = "org.zotero.PDFWorkerController.accessQueue"
        accessQueue = DispatchQueue(label: accessQueueLabel, qos: .userInteractive, attributes: .concurrent)
        accessQueue.setSpecific(key: dispatchSpecificKey, value: accessQueueLabel)
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
            queue[work] = subject
            subjectsByPDFWork[work] = subject
            statesByPDFWork[work] = .enqueued

            startWorkIfNeeded()
        }
        return subject.asObservable()
    }

    private func startWorkIfNeeded() {
        guard pdfWorkerWebViewHandlersByPDFWork.count < Self.maxConcurrentPDFWorkers, !queue.isEmpty else { return }
        let (work, subject) = queue.removeFirst()
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
                    pdfWorkerWebViewHandler = PDFWorkerWebViewHandler(webView: webView)
                }
                pdfWorkerWebViewHandlersByPDFWork[work] = pdfWorkerWebViewHandler
            }
            guard let pdfWorkerWebViewHandler else {
                DDLogError("PDFWorkerController: can't create PDFWorkerWebViewHandler instance")
                cleanupPDFWorker(for: work).subscribe(onSuccess: { $0.on(.next(Update(work: work, kind: .failed))) })
                    .disposed(by: disposeBag)
                return
            }

            statesByPDFWork[work] = .inProgress
            setupObserver(for: pdfWorkerWebViewHandler)
            subject.on(.next(Update(work: work, kind: .inProgress)))
            switch work.kind {
            case .recognizer:
                pdfWorkerWebViewHandler.recognize(file: work.file)

            case .fullText:
                pdfWorkerWebViewHandler.getFullText(file: work.file)
            }

            func setupObserver(for pdfWorkerWebViewHandler: PDFWorkerWebViewHandler) {
                pdfWorkerWebViewHandler.observable
                    .subscribe(onNext: { [weak self] in
                        guard let self else { return }
                        process(result: $0)
                    })
                    .disposed(by: disposeBag)

                func process(result: Result<PDFWorkerWebViewHandler.PDFWorkerData, Error>) {
                    switch result {
                    case .success(let data):
                        switch data {
                        case .recognizerData(let data), .fullText(let data):
                            cleanupPDFWorker(for: work).subscribe(onSuccess: { $0.on(.next(Update(work: work, kind: .extractedData(data: data)))) })
                                .disposed(by: disposeBag)
                        }

                    case .failure(let error):
                        DDLogError("PDFWorkerController: recognizer failed - \(error)")
                        cleanupPDFWorker(for: work).subscribe(onSuccess: { $0.on(.next(Update(work: work, kind: .failed))) })
                            .disposed(by: disposeBag)
                    }
                }
            }
        }
    }

    func cancel(work: PDFWork) {
        DDLogInfo("PDFWorkerController: cancelled \(work)")
        cleanupPDFWorker(for: work).subscribe(onSuccess: { $0.on(.next(Update(work: work, kind: .cancelled))) })
            .disposed(by: disposeBag)
    }

    func cancellAllWorks() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            DDLogInfo("PDFWorkerController: cancel all works")
            // Immediatelly release all PDFWorker web views.
            pdfWorkerWebViewHandlersByPDFWork.values.forEach { $0.removeFromSuperviewAsynchronously() }
            pdfWorkerWebViewHandlersByPDFWork = [:]
            // Then cancel actual works, and send cancelled event for each queued work.
            let works = subjectsByPDFWork.keys + Array(queue.keys)
            for work in works {
                cancel(work: work)
            }
        }
    }

    private func cleanupPDFWorker(for work: PDFWork) -> Maybe<PublishSubject<Update>> {
        return Maybe.create { [weak self] maybe in
            guard let self else {
                maybe(.completed)
                return Disposables.create()
            }
            if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
                cleanup(for: work, maybe: maybe)
            } else {
                accessQueue.async(flags: .barrier) {
                    cleanup(for: work, maybe: maybe)
                }
            }
            return Disposables.create()
        }

        func cleanup(for work: PDFWork, maybe: (MaybeEvent<PublishSubject<Update>>) -> Void) {
            let subject = queue[work] ?? subjectsByPDFWork[work]
            queue[work] = nil
            subjectsByPDFWork[work] = nil
            statesByPDFWork[work] = nil
            DDLogInfo("PDFWorkerController: cleaned up for \(work)")
            pdfWorkerWebViewHandlersByPDFWork.removeValue(forKey: work)?.removeFromSuperviewAsynchronously()
            if let subject {
                maybe(.success(subject))
            } else {
                maybe(.completed)
            }
            startWorkIfNeeded()
        }
    }
}
