//
//  IdentifierLookupController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 22/6/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxSwift

protocol IdentifierLookupWebViewProvider: AnyObject {
    func addWebView() -> WKWebView
    func removeWebView(_ webView: WKWebView)
}

protocol IdentifierLookupPresenter: AnyObject {
    func isPresenting() -> Bool
}

final class IdentifierLookupController: BackgroundDbProcessingActionHandler {
    // MARK: Types
    struct Update {
        enum Kind {
            case lookupError(error: Swift.Error)
            case noIdentifiersDetected
            case identifiersDetected(identifiers: [String])
            case lookupInProgress(identifier: String)
            case lookupFailed(identifier: String)
            case parseFailed(identifier: String)
            case itemCreationFailed(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)])
            case itemStored(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)])
            case pendingAttachments(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)])
        }

        let kind: Kind
    }
    
    struct LookupData {
        enum State {
            case enqueued
            case inProgress
            case failed
            case translated(TranslatedLookupData)
            
            struct TranslatedLookupData {
                let response: ItemResponse
                let attachments: [(Attachment, URL)]
            }
        }
        
        let identifier: String
        let state: State
    }
    
    // MARK: Properties
    let observable: PublishSubject<Update>
    private let accessQueue: DispatchQueue
    internal let backgroundQueue: DispatchQueue
    internal unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let translatorsController: TranslatorsAndStylesController
    private unowned let schemaController: SchemaController
    private unowned let dateParser: DateParser
    private unowned let remoteFileDownloader: RemoteAttachmentDownloader
    private let disposeBag: DisposeBag
    
    private var lookupData: [LookupData] = []
    private var lookupSavedCount = 0
    private var lookupFailedCount = 0
    private var lookupTotalCount: Int {
        lookupData.count
    }
    private var lookupRemainingCount: Int {
        lookupTotalCount - lookupSavedCount - lookupFailedCount
    }
    
    internal weak var webViewProvider: IdentifierLookupWebViewProvider?
    internal weak var presenter: IdentifierLookupPresenter? {
        didSet {
            guard presenter == nil, oldValue != nil else { return }
            cleanupLookup(force: false, alreadyInQueue: false)
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
        
        self.accessQueue = DispatchQueue(label: "org.zotero.IdentifierLookupController.accessQueue", qos: .userInteractive, attributes: .concurrent)
        self.backgroundQueue = DispatchQueue(label: "org.zotero.IdentifierLookupController.backgroundProcessing", qos: .userInitiated)
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
            guard let self = self else { return }
            let lookupSettings = LookupWebViewHandler.LookupSettings(libraryIdentifier: libraryId, collectionKeys: collectionKeys)
            if self.lookupWebViewHandlersByLookupSettings[lookupSettings] != nil {
                lookupData = self.lookupData
                return
            }
            inMainThread(sync: true) {
                if let webView = self.webViewProvider?.addWebView() {
                    let lookupWebViewHandler = LookupWebViewHandler(lookupSettings: lookupSettings, webView: webView, translatorsController: self.translatorsController)
                    self.lookupWebViewHandlersByLookupSettings[lookupSettings] = lookupWebViewHandler
                }
            }
            guard let lookupWebViewHandler = self.lookupWebViewHandlersByLookupSettings[lookupSettings] else {
                DDLogError("IdentifierLookupController: can't create LookupWebViewHandler instance")
                return
            }
            self.setupObserver(for: lookupWebViewHandler)
            lookupData = self.lookupData
        }
    }
    
    func lookUp(libraryId: LibraryIdentifier, collectionKeys: Set<String>, identifier: String) {
        let lookupSettings = LookupWebViewHandler.LookupSettings(libraryIdentifier: libraryId, collectionKeys: collectionKeys)
        lookupWebViewHandlersByLookupSettings[lookupSettings]?.lookUp(identifier: identifier)
    }
    
    func getIdentifiersLookupCount(callback: @escaping (Int, Int, Int, [LookupData]) -> Void) {
        accessQueue.async { [weak self] in
            var savedCount = 0
            var failedCount = 0
            var totalCount = 0
            var data: [LookupData] = []
            defer {
                callback(savedCount, failedCount, totalCount, data)
            }
            guard let self else { return }
            savedCount = self.lookupSavedCount
            failedCount = self.lookupFailedCount
            totalCount = self.lookupTotalCount
            data = self.lookupData
        }
    }

    // MARK: Setups
    private func setupObservers() {
        remoteFileDownloader.observable
            .subscribe { update in
                switch update.kind {
                case .ready(let attachment):
                    finish(download: update.download, attachment: attachment)
                    
                case .cancelled, .failed, .progress:
                    break
                }
            }
            .disposed(by: self.disposeBag)
        
        func finish(download: RemoteAttachmentDownloader.Download, attachment: Attachment) {
            let localizedType = schemaController.localized(itemType: ItemTypes.attachment) ?? ItemTypes.attachment
            
            backgroundQueue.async { [weak self] in
                guard let self else { return }
                
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
                    guard case .file(let filename, let contentType, _, _) = attachment.type else { return }
                    let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType)
                    try? self.fileStorage.remove(file)
                }
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
                cleanupLookup(force: true, alreadyInQueue: false)
                observable.on(.next(Update(kind: .lookupError(error: error))))
            }
            
            func process(data: LookupWebViewHandler.LookupData) {
                switch data {
                case .identifiers(let identifiers):
                    if identifiers.isEmpty {
                        cleanupLookup(force: true, alreadyInQueue: false)
                        observable.on(.next(Update(kind: .noIdentifiersDetected)))
                    } else {
                        let enqueuedIdentifiers = identifiers.map({ identifier(from: $0) })
                        enqueueLookup(for: enqueuedIdentifiers)
                        observable.on(.next(Update(kind: .identifiersDetected(identifiers: enqueuedIdentifiers))))
                    }
                    
                case .item(let data):
                    guard let lookupId = data["identifier"] as? [String: String] else { return }
                    let identifier = identifier(from: lookupId)

                    if data.keys.count == 1 {
                        changeLookup(for: identifier, to: .inProgress)
                        observable.on(.next(Update(kind: .lookupInProgress(identifier: identifier))))
                        return
                    }

                    if let error = data["error"] {
                        DDLogError("IdentifierLookupController: \(identifier) lookup failed - \(error)")
                        changeLookup(for: identifier, to: .failed)
                        observable.on(.next(Update(kind: .lookupFailed(identifier: identifier))))
                        return
                    }

                    guard let itemData = data["data"] as? [[String: Any]],
                          let item = itemData.first,
                          let (response, attachments) = parse(item)
                    else {
                        changeLookup(for: identifier, to: .failed)
                        observable.on(.next(Update(kind: .parseFailed(identifier: identifier))))
                        return
                    }

                    process(identifier: identifier, response: response, attachments: attachments)
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
                func parse(_ itemData: [String: Any]) -> (ItemResponse, [(Attachment, URL)])? {
                    let libraryId = lookupWebViewHandler.lookupSettings.libraryIdentifier
                    let collectionKeys = lookupWebViewHandler.lookupSettings.collectionKeys
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
                                type: .file(filename: filename, contentType: mimeType, location: .local, linkType: .importedFile),
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
                
                func process(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)]) {
                    backgroundQueue.async { [weak self] in
                        guard let self = self else { return }
                        do {
                            try storeDataAndDownloadAttachmentIfNecessary(identifier: identifier, response: response, attachments: attachments)
                        } catch let error {
                            DDLogError("IdentifierLookupController: can't create item(s) - \(error)")
                            self.changeLookup(for: identifier, to: .failed)
                            self.observable.on(.next(Update(kind: .itemCreationFailed(identifier: identifier, response: response, attachments: attachments))))
                        }
                    }
                    
                    func storeDataAndDownloadAttachmentIfNecessary(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)]) throws {
                        let request = CreateTranslatedItemsDbRequest(responses: [response], schemaController: schemaController, dateParser: dateParser)
                        try dbStorage.perform(request: request, on: backgroundQueue)
                        changeLookup(for: identifier, to: .translated(.init(response: response, attachments: attachments)))
                        observable.on(.next(Update(kind: .itemStored(identifier: identifier, response: response, attachments: attachments))))
                        
                        guard Defaults.shared.shareExtensionIncludeAttachment else { return }

                        let downloadData = attachments.map({ ($0, $1, response.key) })
                        guard !downloadData.isEmpty else { return }
                        remoteFileDownloader.download(data: downloadData)
                        observable.on(.next(Update(kind: .pendingAttachments(identifier: identifier, response: response, attachments: attachments))))
                    }
                }
            }
        }
    }
    
    // MARK: Lookup Data
    func cleanupLookup(force: Bool, alreadyInQueue: Bool) {
        if alreadyInQueue {
            _cleanupLookup(force: force)
        } else {
            accessQueue.async(flags: .barrier) {
                _cleanupLookup(force: force)
            }
        }
        
        func _cleanupLookup(force: Bool) {
            var cleanup = false
            if force {
                cleanup = true
            } else if lookupRemainingCount == 0, remoteFileDownloader.batchData.2 == 0 {
                if let presenter {
                    inMainThread(sync: true) {
                        cleanup = !presenter.isPresenting()
                    }
                } else {
                    cleanup = true
                }
            }
            guard cleanup else { return }
            // If forced,
            // or all lookups have been saved or failed, all attachments have finished, and either no presenter is assigned, or it doesn't present currently,
            // then cleanup.
            lookupData = []
            lookupSavedCount = 0
            lookupFailedCount = 0
            DDLogInfo("IdentifierLookupController: cleaned up lookup data")
        }
    }
    
    func enqueueLookup(for identifiers: [String]) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.lookupData.append(contentsOf: identifiers.map({ .init(identifier: $0, state: .enqueued) }))
        }
    }
    
    func changeLookup(for identifier: String, to state: LookupData.State) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if let index = self.lookupData.firstIndex(where: { $0.identifier == identifier }) {
                self.lookupData[index] = .init(identifier: identifier, state: state)
            }
            switch state {
            case .failed:
                self.lookupFailedCount += 1
                
            case .translated:
                self.lookupSavedCount += 1
                
            default:
                break
            }
            self.cleanupLookup(force: false, alreadyInQueue: true)
        }
    }
}
