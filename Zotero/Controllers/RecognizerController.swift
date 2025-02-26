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
    enum RecognizerIdentifier {
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

    struct Task: Hashable {
        enum Kind: Hashable {
            case simple
            case createParentForItem(libraryId: LibraryIdentifier, key: String)
        }

        let file: FileData
        let kind: Kind
    }

    enum Error: Swift.Error {
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

        let task: Task
        let kind: Kind
    }

    enum TaskState {
        case enqueued
        case recognitionInProgress
        case remoteRecognitionInProgress(data: [String: Any])
        case identifiersLookupInProgress(response: RemoteRecognizerResponse, currentIdentifier: RecognizerIdentifier, pendingIdentifiers: [RecognizerIdentifier])
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
    private static let maxConcurrentTasks: Int = 1
    // Using an OrderedDictionary instead of an Array, so we can O(1) when cancelling a work that is still queued.
    private var queue: OrderedDictionary<Task, PublishSubject<Update>> = [:]
    private var subjectsByTask: [Task: PublishSubject<Update>] = [:]
    private var lookupWebViewHandlersByTask: [Task: LookupWebViewHandler] = [:]
    private var statesByTask: [Task: TaskState] = [:]
    private var latestUpdates: [LibraryIdentifier: [String: Update.Kind]] = [:]

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
    func queue(task: Task) -> Observable<Update> {
        let subject = PublishSubject<Update>()
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if let existingSubject = subjectsByTask[task] {
                existingSubject.subscribe(subject)
                    .disposed(by: disposeBag)
                return
            }
            queue[task] = subject
            statesByTask[task] = .enqueued

            emmitUpdate(for: task, subject: subject, kind: .enqueued)
            startRecognitionIfNeeded()
        }
        return subject.asObservable()
    }

    private func emmitUpdate(for task: Task, subject: PublishSubject<Update>, kind: Update.Kind) {
        let update = Update(task: task, kind: kind)
        if case .createParentForItem(let libraryId, let key) = task.kind {
            var libraryLatestUpdates = latestUpdates[libraryId, default: [:]]
            libraryLatestUpdates[key] = kind
            latestUpdates[libraryId] = libraryLatestUpdates
        }
        subject.on(.next(update))
        updatesSubject.on(.next(update))
    }

    private func startRecognitionIfNeeded() {
        guard subjectsByTask.count < Self.maxConcurrentTasks, !queue.isEmpty else { return }
        let (task, subject) = queue.removeFirst()
        start(task: task, subject: subject)

        func start(task: Task, subject: PublishSubject<Update>) {
            subjectsByTask[task] = subject
            statesByTask[task] = .recognitionInProgress
            emmitUpdate(for: task, subject: subject, kind: .recognitionInProgress)

            pdfWorkerController.queue(work: PDFWorkerController.PDFWork(file: task.file, kind: .recognizer))
                .subscribe(onNext: { update in
                    process(update: update)
                })
                .disposed(by: disposeBag)

            func process(update: PDFWorkerController.Update) {
                switch update.kind {
                case .failed:
                    DDLogError("RecognizerController: \(task) - recognizer failed")
                    cleanupTask(for: task).subscribe(onSuccess: { $0.on(.next(Update(task: task, kind: .failed(.recognizerFailed)))) })
                        .disposed(by: disposeBag)

                case .cancelled:
                    cleanupTask(for: task).subscribe(onSuccess: { $0.on(.next(Update(task: task, kind: .cancelled))) })
                        .disposed(by: disposeBag)

                case .inProgress:
                    break

                case .extractedData(let data):
                    switch update.work.kind {
                    case .recognizer:
                        DDLogInfo("RecognizerController: \(task) - extracted recognizer data")
                        startRemoteRecognition(for: task, with: data)

                    case .fullText:
                        DDLogError("RecognizerController: \(task) - PDF worker error")
                        cleanupTask(for: task).subscribe(onSuccess: { $0.on(.next(Update(task: task, kind: .failed(.pdfWorkerError)))) })
                            .disposed(by: disposeBag)
                    }
                }
            }
        }
    }

    private func startRemoteRecognition(for task: Task, with data: [String: Any]) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            guard let subject = subjectsByTask[task] else {
                startRecognitionIfNeeded()
                return
            }
            statesByTask[task] = .remoteRecognitionInProgress(data: data)
            emmitUpdate(for: task, subject: subject, kind: .remoteRecognitionInProgress(data: data))

            apiClient.send(request: RecognizerRequest(parameters: data)).subscribe(
                onSuccess: { (response: (RemoteRecognizerResponse, HTTPURLResponse)) in
                    DDLogInfo("RecognizerController: \(task) - remote recognizer response received")
                    process(response: response.0)
                },
                onFailure: { [weak self] error in
                    guard let self else { return }
                    DDLogError("RecognizerController: \(task) - remote recognizer request failed: \(error)")
                    cleanupTask(for: task).subscribe(onSuccess: { $0.on(.next(Update(task: task, kind: .failed(error as! Error)))) })
                        .disposed(by: disposeBag)
                }
            )
            .disposed(by: disposeBag)
        }

        func process(response: RemoteRecognizerResponse) {
            var identifiers: [RecognizerIdentifier] = []
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
                cleanupTask(for: task).subscribe(onSuccess: { $0.on(.next(Update(task: task, kind: .failed(.remoteRecognizerFailed)))) })
                    .disposed(by: disposeBag)
                return
            }
            enqueueNextIdentifierLookup(for: task) { state in
                guard case .remoteRecognitionInProgress = state else { return nil }
                return (response, identifiers)
            }
        }
    }

    private func enqueueNextIdentifierLookup(
        for task: Task,
        getResponseAndIdentifiers: @escaping (TaskState) -> (RemoteRecognizerResponse, [RecognizerIdentifier])? = { state -> (RemoteRecognizerResponse, [RecognizerIdentifier])? in
            guard case .identifiersLookupInProgress(let response, _, let pendingIdentifiers) = state else { return nil }
            return (response, pendingIdentifiers)
        }
    ) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            _enqueueNextIdentifierLookup(for: task)
        } else {
            accessQueue.async(flags: .barrier) { [weak self] in
                guard let self else { return }
                _enqueueNextIdentifierLookup(for: task)
            }
        }

        func _enqueueNextIdentifierLookup(for task: Task) {
            guard let state = statesByTask[task] else {
                startRecognitionIfNeeded()
                return
            }
            guard let (response, pendingIdentifiers) = getResponseAndIdentifiers(state) else {
                cleanupTask(for: task).subscribe(onSuccess: { $0.on(.next(Update(task: task, kind: .failed(.unexpectedState)))) })
                    .disposed(by: disposeBag)
                return
            }
            lookupNextIdentifier(for: task, with: response, pendingIdentifiers: pendingIdentifiers)
        }
    }

    private func lookupNextIdentifier(for task: Task, with response: RemoteRecognizerResponse, pendingIdentifiers: [RecognizerIdentifier]) {
        DDLogInfo("RecognizerController: \(task) - looking up next identifier from \(pendingIdentifiers)")
        guard let subject = subjectsByTask[task] else {
            startRecognitionIfNeeded()
            return
        }
        guard !pendingIdentifiers.isEmpty else {
            cleanupTask(for: task).subscribe(onSuccess: { $0.on(.next(Update(task: task, kind: .failed(.noRemainingIdentifiersForLookup)))) })
                .disposed(by: disposeBag)
            return
        }
        var remainingIdentifiers = pendingIdentifiers
        let identifier = remainingIdentifiers.removeFirst()
        statesByTask[task] = .identifiersLookupInProgress(response: response, currentIdentifier: identifier, pendingIdentifiers: remainingIdentifiers)

        switch identifier {
        case .arXiv, .doi, .isbn:
            lookup(identifier: identifier.identifierWithPrefix, copyTagsAsAutomatic: identifier.copyTagsAsAutomatic, remainingIdentifiers: remainingIdentifiers)

        case .title(let title):
            use(title: title, with: response)
        }

        func lookup(identifier: String, copyTagsAsAutomatic: Bool, remainingIdentifiers: [RecognizerIdentifier]) {
            DDLogInfo("RecognizerController: \(task) - looking up identifier \(identifier)")
            guard let lookupWebViewHandler = getLookupWebViewHandler(for: task) else {
                enqueueNextIdentifierLookup(for: task)
                return
            }
            emmitUpdate(for: task, subject: subject, kind: .identifierLookupInProgress(response: response, identifier: identifier))
            lookupWebViewHandler.lookUp(identifier: identifier)

            func getLookupWebViewHandler(for task: Task) -> LookupWebViewHandler? {
                if let lookupWebViewHandler = lookupWebViewHandlersByTask[task] {
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
                lookupWebViewHandlersByTask[task] = lookupWebViewHandler
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

        func createParentIfNeeded(for task: Task, with itemResponse: ItemResponse, schemaController: SchemaController, dateParser: DateParser) {
            switch task.kind {
            case .simple:
                cleanupTask(for: task).subscribe(onSuccess: { $0.on(.next(Update(task: task, kind: .translated(itemResponse: itemResponse)))) })
                    .disposed(by: disposeBag)

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
                    cleanupTask(for: task).subscribe(onSuccess: {
                        if let update {
                            $0.on(.next(update))
                        }
                    })
                        .disposed(by: disposeBag)
                }
            }
        }
    }

    func cancel(task: Task) {
        DDLogInfo("RecognizerController: cancelled \(task)")
        cleanupTask(for: task).subscribe(onSuccess: { $0.on(.next(Update(task: task, kind: .cancelled))) })
            .disposed(by: disposeBag)
    }

    func cancellAllTasks() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            DDLogInfo("RecognizerController: cancel all tasks")
            // Immediatelly release all lookup web views.
            lookupWebViewHandlersByTask.values.forEach { $0.removeFromSuperviewAsynchronously() }
            lookupWebViewHandlersByTask = [:]
            // Then cancel actual tasks, and send cancelled event for each queued task.
            let tasks = subjectsByTask.keys + Array(queue.keys)
            for task in tasks {
                cancel(task: task)
            }
        }
    }

    private func cleanupTask(for task: Task) -> Maybe<PublishSubject<Update>> {
        return Maybe.create { [weak self] maybe in
            guard let self else {
                maybe(.completed)
                return Disposables.create()
            }
            if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
                cleanup(for: task, maybe: maybe)
            } else {
                accessQueue.async(flags: .barrier) {
                    cleanup(for: task, maybe: maybe)
                }
            }
            return Disposables.create()
        }

        func cleanup(for task: Task, maybe: (MaybeEvent<PublishSubject<Update>>) -> Void) {
            let subject = queue[task] ?? subjectsByTask[task]
            queue[task] = nil
            subjectsByTask[task] = nil
            statesByTask[task] = nil
            if case .createParentForItem(let libraryId, let key) = task.kind, var libraryLatestUpdates = latestUpdates[libraryId] {
                libraryLatestUpdates[key] = nil
                latestUpdates[libraryId] = libraryLatestUpdates
            }
            DDLogInfo("RecognizerController: \(task) - cleaned up")
            lookupWebViewHandlersByTask.removeValue(forKey: task)?.removeFromSuperviewAsynchronously()
            if let subject {
                maybe(.success(subject))
            } else {
                maybe(.completed)
            }
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
