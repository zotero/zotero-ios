//
//  IdentifierLookupController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 22/6/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class IdentifierLookupController: BackgroundDbProcessingActionHandler {
    // MARK: Types
    struct Update {
        enum Kind: Hashable {
            case itemStored
            case pendingAttachments
            case itemCreationFailed
        }

        let identifier: String
        let response: ItemResponse
        let attachments: [(Attachment, URL)]
        let kind: Kind
    }
    
    // MARK: Properties
    let observable: PublishSubject<Update>
    internal let backgroundQueue: DispatchQueue
    internal unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let schemaController: SchemaController
    private unowned let dateParser: DateParser
    private unowned let remoteFileDownloader: RemoteAttachmentDownloader
    private let disposeBag: DisposeBag
    
    // MARK: Object Lifecycle
    init(dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController, dateParser: DateParser, remoteFileDownloader: RemoteAttachmentDownloader) {
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.dateParser = dateParser
        self.remoteFileDownloader = remoteFileDownloader
        
        self.backgroundQueue = DispatchQueue(label: "org.zotero.IdentifierLookupController.backgroundProcessing", qos: .userInitiated)
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()
        
        remoteFileDownloader.observable
            .subscribe { [weak self] update in
                guard let self else { return }
                switch update.kind {
                case .ready(let attachment):
                    self.finish(download: update.download, attachment: attachment)
                    
                case .cancelled, .failed, .progress:
                    break
                }
            }
            .disposed(by: self.disposeBag)
    }
    
    // MARK: Actions
    func process(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)]) {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.storeDataAndDownloadAttachmentIfNecessary(identifier: identifier, response: response, attachments: attachments)
            } catch let error {
                DDLogError("IdentifierLookupController: can't create item(s) - \(error)")
                observable.on(.next(Update(identifier: identifier, response: response, attachments: attachments, kind: .itemCreationFailed)))
            }
        }
    }
    
    // MARK: Helper Methods
    private func storeDataAndDownloadAttachmentIfNecessary(identifier: String, response: ItemResponse, attachments: [(Attachment, URL)]) throws {
        let request = CreateTranslatedItemsDbRequest(responses: [response], schemaController: schemaController, dateParser: dateParser)
        try dbStorage.perform(request: request, on: backgroundQueue)
        observable.on(.next(Update(identifier: identifier, response: response, attachments: attachments, kind: .itemStored)))
        
        guard Defaults.shared.shareExtensionIncludeAttachment else { return }

        let downloadData = attachments.map({ ($0, $1, response.key) })
        guard !downloadData.isEmpty else { return }
        remoteFileDownloader.download(data: downloadData)
        observable.on(.next(Update(identifier: identifier, response: response, attachments: attachments, kind: .pendingAttachments)))
    }
    
    private func finish(download: RemoteAttachmentDownloader.Download, attachment: Attachment) {
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
