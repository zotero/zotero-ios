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
                   .subscribe(onNext: { [weak self, weak viewModel] data in
                       self?.backgroundQueue.async {
                           guard let `self` = self, let viewModel = viewModel else { return }
                           self.process(data: data, in: viewModel)
                       }
                   }, onError: { [weak self, weak viewModel] error in
                       DDLogError("LookupActionHandler: lookup failed - \(error)")
                       inMainThread {
                           guard let `self` = self, let viewModel = viewModel else { return }
                           self.showError(in: viewModel)
                       }
                   })
                   .disposed(by: self.disposeBag)

        case .lookUp(let identifier):
            guard !identifier.isEmpty else { return }
            self.update(viewModel: viewModel) { state in
                state.state = .loading
            }
            self.lookupWebViewHandler?.lookUp(identifier: identifier)
        }
    }

    private func process(data: [[String: Any]], in viewModel: ViewModel<LookupActionHandler>) {
        let parsedData = self.parse(data, viewModel: viewModel, schemaController: self.schemaController)

        do {
            let request = CreateTranslatedItemsDbRequest(responses: parsedData.map({ $0.response }), schemaController: self.schemaController, dateParser: self.dateParser)
            try self.dbStorage.perform(request: request, on: self.backgroundQueue)

            inMainThread {
                self.update(viewModel: viewModel) { state in
                    state.state = .done(parsedData)
                }
            }

            let downloadData = parsedData.flatMap({ lookupData in
                return lookupData.attachments.map({ ($0, $1, lookupData.response.key) })
            })
            self.remoteFileDownloader.download(data: downloadData)
        } catch let error {
            DDLogError("LookupActionHandler: can't create item(s) - \(error)")
            inMainThread {
                self.showError(in: viewModel)
            }
        }
    }

    /// Tries to parse `ItemResponse` from data returned by translation server. It prioritizes items with attachments if there are multiple items.
    /// - parameter data: Data to parse
    /// - parameter schemaController: SchemaController which is used for validating item type and field types
    /// - returns: `ItemResponse` of parsed item and optional attachment dictionary with title and url.
    private func parse(_ data: [[String: Any]], viewModel: ViewModel<LookupActionHandler>, schemaController: SchemaController) -> [LookupState.LookupData] {
        let collectionKeys = viewModel.state.collectionKeys
        let libraryId = viewModel.state.libraryId
        var items: [LookupState.LookupData] = []

        for itemData in data {
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
                
                items.append(LookupState.LookupData(response: item, attachments: attachments))
            } catch let error {
                DDLogError("LookupActionHandler: can't parse data - \(error)")
            }
        }

        return items
    }

    private func showError(in viewModel: ViewModel<LookupActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.state = .failed
        }
    }
}
