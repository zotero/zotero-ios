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
    enum RemoteRecognizerIdentifier {
        case arXiv(String)
        case doi(String)
        case isbn(String)
        case title(String)

        var identifierWithPrefix: String {
            switch self {
            case .arXiv(let identifier):
                return "arXiv: \(identifier)"

            case .doi(let identifier):
                return "DOI: \(identifier)"

            case .isbn(let identifier):
                return "ISBN: \(identifier)"

            case .title(let identifier):
                return identifier
            }
        }

        var copyTagsAsAutomatic: Bool {
            switch self {
            case .isbn:
                return true

            case .arXiv, .doi, .title:
                return false
            }
        }
    }

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
        enum Kind: Hashable {
            case simple
            case createParentForItem(libraryId: LibraryIdentifier, key: String)
        }

        let file: FileData
        let kind: Kind
    }

    enum Error: Swift.Error {
        case cantStartPDFWorker
        case pdfWorkerError
        case recognizerFailed
        case remoteRecognizerFailed
        case noRemainingIdentifiersForLookup
        case unexpectedState
        case cantCreateParentForItem
    }

    struct Update {
        enum Kind {
            case failed(Error)
            case cancelled
            case enqueued
            case recognitionInProgress
            case remoteRecognitionInProgress(data: [String: Any])
            case identifierLookupInProgress(response: RemoteRecognizerResponse, identifier: String)
            case translated(itemResponse: ItemResponse)
            case createdParent(item: RItem)
        }

        let task: RecognizerTask
        let kind: Kind
    }

    enum RecognizerTaskState {
        case enqueued
        case recognitionInProgress
        case remoteRecognitionInProgress(data: [String: Any])
        case identifiersLookupInProgress(response: RemoteRecognizerResponse, currentIdentifier: RemoteRecognizerIdentifier, pendingIdentifiers: [RemoteRecognizerIdentifier])
    }

    // MARK: Properties
    private unowned let pdfWorkerController: PDFWorkerController
    private unowned let apiClient: ApiClient
    private unowned let translatorsController: TranslatorsAndStylesController
    private unowned let schemaController: SchemaController
    private unowned let dbStorage: DbStorage
    private unowned let dateParser: DateParser
    private let dispatchSpecificKey: DispatchSpecificKey<String>
    private let accessQueueLabel: String
    private let accessQueue: DispatchQueue
    private let backgroundQueue: DispatchQueue
    private let updatesSubject: PublishSubject<Update>
    var updates: Observable<Update> {
        updatesSubject.asObservable()
    }
    private let disposeBag: DisposeBag

    internal weak var webViewProvider: WebViewProvider?

    // Accessed only via accessQueue
    private static let maxConcurrentRecognizerTasks: Int = 1
    private var queue: OrderedDictionary<RecognizerTask, (state: RecognizerTaskState, observable: PublishSubject<Update>)> = [:]
    private var latestUpdates: [LibraryIdentifier: [String: Update.Kind]] = [:]
    private var lookupWebViewHandlersByRecognizerTask: [RecognizerTask: LookupWebViewHandler] = [:]

    // MARK: Object Lifecycle
    init(
        pdfWorkerController: PDFWorkerController,
        apiClient: ApiClient,
        translatorsController: TranslatorsAndStylesController,
        schemaController: SchemaController,
        dbStorage: DbStorage,
        dateParser: DateParser
    ) {
        self.pdfWorkerController = pdfWorkerController
        self.apiClient = apiClient
        self.translatorsController = translatorsController
        self.schemaController = schemaController
        self.dbStorage = dbStorage
        self.dateParser = dateParser
        dispatchSpecificKey = DispatchSpecificKey<String>()
        accessQueueLabel = "org.zotero.RecognizerController.accessQueue"
        accessQueue = DispatchQueue(label: accessQueueLabel, qos: .userInteractive, attributes: .concurrent)
        accessQueue.setSpecific(key: dispatchSpecificKey, value: accessQueueLabel)
        backgroundQueue = DispatchQueue(label: "org.zotero.RecognizerController.backgroundQueue", qos: .userInitiated)
        updatesSubject = PublishSubject()
        disposeBag = DisposeBag()
    }

    // MARK: Actions
    func queue(task: RecognizerTask, completion: ((_ observable: Observable<Update>?) -> Void)? = nil) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else {
                completion?(nil)
                return
            }
            if let (_, observable) = queue[task] {
                completion?(observable.asObservable())
                return
            }
            let state: RecognizerTaskState = .enqueued
            let observable: PublishSubject<Update> = PublishSubject()
            queue[task] = (state, observable)
            completion?(observable.asObservable())
            observable.subscribe(onNext: { [weak self] update in
                self?.updatesSubject.on(.next(update))
            }).disposed(by: disposeBag)

            emmitUpdate(for: task, observable: observable, kind: .enqueued)
            startRecognitionIfNeeded()
        }
    }

    private func emmitUpdate(for task: RecognizerTask, observable: PublishSubject<Update>, kind: Update.Kind) {
        let update = Update(task: task, kind: kind)
        if case .createParentForItem(let libraryId, let key) = task.kind {
            var libraryLatestUpdates = latestUpdates[libraryId, default: [:]]
            libraryLatestUpdates[key] = kind
            latestUpdates[libraryId] = libraryLatestUpdates
        }
        observable.on(.next(update))
    }

    private func startRecognitionIfNeeded() {
        let runningRecognizerTasksCount = queue.filter({
            switch $0.value.state {
            case .enqueued:
                return false

            case .recognitionInProgress, .remoteRecognitionInProgress, .identifiersLookupInProgress:
                return true
            }
        }).count
        guard runningRecognizerTasksCount < Self.maxConcurrentRecognizerTasks else { return }
        let tasks = queue.keys
        for task in tasks {
            guard let (state, observable) = queue[task] else { continue }
            switch state {
            case .enqueued:
                start(task: task, observable: observable)
                startRecognitionIfNeeded()
                return

            case .recognitionInProgress, .remoteRecognitionInProgress, .identifiersLookupInProgress:
                break
            }
        }

        func start(task: RecognizerTask, observable: PublishSubject<Update>) {
            queue[task] = (.recognitionInProgress, observable)
            emmitUpdate(for: task, observable: observable, kind: .recognitionInProgress)

            pdfWorkerController.queue(work: PDFWorkerController.PDFWork(file: task.file, kind: .recognizer)) { [weak self] pdfWorkerObservable in
                guard let self else { return }
                guard let pdfWorkerObservable else {
                    DDLogError("RecognizerController: \(task) - can't create start PDF worker")
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
                    DDLogError("RecognizerController: \(task) - recognizer failed")
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
                    DDLogInfo("RecognizerController: \(task) - extracted recognizer data")
                    startRemoteRecognition(for: task, with: data)

                case .extractedFullText:
                    DDLogError("RecognizerController: \(task) - PDF worker error")
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
            queue[task] = (.remoteRecognitionInProgress(data: data), observable)
            emmitUpdate(for: task, observable: observable, kind: .remoteRecognitionInProgress(data: data))

            apiClient.send(request: RecognizerRequest(parameters: data)).subscribe(
                onSuccess: { (response: (RemoteRecognizerResponse, HTTPURLResponse)) in
                    DDLogInfo("RecognizerController: \(task) - remote recognizer response received")
                    process(response: response.0)
                },
                onFailure: { [weak self] error in
                    DDLogError("RecognizerController: \(task) - remote recognizer request failed: \(error)")
                    self?.cleanupTask(for: task) { observable in
                        observable?.on(.next(Update(task: task, kind: .failed(error as! Error))))
                    }
                }
            )
            .disposed(by: disposeBag)
        }

        func process(response: RemoteRecognizerResponse) {
            var identifiers: [RemoteRecognizerIdentifier] = []
            if let identifier = response.arxiv {
                identifiers.append(.arXiv(identifier))
            }
            if let identifier = response.doi {
                identifiers.append(.doi(identifier))
            }
            if let identifier = response.isbn {
                identifiers.append(.isbn(identifier))
            }
            if let identifier = response.title {
                identifiers.append(.title(identifier))
            }
            guard !identifiers.isEmpty else {
                cleanupTask(for: task) { observable in
                    observable?.on(.next(Update(task: task, kind: .failed(.remoteRecognizerFailed))))
                }
                return
            }
            startIdentifiersLookup(for: task, with: response, pendingIdentifiers: identifiers)
        }
    }

    private func startIdentifiersLookup(for task: RecognizerTask, with response: RemoteRecognizerResponse, pendingIdentifiers: [RemoteRecognizerIdentifier]) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            guard let (state, _) = queue[task] else {
                startRecognitionIfNeeded()
                return
            }
            guard case .remoteRecognitionInProgress = state else {
                cleanupTask(for: task) { observable in
                    observable?.on(.next(Update(task: task, kind: .failed(.unexpectedState))))
                }
                return
            }
            lookupNextIdentifier(for: task, with: response, pendingIdentifiers: pendingIdentifiers)
        }
    }

    private func enqueueNextIdentifierLookup(for task: RecognizerTask) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            _enqueueNextIdentifierLookup(for: task)
        } else {
            accessQueue.async(flags: .barrier) {
                _enqueueNextIdentifierLookup(for: task)
            }
        }

        func _enqueueNextIdentifierLookup(for task: RecognizerTask) {
            guard let (state, _) = queue[task] else {
                startRecognitionIfNeeded()
                return
            }
            guard case .identifiersLookupInProgress(let response, _, let pendingIdentifiers) = state else {
                cleanupTask(for: task) { observable in
                    observable?.on(.next(Update(task: task, kind: .failed(.unexpectedState))))
                }
                return
            }
            lookupNextIdentifier(for: task, with: response, pendingIdentifiers: pendingIdentifiers)
        }
    }

    private func lookupNextIdentifier(for task: RecognizerTask, with response: RemoteRecognizerResponse, pendingIdentifiers: [RemoteRecognizerIdentifier]) {
        DDLogInfo("RecognizerController: \(task) - looking up next identifier from \(pendingIdentifiers)")
        guard let (_, observable) = queue[task] else {
            startRecognitionIfNeeded()
            return
        }
        guard !pendingIdentifiers.isEmpty else {
            cleanupTask(for: task) { observable in
                observable?.on(.next(Update(task: task, kind: .failed(.noRemainingIdentifiersForLookup))))
            }
            return
        }
        var remainingIdentifiers = pendingIdentifiers
        let identifier = remainingIdentifiers.removeFirst()
        queue[task] = (.identifiersLookupInProgress(response: response, currentIdentifier: identifier, pendingIdentifiers: remainingIdentifiers), observable)

        switch identifier {
        case .arXiv, .doi, .isbn:
            lookup(identifier: identifier.identifierWithPrefix, copyTagsAsAutomatic: identifier.copyTagsAsAutomatic, remainingIdentifiers: remainingIdentifiers)

        case .title(let title):
            use(title: title, with: response)
        }

        func lookup(identifier: String, copyTagsAsAutomatic: Bool, remainingIdentifiers: [RemoteRecognizerIdentifier]) {
            DDLogInfo("RecognizerController: \(task) - looking up identifier \(identifier)")
            guard let lookupWebViewHandler = getLookupWebViewHandler(for: task) else {
                enqueueNextIdentifierLookup(for: task)
                return
            }
            emmitUpdate(for: task, observable: observable, kind: .identifierLookupInProgress(response: response, identifier: identifier))
            lookupWebViewHandler.lookUp(identifier: identifier)

            func getLookupWebViewHandler(for task: RecognizerTask) -> LookupWebViewHandler? {
                if let lookupWebViewHandler = lookupWebViewHandlersByRecognizerTask[task] {
                    return lookupWebViewHandler
                }
                var lookupWebViewHandler: LookupWebViewHandler?
                DispatchQueue.main.sync { [weak self, weak webViewProvider] in
                    guard let self, let webViewProvider else { return }
                    let webView = webViewProvider.addWebView(configuration: nil)
                    lookupWebViewHandler = LookupWebViewHandler(webView: webView, translatorsController: translatorsController)
                }
                guard let lookupWebViewHandler else {
                    DDLogWarn("RecognizerController: \(task) - can't create LookupWebViewHandler instance")
                    return nil
                }
                lookupWebViewHandlersByRecognizerTask[task] = lookupWebViewHandler
                setupObserver(for: lookupWebViewHandler)
                return lookupWebViewHandler

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
                                    DDLogWarn("RecognizerController: \(task) - identifier not accepted by LookupWebViewHandler")
                                    enqueueNextIdentifierLookup(for: task)
                                }

                            case .item(let data):
                                guard data["identifier"] as? [String: String] != nil else {
                                    DDLogWarn("RecognizerController: \(task) - lookup item data don't contain identifier")
                                    return
                                }
                                guard data.count > 1 else { return }
                                if let error = data["error"] {
                                    DDLogWarn("RecognizerController: \(task) - lookup failed - \(error)")
                                    enqueueNextIdentifierLookup(for: task)
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
                                    DDLogWarn("RecognizerController: \(task) - parse failed")
                                    enqueueNextIdentifierLookup(for: task)
                                    return
                                }
                                if copyTagsAsAutomatic, !itemResponse.tags.isEmpty {
                                    itemResponse = itemResponse.copyWithAutomaticTags
                                }
                                createParentIfNeeded(for: task, with: itemResponse, schemaController: schemaController, dateParser: dateParser)
                            }

                        case .failure(let error):
                            DDLogError("RecognizerController: \(task) - identifier lookup failed - \(error)")
                            enqueueNextIdentifierLookup(for: task)
                        }
                    }
                }
            }
        }

        func use(title: String, with response: RemoteRecognizerResponse) {
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
            createParentIfNeeded(for: task, with: itemResponse, schemaController: schemaController, dateParser: dateParser)
        }

        func createParentIfNeeded(for task: RecognizerTask, with itemResponse: ItemResponse, schemaController: SchemaController, dateParser: DateParser) {
            switch task.kind {
            case .simple:
                cleanupTask(for: task) { observable in
                    observable?.on(.next(Update(task: task, kind: .translated(itemResponse: itemResponse))))
                }

            case .createParentForItem(let libraryId, let key):
                backgroundQueue.async { [weak self] in
                    guard let self else { return }
                    let response = itemResponse.copy(libraryId: libraryId, collectionKeys: [], tags: [])
                    var update: Update?
                    do {
                        try dbStorage.perform(on: backgroundQueue) { coordinator in
                            let items = try coordinator.perform(request: CreateTranslatedItemsDbRequest(responses: [response], schemaController: schemaController, dateParser: dateParser))
                            guard let parent = items.first else {
                                update = Update(task: task, kind: .failed(.cantCreateParentForItem))
                                return
                            }
                            try coordinator.perform(request: MoveItemsToParentDbRequest(itemKeys: [key], parentKey: parent.key, libraryId: libraryId))
                            update = Update(task: task, kind: .createdParent(item: parent))
                            coordinator.invalidate()
                        }
                    } catch let error {
                        DDLogError("RecognizerController: can't create parent for item - \(error)")
                        update = Update(task: task, kind: .failed(error as! Error))
                    }
                    cleanupTask(for: task) { observable in
                        if let update {
                            observable?.on(.next(update))
                        }
                    }
                }
            }
        }
    }

    func cancel(task: RecognizerTask) {
        cleanupTask(for: task) { observable in
            DDLogInfo("RecognizerController: cancelled \(task)")
            observable?.on(.next(Update(task: task, kind: .cancelled)))
        }
    }

    func cancellAllTasks() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            DDLogInfo("RecognizerController: cancel all tasks")
            // Immediatelly release all lookup web views.
            let keys = lookupWebViewHandlersByRecognizerTask.keys
            for key in keys {
                guard let webView = lookupWebViewHandlersByRecognizerTask.removeValue(forKey: key)?.webViewHandler.webView else { continue }
                DispatchQueue.main.async {
                    webView.removeFromSuperview()
                }
            }
            // Then cancel actual tasks, and send cancelled event for each queued task.
            let tasks = queue.keys
            for task in tasks {
                cancel(task: task)
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
            if case .createParentForItem(let libraryId, let key) = task.kind, var libraryLatestUpdates = latestUpdates[libraryId] {
                libraryLatestUpdates[key] = nil
                latestUpdates[libraryId] = libraryLatestUpdates
            }
            DDLogInfo("RecognizerController: \(task) - cleaned up")
            lookupWebViewHandlersByRecognizerTask.removeValue(forKey: task)?.removeFromSuperviewAsynchronously()
            completion(observable)
            startRecognitionIfNeeded()
        }
    }

    func latestUpdate(for key: String, libraryId: LibraryIdentifier) -> Update.Kind? {
        return accessQueue.sync { [weak self] in
            guard let self, let libraryLatestUpdates = latestUpdates[libraryId] else { return nil }
            return libraryLatestUpdates[key]
        }
    }
}
