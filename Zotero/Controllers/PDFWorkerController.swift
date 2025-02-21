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
            case extractedRecognizerData(data: [String: Any])
            case extractedFullText(data: [String: Any])
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

    internal weak var webViewProvider: WebViewProvider?

    // Accessed only via accessQueue
    private static let maxConcurrentPDFWorkers: Int = 1
    private var queue: OrderedDictionary<PDFWork, (state: PDFWorkState, observable: PublishSubject<Update>)> = [:]
    private var pdfWorkerWebViewHandlersByPDFWork: [PDFWork: PDFWorkerWebViewHandler] = [:]

    // MARK: Object Lifecycle
    init() {
        dispatchSpecificKey = DispatchSpecificKey<String>()
        accessQueueLabel = "org.zotero.PDFWorkerController.accessQueue"
        accessQueue = DispatchQueue(label: accessQueueLabel, qos: .userInteractive, attributes: .concurrent)
        accessQueue.setSpecific(key: dispatchSpecificKey, value: accessQueueLabel)
        disposeBag = DisposeBag()
    }

    // MARK: Actions
    func queue(work: PDFWork, completion: @escaping (_ observable: Observable<Update>?) -> Void) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            if let (_, observable) = queue[work] {
                completion(observable.asObservable())
                return
            }
            let state: PDFWorkState = .enqueued
            let observable: PublishSubject<Update> = PublishSubject()
            queue[work] = (state, observable)
            completion(observable.asObservable())

            startWorkIfNeeded()
        }
    }

    private func startWorkIfNeeded() {
        guard pdfWorkerWebViewHandlersByPDFWork.count < Self.maxConcurrentPDFWorkers else { return }
        let works = queue.keys
        for work in works {
            guard let (state, observable) = queue[work] else { continue }
            switch state {
            case .enqueued:
                start(work: work, observable: observable)
                startWorkIfNeeded()
                return

            case .inProgress:
                break
            }
        }

        func start(work: PDFWork, observable: PublishSubject<Update>) {
            var pdfWorkerWebViewHandler = pdfWorkerWebViewHandlersByPDFWork[work]
            if pdfWorkerWebViewHandler == nil {
                DispatchQueue.main.sync { [weak webViewProvider] in
                    guard let webViewProvider else { return }
                    let configuration = WKWebViewConfiguration()
                    configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
                    let webView = webViewProvider.addWebView(configuration: configuration)
                    pdfWorkerWebViewHandler = PDFWorkerWebViewHandler(webView: webView)
                }
            }
            guard let pdfWorkerWebViewHandler else {
                DDLogError("PDFWorkerController: can't create PDFWorkerWebViewHandler instance")
                cleanupPDFWorker(for: work) { observable in
                    observable?.on(.next(Update(work: work, kind: .failed)))
                }
                return
            }
            pdfWorkerWebViewHandlersByPDFWork[work] = pdfWorkerWebViewHandler
            setupObserver(for: pdfWorkerWebViewHandler)
            queue[work] = (.inProgress, observable)
            observable.on(.next(Update(work: work, kind: .inProgress)))
            switch work.kind {
            case .recognizer:
                pdfWorkerWebViewHandler.recognize(file: work.file)

            case .fullText:
                pdfWorkerWebViewHandler.getFullText(file: work.file)
            }

            func setupObserver(for pdfWorkerWebViewHandler: PDFWorkerWebViewHandler) {
                pdfWorkerWebViewHandler.observable
                    .subscribe(onNext: { process(result: $0) })
                    .disposed(by: disposeBag)

                func process(result: Result<PDFWorkerWebViewHandler.PDFWorkerData, Error>) {
                    switch result {
                    case .success(let data):
                        switch data {
                        case .recognizerData(let data):
                            cleanupPDFWorker(for: work) { observable in
                                observable?.on(.next(Update(work: work, kind: .extractedRecognizerData(data: data))))
                            }

                        case .fullText(let data):
                            cleanupPDFWorker(for: work) { observable in
                                observable?.on(.next(Update(work: work, kind: .extractedFullText(data: data))))
                            }
                        }

                    case .failure(let error):
                        DDLogError("PDFWorkerController: recognizer failed - \(error)")
                        cleanupPDFWorker(for: work) { observable in
                            observable?.on(.next(Update(work: work, kind: .failed)))
                        }
                    }
                }
            }
        }
    }

    func cancel(work: PDFWork) {
        cleanupPDFWorker(for: work) { observable in
            DDLogInfo("PDFWorkerController: cancelled \(work)")
            observable?.on(.next(Update(work: work, kind: .cancelled)))
        }
    }

    func cancellAllWorks() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            DDLogInfo("PDFWorkerController: cancel all works")
            // Immediatelly release all PDFWorker web views.
            let keys = pdfWorkerWebViewHandlersByPDFWork.keys
            for key in keys {
                pdfWorkerWebViewHandlersByPDFWork.removeValue(forKey: key)?.removeFromSuperviewAsynchronously()
            }
            // Then cancel actual works, and send cancelled event for each queued work.
            let works = queue.keys
            for work in works {
                cancel(work: work)
            }
        }
    }

    private func cleanupPDFWorker(for work: PDFWork, completion: @escaping (_ observable: PublishSubject<Update>?) -> Void) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            cleanup(for: work, completion: completion)
        } else {
            accessQueue.async(flags: .barrier) {
                cleanup(for: work, completion: completion)
            }
        }

        func cleanup(for work: PDFWork, completion: @escaping (_ observable: PublishSubject<Update>?) -> Void) {
            let observable = queue.removeValue(forKey: work).flatMap({ $0.observable })
            DDLogInfo("PDFWorkerController: cleaned up for \(work)")
            pdfWorkerWebViewHandlersByPDFWork.removeValue(forKey: work)?.removeFromSuperviewAsynchronously()
            completion(observable)
            startWorkIfNeeded()
        }
    }
}
