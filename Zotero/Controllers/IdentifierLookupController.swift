//
//  IdentifierLookupController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 22/6/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit
import OrderedCollections

import CocoaLumberjackSwift
import RxSwift

protocol IdentifierLookupWebViewProvider: AnyObject {
    func addWebView() -> WKWebView
}

protocol IdentifierLookupPresenter: AnyObject {
    func isPresenting() -> Bool
}

final class IdentifierLookupController {
    // MARK: Types
    struct Update {
        enum Kind {
            case lookupError(error: Swift.Error)
            case identifiersDetected(identifiers: [String])
            case lookupInProgress(identifier: String)
            case lookupFailed(identifier: String)
            case parseFailed(identifier: String)
            case itemCreationFailed(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)])
            case itemStored(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)])
            case pendingAttachments(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)])
            case finishedAllLookups
        }

        let kind: Kind
        let lookupData: [LookupData]
    }
    
    struct LookupData {
        enum State: CustomStringConvertible {
            case enqueued
            case inProgress
            case failed
            case translated(TranslatedLookupData)
            
            struct TranslatedLookupData {
                let response: ItemResponse
                let attachments: [(Attachment, URL)]
                let libraryId: LibraryIdentifier
                let collectionKeys: Set<String>
            }
            
            var description: String {
                switch self {
                case .enqueued:
                    return "enqueued"
                    
                case .inProgress:
                    return "inProgress"
                    
                case .failed:
                    return "failed"
                    
                case .translated:
                    return "translated"
                }
            }
            
            var canTransition: Bool {
                // [translated, failed] are final states
                switch self {
                case .enqueued, .inProgress:
                    return true

                case .translated, .failed:
                    return false
                }
            }

            static func isTransitionValid(from: Self, to: Self) -> Bool {
                // enqueued is initial state
                // enqueued -> [inProgress, failed]
                // inProgress -> [translated, failed]
                switch (from, to) {
                case (.enqueued, .inProgress), (.enqueued, .failed), (.inProgress, .translated), (.inProgress, .failed):
                    return true

                default:
                    return false
                }
            }
        }
        
        let identifier: String
        let state: State
    }
    
    // MARK: Properties
    let observable: PublishSubject<Update>
    private let dispatchSpecificKey: DispatchSpecificKey<String>
    private let accessQueueLabel: String
    private let accessQueue: DispatchQueue
    private let backgroundQueue: DispatchQueue
    private let backgroundScheduler: SerialDispatchQueueScheduler
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let translatorsController: TranslatorsAndStylesController
    private unowned let schemaController: SchemaController
    private unowned let dateParser: DateParser
    private unowned let remoteFileDownloader: RemoteAttachmentDownloader
    private let disposeBag: DisposeBag
    
    private var lookupData: OrderedDictionary<String, LookupData> = [:]
    private var lookupSavedCount = 0
    private var lookupFailedCount = 0
    private var lookupTotalCount: Int {
        lookupData.count
    }
    private var lookupRemainingCount: Int {
        lookupTotalCount - lookupSavedCount - lookupFailedCount
    }
    var batchData: (savedCount: Int, failedCount: Int, totalCount: Int) {
        var savedCount = 0
        var failedCount = 0
        var totalCount = 0

        accessQueue.sync { [weak self] in
            guard let self else { return }
            savedCount = lookupSavedCount
            failedCount = lookupFailedCount
            totalCount = lookupTotalCount
        }
        
        return (savedCount, failedCount, totalCount)
    }

    internal weak var webViewProvider: IdentifierLookupWebViewProvider?
    internal weak var presenter: IdentifierLookupPresenter? {
        didSet {
            guard presenter == nil, oldValue != nil else { return }
            cleanupLookupIfNeeded(force: false) { [weak self] cleaned in
                guard let self, cleaned else { return }
                observable.on(.next(Update(kind: .finishedAllLookups, lookupData: [])))
            }
        }
    }
    private var lookupWebViewHandlersByLookupSettings: [LookupWebViewHandler.LookupSettings: LookupWebViewHandler] = [:]
    
    // MARK: Object Lifecycle
    init(
        dbStorage: DbStorage,
        fileStorage: FileStorage,
        translatorsController: TranslatorsAndStylesController,
        schemaController: SchemaController,
        dateParser: DateParser,
        remoteFileDownloader: RemoteAttachmentDownloader
    ) {
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.translatorsController = translatorsController
        self.schemaController = schemaController
        self.dateParser = dateParser
        self.remoteFileDownloader = remoteFileDownloader
        
        self.dispatchSpecificKey = DispatchSpecificKey<String>()
        self.accessQueueLabel = "org.zotero.IdentifierLookupController.accessQueue"
        self.accessQueue = DispatchQueue(label: accessQueueLabel, qos: .userInteractive, attributes: .concurrent)
        accessQueue.setSpecific(key: dispatchSpecificKey, value: accessQueueLabel)
        self.backgroundQueue = DispatchQueue(label: "org.zotero.IdentifierLookupController.backgroundProcessing", qos: .userInitiated)
        self.backgroundScheduler = SerialDispatchQueueScheduler(queue: backgroundQueue, internalSerialQueueName: "org.zotero.IdentifierLookupController.backgroundScheduler")
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()
        
        setupObservers()
    }

    // MARK: Actions
    func initialize(libraryId: LibraryIdentifier, collectionKeys: Set<String>, completion: @escaping ([LookupData]?) -> Void) {
        accessQueue.async(flags: .barrier) { [weak self] in
            var lookupData: [LookupData]?
            defer {
                completion(lookupData)
            }
            guard let self else { return }
            let lookupSettings = LookupWebViewHandler.LookupSettings(libraryIdentifier: libraryId, collectionKeys: collectionKeys)
            if lookupWebViewHandlersByLookupSettings[lookupSettings] != nil {
                lookupData = Array(self.lookupData.values)
                return
            }
            var lookupWebViewHandler: LookupWebViewHandler?
            inMainThread(sync: true) {
                if let webView = self.webViewProvider?.addWebView() {
                    lookupWebViewHandler = LookupWebViewHandler(lookupSettings: lookupSettings, webView: webView, translatorsController: self.translatorsController)
                }
            }
            guard let lookupWebViewHandler else {
                DDLogError("IdentifierLookupController: can't create LookupWebViewHandler instance")
                return
            }
            lookupWebViewHandlersByLookupSettings[lookupSettings] = lookupWebViewHandler
            setupObserver(for: lookupWebViewHandler)
            lookupData = Array(self.lookupData.values)
        }
    }
    
    func lookUp(libraryId: LibraryIdentifier, collectionKeys: Set<String>, identifier: String) {
        let lookupSettings = LookupWebViewHandler.LookupSettings(libraryIdentifier: libraryId, collectionKeys: collectionKeys)
        guard let lookupWebViewHandler = lookupWebViewHandlersByLookupSettings[lookupSettings] else {
            DDLogError("IdentifierLookupController: can't find lookup web view handler for settings - \(lookupSettings)")
            return
        }
        lookupWebViewHandler.lookUp(identifier: identifier)
    }
    
    func cancelAllLookups() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            DDLogInfo("IdentifierLookupController: cancel all lookups")
            let keys = lookupWebViewHandlersByLookupSettings.keys
            for key in keys {
                guard let webView = lookupWebViewHandlersByLookupSettings.removeValue(forKey: key)?.webViewHandler.webView else { continue }
                inMainThread {
                    webView.removeFromSuperview()
                }
            }
            remoteFileDownloader.stop()
            let lookupData = self.lookupData
            cleanupLookupIfNeeded(force: true) { [weak self] _ in
                self?.observable.on(.next(Update(kind: .finishedAllLookups, lookupData: [])))
            }
            let storedItemResponses: [(ItemResponse, LibraryIdentifier)] = lookupData.values.compactMap {
                switch $0.state {
                case .translated(let translatedLookupData):
                    return (translatedLookupData.response, translatedLookupData.libraryId)
                    
                default:
                    return nil
                }
            }
            backgroundQueue.async { [weak self] in
                guard let self else { return }
                do {
                    let requests = storedItemResponses.map({ MarkItemsAsTrashedDbRequest(keys: [$0.0.key], libraryId: $0.1, trashed: true) })
                    try dbStorage.perform(writeRequests: requests, on: backgroundQueue)
                } catch let error {
                    DDLogError("IdentifierLookupController: can't trash item(s) - \(error)")
                }
            }
        }
    }
    
    // MARK: Setups
    private func setupObservers() {
        remoteFileDownloader.observable
            .observe(on: backgroundScheduler)
            .subscribe { [weak self] update in
                var cleanupLookupIfNeeded = false
                switch update.kind {
                case .ready(let attachment):
                    finish(download: update.download, attachment: attachment)
                    cleanupLookupIfNeeded = true

                case .cancelled, .failed:
                    cleanupLookupIfNeeded = true
                    
                case .progress:
                    break
                }
                guard cleanupLookupIfNeeded else { return }
                self?.cleanupLookupIfNeeded(force: false) { [weak self] _ in
                    guard let self else { return }
                    observable.on(.next(Update(kind: .finishedAllLookups, lookupData: [])))
                }
            }
            .disposed(by: self.disposeBag)
        
        func finish(download: RemoteAttachmentDownloader.Download, attachment: Attachment) {
            let localizedType = schemaController.localized(itemType: ItemTypes.attachment) ?? ItemTypes.attachment
            do {
                let request = CreateAttachmentDbRequest(
                    attachment: attachment,
                    parentKey: download.parentKey,
                    localizedType: localizedType,
                    includeAccessDate: attachment.hasUrl,
                    collections: [],
                    tags: []
                )
                _ = try self.dbStorage.perform(request: request, on: self.backgroundQueue)
            } catch let error {
                DDLogError("IdentifierLookupController: can't store attachment after download - \(error)")
                
                // Storing item failed, remove downloaded file
                guard let file = attachment.file else { return }
                try? self.fileStorage.remove(file)
            }
        }
    }
    
    private func setupObserver(for lookupWebViewHandler: LookupWebViewHandler) {
        lookupWebViewHandler.observable
            .subscribe { result in
                process(result: result)
            }
            .disposed(by: self.disposeBag)
        
        func process(result: Result<LookupWebViewHandler.LookupData, Error>) {
            switch result {
            case .success(let data):
                process(data: data)
                
            case .failure(let error):
                DDLogError("IdentifierLookupController: lookup failed - \(error)")
                cleanupLookupIfNeeded(force: false) { [weak self] _ in
                    guard let self else { return }
                    observable.on(.next(Update(kind: .lookupError(error: error), lookupData: Array(lookupData.values))))
                }
            }
            
            func process(data: LookupWebViewHandler.LookupData) {
                switch data {
                case .identifiers(let identifiers):
                    let enqueuedIdentifiers = identifiers.map({ identifier(from: $0) })
                    enqueueLookup(for: enqueuedIdentifiers) { [weak self] validIdentifiers in
                        guard let self else { return }
                        if validIdentifiers.isEmpty {
                            cleanupLookupIfNeeded(force: false) { [weak self] _ in
                                guard let self else { return }
                                observable.on(.next(Update(kind: .identifiersDetected(identifiers: []), lookupData: Array(lookupData.values))))
                            }
                        }
                        observable.on(.next(Update(kind: .identifiersDetected(identifiers: validIdentifiers), lookupData: Array(lookupData.values))))
                    }
                    
                case .item(let data):
                    guard let lookupId = data["identifier"] as? [String: String] else {
                        DDLogWarn("IdentifierLookupController: lookup item data don't contain identifier")
                        return
                    }
                    let identifier = identifier(from: lookupId)
                    var currentState: LookupData.State?
                    accessQueue.sync { [weak self] in
                        guard let self, let currentLookupData = lookupData[identifier] else { return }
                        currentState = currentLookupData.state
                    }
                    guard currentState?.canTransition == true else {
                        DDLogWarn("IdentifierLookupController: \(identifier) lookup item can't transition from state: \(String(describing: currentState))")
                        return
                    }

                    if data.keys.count == 1 {
                        changeLookup(for: identifier, to: .inProgress) { [weak self] didChange in
                            guard let self, didChange else { return }
                            observable.on(.next(Update(kind: .lookupInProgress(identifier: identifier), lookupData: Array(lookupData.values))))
                            // Since at least one identifier lookup is in progress, there is no need to cleanup if needed.
                        }
                        return
                    }

                    if let error = data["error"] {
                        DDLogError("IdentifierLookupController: \(identifier) lookup failed - \(error)")
                        changeLookup(for: identifier, to: .failed) { [weak self] didChange in
                            guard let self, didChange else { return }
                            observable.on(.next(Update(kind: .lookupFailed(identifier: identifier), lookupData: Array(lookupData.values))))
                            cleanupLookupIfNeeded(force: false) { [weak self] cleaned in
                                guard let self, cleaned else { return }
                                observable.on(.next(Update(kind: .finishedAllLookups, lookupData: [])))
                            }
                        }
                        return
                    }

                    let libraryId = lookupWebViewHandler.lookupSettings.libraryIdentifier
                    let collectionKeys = lookupWebViewHandler.lookupSettings.collectionKeys
                    guard let itemData = data["data"] as? [[String: Any]],
                          let item = itemData.first,
                          let (response, attachments) = parse(item, libraryId: libraryId, collectionKeys: collectionKeys, schemaController: schemaController, dateParser: dateParser)
                    else {
                        changeLookup(for: identifier, to: .failed) { [weak self] didChange in
                            guard let self, didChange else { return }
                            observable.on(.next(Update(kind: .parseFailed(identifier: identifier), lookupData: Array(lookupData.values))))
                            cleanupLookupIfNeeded(force: false) { [weak self] cleaned in
                                guard let self, cleaned else { return }
                                observable.on(.next(Update(kind: .finishedAllLookups, lookupData: [])))
                            }
                        }
                        return
                    }

                    process(identifier: identifier, response: response, attachments: attachments, libraryId: libraryId, collectionKeys: collectionKeys)
                }
                
                func identifier(from data: [String: String]) -> String {
                    var result = ""
                    for (key, value) in data {
                        result += key + ":" + value
                    }
                    return result
                }

                /// Tries to parse `ItemResponse` from data returned by translation server. It prioritizes items with attachments if there are multiple items.
                /// - parameter itemData: Data to parse
                /// - parameter schemaController: SchemaController which is used for validating item type and field types
                /// - returns: `ItemResponse` of parsed item and optional attachment dictionary with title and url.
                func parse(
                    _ itemData: [String: Any],
                    libraryId: LibraryIdentifier,
                    collectionKeys: Set<String>,
                    schemaController: SchemaController,
                    dateParser: DateParser
                ) -> (ItemResponse, [(Attachment, URL)])? {
                    do {
                        let item = try ItemResponse(translatorResponse: itemData, schemaController: schemaController).copy(libraryId: libraryId, collectionKeys: collectionKeys, tags: [])

                        let attachments = ((itemData["attachments"] as? [[String: Any]]) ?? []).compactMap { data -> (Attachment, URL)? in
                            // We can't process snapshots yet, so ignore all text/html attachments
                            guard let mimeType = data["mimeType"] as? String, mimeType != "text/html", let ext = mimeType.extensionFromMimeType,
                                  let urlString = data["url"] as? String, let url = URL(string: urlString)
                            else { return nil }

                            let key = KeyGenerator.newKey
                            let filename = FilenameFormatter.filename(from: item, defaultTitle: "Full Text", ext: ext, dateParser: dateParser)
                            let attachment = Attachment(
                                type: .file(filename: filename, contentType: mimeType, location: .local, linkType: .importedFile, compressed: false),
                                title: filename,
                                key: key,
                                libraryId: libraryId
                            )

                            return (attachment, url)
                        }

                        return (item, attachments)
                    } catch let error {
                        DDLogError("IdentifierLookupController: can't parse data - \(error)")
                        return nil
                    }
                }
                
                func process(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)], libraryId: LibraryIdentifier, collectionKeys: Set<String>) {
                    backgroundQueue.async { [weak self] in
                        guard let self else { return }
                        do {
                            try storeDataAndDownloadAttachmentIfNecessary(identifier: identifier, response: response, attachments: attachments)
                        } catch let error {
                            DDLogError("IdentifierLookupController: can't create item(s) - \(error)")
                            changeLookup(for: identifier, to: .failed) { [weak self] didChange in
                                guard let self, didChange else { return }
                                observable.on(.next(Update(kind: .itemCreationFailed(identifier: identifier, response: response, attachments: attachments), lookupData: Array(lookupData.values))))
                                cleanupLookupIfNeeded(force: false) { [weak self] cleaned in
                                    guard let self, cleaned else { return }
                                    observable.on(.next(Update(kind: .finishedAllLookups, lookupData: [])))
                                }
                            }
                        }
                    }
                    
                    func storeDataAndDownloadAttachmentIfNecessary(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)]) throws {
                        let request = CreateTranslatedItemsDbRequest(responses: [response], schemaController: schemaController, dateParser: dateParser)
                        try dbStorage.perform(request: request, on: backgroundQueue)
                        changeLookup(
                            for: identifier,
                            to: .translated(.init(response: response, attachments: attachments, libraryId: libraryId, collectionKeys: collectionKeys))
                        ) { [weak self] didChange in
                            guard let self, didChange else { return }
                            observable.on(.next(Update(kind: .itemStored(identifier: identifier, response: response, attachments: attachments), lookupData: Array(lookupData.values))))
                            
                            if Defaults.shared.shareExtensionIncludeAttachment, !attachments.isEmpty {
                                let downloadData = attachments.map({ ($0, $1, response.key) })
                                remoteFileDownloader.download(data: downloadData)
                                observable.on(.next(Update(kind: .pendingAttachments(identifier: identifier, response: response, attachments: attachments), lookupData: Array(lookupData.values))))
                            }
                            
                            cleanupLookupIfNeeded(force: false) { [weak self] cleaned in
                                guard let self, cleaned else { return }
                                observable.on(.next(Update(kind: .finishedAllLookups, lookupData: [])))
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: Lookup Data
    private func cleanupLookupIfNeeded(force: Bool, completion: @escaping (Bool) -> Void) {
        if DispatchQueue.getSpecific(key: dispatchSpecificKey) == accessQueueLabel {
            cleanupLookup(force: force, completion: completion)
        } else {
            accessQueue.async(flags: .barrier) {
                cleanupLookup(force: force, completion: completion)
            }
        }

        func cleanupLookup(force: Bool, completion: @escaping (Bool) -> Void) {
            if force {
                // If forced, cleanup and return
                cleanup(completion: completion)
                return
            }
            guard lookupRemainingCount == 0, remoteFileDownloader.batchData.2 == 0 else {
                // If there are remaining lookups, or downloading attachments, then just return
                completion(false)
                return
            }
            guard let presenter else {
                // If no presenter is assigned, then cleanup and return
                cleanup(completion: completion)
                return
            }
            // Presenter is assigned
            DispatchQueue.main.async { [weak self] in
                // Checking if it is presenting in main queue.
                // Doing so asynchronously, to not cause a deadlock if cleanupLookupIfNeeded is already called from the main thread.
                guard !presenter.isPresenting(), let self else {
                    completion(false)
                    return
                }
                // It is not presenting, then cleanup
                self.accessQueue.async(flags: .barrier) {
                    cleanup(completion: completion)
                }
            }

            @Sendable func cleanup(completion: @escaping (Bool) -> Void) {
                lookupData = [:]
                lookupSavedCount = 0
                lookupFailedCount = 0
                DDLogInfo("IdentifierLookupController: cleaned up lookup data")
                let keys = lookupWebViewHandlersByLookupSettings.keys
                for key in keys {
                    guard let webView = lookupWebViewHandlersByLookupSettings.removeValue(forKey: key)?.webViewHandler.webView else { continue }
                    DispatchQueue.main.async {
                        webView.removeFromSuperview()
                    }
                }
                completion(true)
            }
        }
    }
    
    private func enqueueLookup(for identifiers: [String], completion: @escaping ([String]) -> Void) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            var newUniqueIdentifiers: [String] = []
            var index = 0
            for identifier in identifiers {
                guard lookupData[identifier] == nil else { continue }
                newUniqueIdentifiers.append(identifier)
                lookupData.updateValue(.init(identifier: identifier, state: .enqueued), forKey: identifier, insertingAt: index)
                index += 1
            }
            completion(newUniqueIdentifiers)
        }
    }
    
    private func changeLookup(for identifier: String, to state: LookupData.State, completion: @escaping (Bool) -> Void) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            var didChange = false
            defer {
                completion(didChange)
            }
            guard let currentLookupData = lookupData[identifier] else { return }
            let currentState = currentLookupData.state
            let isTransitionValid = LookupData.State.isTransitionValid(from: currentState, to: state)
            guard isTransitionValid else {
                DDLogWarn("IdentifierLookupController: \(identifier) lookup item won't transition from state: \(String(describing: currentState)) to state: \(String(describing: state))")
                return
            }
            lookupData[identifier] = .init(identifier: identifier, state: state)
            didChange = true
            switch state {
            case .failed:
                lookupFailedCount += 1
                
            case .translated:
                lookupSavedCount += 1
                
            default:
                break
            }
        }
    }
}
