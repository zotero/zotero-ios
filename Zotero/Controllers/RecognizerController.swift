//
//  RecognizerController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 11/2/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit
import OrderedCollections

import CocoaLumberjackSwift
import RxSwift

final class RecognizerController {
    // MARK: Types
    struct RemoteRecognizerResponse: Decodable {
        struct Author: Decodable {
            let firstName, lastName: String?
        }
        let arxiv, doi, isbn: String?
        let abstract, language: String?
        let title, type, year, pages, volume, url, issue, issn, container, publisher: String?
        let authors: [Author]
    }

    struct RecognizerRequest: ApiResponseRequest {
        typealias Response = RemoteRecognizerResponse
        let parameters: [String: Any]?

        var endpoint: ApiEndpoint { .other(URL(string: "https://services.zotero.org/recognizer/recognize")!) }
        var httpMethod: ApiHttpMethod { .post }
        var encoding: ApiParameterEncoding { .json }
        var headers: [String: String]? { nil }

        init(parameters: [String: Any]) {
            self.parameters = parameters
        }
    }

    struct RecognizerTask: Hashable {
        let file: FileData
    }

    enum Error: Swift.Error {
        case cantStartPDFWorker
        case pdfWorkerError
        case recognizerFailed
        case remoteRecognizerFailed
        case cantCreateLookupWebViewHandler
        case identifierNotAccepted
        case lookupFailed
        case parseFailed
    }

    struct Update {
        enum Kind {
            case failed(Error)
            case cancelled
            case recognitionInProgress
            case remoteRecognitionInProgress(data: [String: Any])
            case identifierLookupInProgress(response: RemoteRecognizerResponse)
            case translated(item: ItemResponse)
        }

        let task: RecognizerTask
        let kind: Kind
    }

    enum RecognizerTaskState {
        case enqueued
        case recognitionInProgress
        case remoteRecognitionInProgress
        case identifierLookupInProgress
    }

    // MARK: Properties
    private unowned let pdfWorkerController: PDFWorkerController
    private unowned let apiClient: ApiClient
    private unowned let translatorsController: TranslatorsAndStylesController
    private unowned let schemaController: SchemaController
    private let dispatchSpecificKey: DispatchSpecificKey<String>
    private let accessQueueLabel: String
    private let accessQueue: DispatchQueue
    private let disposeBag: DisposeBag

    internal weak var webViewProvider: WebViewProvider?

    // Accessed only via accessQueue
    private static let maxConcurrentRecognizerTasks: Int = 1
    private var queue: OrderedDictionary<RecognizerTask, (state: RecognizerTaskState, observable: PublishSubject<Update>)> = [:]
    private var lookupWebViewHandlersByRecognizerTask: [RecognizerTask: LookupWebViewHandler] = [:]

    // MARK: Object Lifecycle
    init(pdfWorkerController: PDFWorkerController, apiClient: ApiClient, translatorsController: TranslatorsAndStylesController, schemaController: SchemaController) {
        self.pdfWorkerController = pdfWorkerController
        self.apiClient = apiClient
        self.translatorsController = translatorsController
        self.schemaController = schemaController
        dispatchSpecificKey = DispatchSpecificKey<String>()
        accessQueueLabel = "org.zotero.RecognizerController.accessQueue"
        accessQueue = DispatchQueue(label: accessQueueLabel, qos: .userInteractive, attributes: .concurrent)
        accessQueue.setSpecific(key: dispatchSpecificKey, value: accessQueueLabel)
        disposeBag = DisposeBag()
    }

    // MARK: Actions
    func queue(task: RecognizerTask, completion: @escaping (_ observable: PublishSubject<Update>?) -> Void) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            if let (_, observable) = queue[task] {
                completion(observable)
                return
            }
            let state: RecognizerTaskState = .enqueued
            let observable: PublishSubject<Update> = PublishSubject()
            queue[task] = (state, observable)
            completion(observable)

            startRecognitionIfNeeded()
        }
    }

    private func startRecognitionIfNeeded() {
        let recognitionInProgressCount = queue.filter({ $0.value.state == .recognitionInProgress }).count
        guard recognitionInProgressCount < Self.maxConcurrentRecognizerTasks else { return }
        let tasks = queue.keys
        for task in tasks {
            guard let (state, observable) = queue[task] else { continue }
            switch state {
            case .enqueued:
                start(task: task, observable: observable)
                startRecognitionIfNeeded()
                return

            case .recognitionInProgress, .remoteRecognitionInProgress, .identifierLookupInProgress:
                break
            }
        }

        func start(task: RecognizerTask, observable: PublishSubject<Update>) {
            queue[task] = (.recognitionInProgress, observable)
            observable.on(.next(Update(task: task, kind: .recognitionInProgress)))

            pdfWorkerController.queue(work: PDFWorkerController.PDFWork(file: task.file, kind: .recognizer)) { [weak self] pdfWorkerObservable in
                guard let self else { return }
                guard let pdfWorkerObservable else {
                    DDLogError("RecognizerController: can't create start PDF worker")
                    cleanupTask(for: task) { observable in
                        observable?.on(.next(Update(task: task, kind: .failed(.cantStartPDFWorker))))
                    }
                    return
                }
                pdfWorkerObservable
                    .subscribe(onNext: { process(update: $0) })
                    .disposed(by: disposeBag)
            }

            func process(update: PDFWorkerController.Update) {
                switch update.kind {
                case .failed:
                    DDLogError("RecognizerController: recognizer failed")
                    cleanupTask(for: task) { observable in
                        observable?.on(.next(Update(task: task, kind: .failed(.recognizerFailed))))
                    }

                case .cancelled:
                    cleanupTask(for: task) { observable in
                        observable?.on(.next(Update(task: task, kind: .cancelled)))
                    }

                case .inProgress:
                    break

                case .extractedRecognizerData(data: let data):
                    DDLogInfo("RecognizerController: extracted recognizer data")
                    startRemoteRecognition(for: task, with: data)

                case .extractedFullText:
                    DDLogError("RecognizerController: PDF worker error")
                    cleanupTask(for: task) { observable in
                        observable?.on(.next(Update(task: task, kind: .failed(.pdfWorkerError))))
                    }
                }
            }
        }
    }

    private func startRemoteRecognition(for task: RecognizerTask, with data: [String: Any]) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            guard let (_, observable) = queue[task] else {
                startRecognitionIfNeeded()
                return
            }
            queue[task] = (.remoteRecognitionInProgress, observable)
            observable.on(.next(Update(task: task, kind: .remoteRecognitionInProgress(data: data))))

            apiClient.send(request: RecognizerRequest(parameters: data)).subscribe(
                onSuccess: { [weak self] (response: (RemoteRecognizerResponse, HTTPURLResponse)) in
                    DDLogInfo("RecognizerController: remote recognizer response received")
                    guard let self else { return }
                    process(response: response.0)
                },
                onFailure: { [weak self] error in
                    DDLogError("RecognizerController: remote recognizer request failed: \(error)")
                    self?.cleanupTask(for: task) { observable in
                        observable?.on(.next(Update(task: task, kind: .failed(error as! Error))))
                    }
                }
            )
            .disposed(by: disposeBag)
        }

        func process(response: RemoteRecognizerResponse) {
            var identifier: String?
            var copyTagsAsAutomatic = false
            if let arxiv = response.arxiv {
                identifier = "arXiv: \(arxiv)"
            } else if let doi = response.doi {
                identifier = "DOI: \(doi)"
            } else if let isbn = response.isbn {
                identifier = "ISBN: \(isbn)"
                copyTagsAsAutomatic = true
            }
            if let identifier {
                startIdentifierLookup(for: task, with: identifier, response: response, copyTagsAsAutomatic: copyTagsAsAutomatic)
                return
            }
            if let title = response.title {
                let creators = response.authors.map({ CreatorResponse(creatorType: "author", firstName: $0.firstName, lastName: $0.lastName) })
                var fields: [KeyBaseKeyPair: String] = [:]
                fields[KeyBaseKeyPair(key: FieldKeys.Item.title, baseKey: nil)] = title
                fields[KeyBaseKeyPair(key: FieldKeys.Item.abstract, baseKey: nil)] = response.abstract
                fields[KeyBaseKeyPair(key: FieldKeys.Item.date, baseKey: nil)] = response.year
                fields[KeyBaseKeyPair(key: FieldKeys.Item.pages, baseKey: nil)] = response.pages
                fields[KeyBaseKeyPair(key: FieldKeys.Item.volume, baseKey: nil)] = response.volume
                fields[KeyBaseKeyPair(key: FieldKeys.Item.url, baseKey: nil)] = response.url
                fields[KeyBaseKeyPair(key: FieldKeys.Item.language, baseKey: nil)] = response.language
                let rawType: String
                if response.type == "book-chapter" {
                    rawType = "bookSection"
                    fields[KeyBaseKeyPair(key: FieldKeys.Item.bookTitle, baseKey: nil)] = response.container
                    fields[KeyBaseKeyPair(key: FieldKeys.Item.publisher, baseKey: nil)] = response.publisher
                } else {
                    rawType = "journalArticle"
                    fields[KeyBaseKeyPair(key: FieldKeys.Item.issue, baseKey: nil)] = response.issue
                    fields[KeyBaseKeyPair(key: FieldKeys.Item.issn, baseKey: nil)] = response.issn
                    fields[KeyBaseKeyPair(key: FieldKeys.Item.publicationTitle, baseKey: nil)] = response.container
                }
                let accessDate = Date()

                let itemResponse = ItemResponse(
                    rawType: rawType,
                    key: KeyGenerator.newKey,
                    library: LibraryResponse(id: 0, name: "", type: "", links: nil),
                    parentKey: nil,
                    collectionKeys: [],
                    links: nil,
                    parsedDate: nil,
                    isTrash: false,
                    version: 0,
                    dateModified: accessDate,
                    dateAdded: accessDate,
                    fields: fields,
                    tags: [],
                    creators: creators,
                    relations: [:],
                    createdBy: nil,
                    lastModifiedBy: nil,
                    rects: nil,
                    paths: nil
                )
                cleanupTask(for: task) { observable in
                    observable?.on(.next(Update(task: task, kind: .translated(item: itemResponse))))
                }
                return
            }
            cleanupTask(for: task) { observable in
                observable?.on(.next(Update(task: task, kind: .failed(.remoteRecognizerFailed))))
            }
        }
    }

    private func startIdentifierLookup(for task: RecognizerTask, with identifier: String, response: RemoteRecognizerResponse, copyTagsAsAutomatic: Bool) {
        accessQueue.async(flags: .barrier) { [weak self] in
            DDLogInfo("RecognizerController: starting identifier lookup - \(identifier)")
            guard let self else { return }
            guard let (_, observable) = queue[task] else {
                startRecognitionIfNeeded()
                return
            }
            var lookupWebViewHandler = lookupWebViewHandlersByRecognizerTask[task]
            if lookupWebViewHandler == nil {
                DispatchQueue.main.sync { [weak webViewProvider] in
                    guard let webViewProvider else { return }
                    let webView = webViewProvider.addWebView(configuration: nil)
                    lookupWebViewHandler = LookupWebViewHandler(webView: webView, translatorsController: self.translatorsController)
                }
            }
            guard let lookupWebViewHandler else {
                DDLogError("RecognizerController: can't create LookupWebViewHandler instance")
                cleanupTask(for: task) { observable in
                    observable?.on(.next(Update(task: task, kind: .failed(.cantCreateLookupWebViewHandler))))
                }
                return
            }
            lookupWebViewHandlersByRecognizerTask[task] = lookupWebViewHandler
            setupObserver(for: lookupWebViewHandler)
            queue[task] = (.identifierLookupInProgress, observable)
            observable.on(.next(Update(task: task, kind: .identifierLookupInProgress(response: response))))
            lookupWebViewHandler.lookUp(identifier: identifier)

            func setupObserver(for lookupWebViewHandler: LookupWebViewHandler) {
                lookupWebViewHandler.observable
                    .subscribe(onNext: { process(result: $0) })
                    .disposed(by: disposeBag)

                func process(result: Result<LookupWebViewHandler.LookupData, Swift.Error>) {
                    switch result {
                    case .success(let data):
                        switch data {
                        case .identifiers(let identifiers):
                            if identifiers.isEmpty {
                                DDLogError("RecognizerController: identifier not accepted by LookupWebViewHandler")
                                cleanupTask(for: task) { observable in
                                    observable?.on(.next(Update(task: task, kind: .failed(.identifierNotAccepted))))
                                }
                            }

                        case .item(let data):
                            guard data["identifier"] as? [String: String] != nil else {
                                DDLogWarn("RecognizerController: lookup item data don't contain identifier")
                                return
                            }
                            guard data.count > 1 else { return }
                            if let error = data["error"] {
                                DDLogError("RecognizerController: lookup failed - \(error)")
                                cleanupTask(for: task) { observable in
                                    observable?.on(.next(Update(task: task, kind: .failed(.lookupFailed))))
                                }
                                return
                            }
                            guard let itemData = data["data"] as? [[String: Any]],
                                  let item = itemData.first.flatMap({
                                      var item = $0
                                      item[FieldKeys.Item.abstract] = item[FieldKeys.Item.abstract] ?? response.abstract
                                      item[FieldKeys.Item.language] = item[FieldKeys.Item.language] ?? response.language
                                      return item
                                  }),
                                  var itemResponse = try? ItemResponse(translatorResponse: item, schemaController: schemaController)
                            else {
                                cleanupTask(for: task) { observable in
                                    observable?.on(.next(Update(task: task, kind: .failed(.parseFailed))))
                                }
                                return
                            }
                            if copyTagsAsAutomatic, !itemResponse.tags.isEmpty {
                                itemResponse = itemResponse.copyWithAutomaticTags
                            }
                            cleanupTask(for: task) { observable in
                                observable?.on(.next(Update(task: task, kind: .translated(item: itemResponse))))
                            }
                        }

                    case .failure(let error):
                        DDLogError("RecognizerController: identifier lookup failed - \(error)")
                        cleanupTask(for: task) { observable in
                            observable?.on(.next(Update(task: task, kind: .failed(error as! RecognizerController.Error))))
                        }
                    }
                }
            }
        }
    }

    private func cleanupTask(for task: RecognizerTask, completion: @escaping (_ observable: PublishSubject<Update>?) -> Void) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            cleanup(for: task, completion: completion)
        } else {
            accessQueue.async(flags: .barrier) {
                cleanup(for: task, completion: completion)
            }
        }

        func cleanup(for task: RecognizerTask, completion: @escaping (_ observable: PublishSubject<Update>?) -> Void) {
            let observable = queue.removeValue(forKey: task).flatMap({ $0.observable })
            DDLogInfo("RecognizerController: cleaned up for \(task)")
            lookupWebViewHandlersByRecognizerTask.removeValue(forKey: task)?.removeFromSuperviewAsynchronously()
            completion(observable)
            startRecognitionIfNeeded()
        }
    }
}
