//
//  LookupActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 17.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

final class LookupActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias State = LookupState
    typealias Action = LookupAction

    unowned let dbStorage: DbStorage
    let backgroundQueue: DispatchQueue
    private unowned let translatorsController: TranslatorsAndStylesController
    private unowned let schemaController: SchemaController
    private unowned let dateParser: DateParser
    private unowned let remoteFileDownloader: RemoteAttachmentDownloader
    private let disposeBag: DisposeBag

    private var lookupWebViewHandler: LookupWebViewHandler?

    init(dbStorage: DbStorage, translatorsController: TranslatorsAndStylesController, schemaController: SchemaController, dateParser: DateParser, remoteFileDownloader: RemoteAttachmentDownloader) {
        self.backgroundQueue = DispatchQueue(label: "org.zotero.ItemsActionHandler.backgroundProcessing", qos: .userInitiated)
        self.dbStorage = dbStorage
        self.translatorsController = translatorsController
        self.schemaController = schemaController
        self.dateParser = dateParser
        self.remoteFileDownloader = remoteFileDownloader
        self.disposeBag = DisposeBag()
    }

    func process(action: LookupAction, in viewModel: ViewModel<LookupActionHandler>) {
        switch action {
        case .initialize(let webView):
            let handler = LookupWebViewHandler(webView: webView, translatorsController: self.translatorsController)
            self.lookupWebViewHandler = handler

            handler.observable
                   .observe(on: MainScheduler.instance)
                   .subscribe(onNext: { [weak self, weak viewModel] result in
                       switch result {
                       case .success(let data):
                           guard let `self` = self, let viewModel = viewModel else { return }
                           self.process(data: data, in: viewModel)
                       case .failure(let error):
                           DDLogError("LookupActionHandler: lookup failed - \(error)")
                           guard let `self` = self, let viewModel = viewModel else { return }
                           self.show(error: error, in: viewModel)
                       }
                   })
                   .disposed(by: self.disposeBag)

        case .lookUp(let identifier):
            guard !identifier.isEmpty else { return }
            self.update(viewModel: viewModel) { state in
                state.lookupState = .loadingIdentifiers
            }
            self.lookupWebViewHandler?.lookUp(identifier: identifier)
        }
    }

    private func process(data: LookupWebViewHandler.LookupData, in viewModel: ViewModel<LookupActionHandler>) {
        switch data {
        case .identifiers(let identifiers):
            let lookupData = identifiers.map({ LookupState.LookupData(identifier: self.identifier(from: $0), state: .enqueued) })
            self.update(viewModel: viewModel) { state in
                state.lookupState = .lookup(lookupData)
            }

        case .item(let data):
            guard let lookupId = data["identifier"] as? [String: String] else { return }
            let identifier = self.identifier(from: lookupId)

            if data.keys.count == 1 {
                self.update(lookupData: LookupState.LookupData(identifier: identifier, state: .inProgress), in: viewModel)
                return
            }

            if let error = data["error"] {
                DDLogError("LookupActionHandler: \(identifier) lookup failed - \(error)")
                self.update(lookupData: LookupState.LookupData(identifier: identifier, state: .failed), in: viewModel)
                return
            }

            guard let itemData = data["data"] as? [[String: Any]], let item = itemData.first, let parsedData = self.parse(item, viewModel: viewModel, schemaController: self.schemaController) else {
                self.update(lookupData: LookupState.LookupData(identifier: identifier, state: .failed), in: viewModel)
                return
            }

            self.backgroundQueue.async { [weak self, weak viewModel] in
                guard let `self` = self else { return }

                do {
                    try self.storeDataAndDownloadAttachmentIfNecessary(parsedData)

                    inMainThread { [weak self] in
                        guard let `self` = self, let viewModel = viewModel else { return }
                        let translatedData = LookupState.LookupData(identifier: identifier, state: .translated(parsedData))
                        self.update(lookupData: translatedData, in: viewModel)
                    }
                } catch let error {
                    DDLogError("LookupActionHandler: can't create item(s) - \(error)")

                    inMainThread { [weak self] in
                        guard let `self` = self, let viewModel = viewModel else { return }
                        let failedData = LookupState.LookupData(identifier: identifier, state: .failed)
                        self.update(lookupData: failedData, in: viewModel)
                    }
                }
            }
        }
    }

    private func update(lookupData: LookupState.LookupData, in viewModel: ViewModel<LookupActionHandler>) {
        switch viewModel.state.lookupState {
        case .lookup(let oldData):
            var newData = oldData
            guard let index = oldData.firstIndex(where: { $0.identifier == lookupData.identifier }) else { return }
            newData[index] = lookupData
            self.update(viewModel: viewModel) { state in
                state.lookupState = .lookup(newData)
            }

        default: break
        }
    }

    private func identifier(from data: [String: String]) -> String {
        var result = ""
        for (key, value) in data {
            result += key + ":" + value
        }
        return result
    }

    private func storeDataAndDownloadAttachmentIfNecessary(_ data: LookupState.TranslatedLookupData) throws {
        let request = CreateTranslatedItemsDbRequest(responses: [data.response], schemaController: self.schemaController, dateParser: self.dateParser)
        try self.dbStorage.perform(request: request, on: self.backgroundQueue)

        let downloadData = data.attachments.map({ ($0, $1, data.response.key) })
        self.remoteFileDownloader.download(data: downloadData)
    }

    /// Tries to parse `ItemResponse` from data returned by translation server. It prioritizes items with attachments if there are multiple items.
    /// - parameter data: Data to parse
    /// - parameter schemaController: SchemaController which is used for validating item type and field types
    /// - returns: `ItemResponse` of parsed item and optional attachment dictionary with title and url.
    private func parse(_ itemData: [String: Any], viewModel: ViewModel<LookupActionHandler>, schemaController: SchemaController) -> LookupState.TranslatedLookupData? {
        let collectionKeys = viewModel.state.collectionKeys
        let libraryId = viewModel.state.libraryId

        do {
            let item = try ItemResponse(translatorResponse: itemData, schemaController: self.schemaController).copy(libraryId: libraryId, collectionKeys: collectionKeys, tags: [])

            let attachments = ((itemData["attachments"] as? [[String: Any]]) ?? []).compactMap { data -> (Attachment, URL)? in
                // We can't process snapshots yet, so ignore all text/html attachments
                guard let mimeType = data["mimeType"] as? String, mimeType != "text/html", let ext = mimeType.extensionFromMimeType,
                      let urlString = data["url"] as? String, let url = URL(string: urlString) else { return nil }

                let key = KeyGenerator.newKey
                let filename = FilenameFormatter.filename(from: item, defaultTitle: "Full Text", ext: ext, dateParser: self.dateParser)
                let attachment = Attachment(type: .file(filename: filename, contentType: mimeType, location: .local, linkType: .importedFile), title: filename, key: key, libraryId: libraryId)

                return (attachment, url)
            }

            return LookupState.TranslatedLookupData(response: item, attachments: attachments)
        } catch let error {
            DDLogError("LookupActionHandler: can't parse data - \(error)")
            return nil
        }
    }

    private func show(error: Error, in viewModel: ViewModel<LookupActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.lookupState = .failed(error)
        }
    }
}
