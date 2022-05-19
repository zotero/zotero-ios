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
    struct LookupData {
        let response: ItemResponse
        let attachments: [(Attachment, URL)]
    }

    typealias State = LookupState
    typealias Action = LookupAction

    unowned let dbStorage: DbStorage
    private let translatorsController: TranslatorsAndStylesController
    private let schemaController: SchemaController
    private let dateParser: DateParser
    let backgroundQueue: DispatchQueue
    private let disposeBag: DisposeBag

    private var lookupWebViewHandler: LookupWebViewHandler?

    init(dbStorage: DbStorage, translatorsController: TranslatorsAndStylesController, schemaController: SchemaController, dateParser: DateParser) {
        self.backgroundQueue = DispatchQueue(label: "org.zotero.ItemsActionHandler.backgroundProcessing", qos: .userInitiated)
        self.dbStorage = dbStorage
        self.translatorsController = translatorsController
        self.schemaController = schemaController
        self.dateParser = dateParser
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
                       inMainThread {
                           guard let `self` = self, let viewModel = viewModel else { return }
                           self.showError(in: viewModel)
                       }
                   })
                   .disposed(by: self.disposeBag)

        case .lookUp(let identifier):
            self.lookupWebViewHandler?.lookUp(identifier: identifier)
        }
    }

    private func process(data: [[String: Any]], in viewModel: ViewModel<LookupActionHandler>) {
        let parsedData = self.parse(data, viewModel: viewModel, schemaController: self.schemaController)

        do {
            let request = CreateTranslatedItemDbRequest(responses: parsedData.map({ $0.response }), schemaController: self.schemaController, dateParser: self.dateParser)
            try self.dbStorage.perform(request: request)
        } catch let error {
            DDLogError("LookupActionHandler: can't create item(s) - \(error)")
        }
    }

    /// Tries to parse `ItemResponse` from data returned by translation server. It prioritizes items with attachments if there are multiple items.
    /// - parameter data: Data to parse
    /// - parameter schemaController: SchemaController which is used for validating item type and field types
    /// - returns: `ItemResponse` of parsed item and optional attachment dictionary with title and url.
    private func parse(_ data: [[String: Any]], viewModel: ViewModel<LookupActionHandler>, schemaController: SchemaController) -> [LookupData] {
        let collectionKeys = viewModel.state.collectionKeys
        let libraryId = viewModel.state.libraryId
        var items: [LookupData] = []

        for itemData in data {
            do {
                let item = try ItemResponse(translatorResponse: itemData, schemaController: self.schemaController).copy(libraryId: libraryId, collectionKeys: collectionKeys, tags: [])
                let attachments = ((itemData["attachments"] as? [[String: Any]]) ?? []).compactMap { data -> (Attachment, URL)? in
                    guard let urlString = data["url"] as? String, let url = URL(string: urlString), let mimeType = data["mimeType"] as? String, let ext = mimeType.extensionFromMimeType else { return nil }

                    let key = KeyGenerator.newKey
                    let filename = FilenameFormatter.filename(from: item, defaultTitle: "Full Text", ext: ext, dateParser: self.dateParser)
                    let attachment = Attachment(type: .file(filename: filename, contentType: mimeType, location: .local, linkType: .importedFile), title: filename, key: key, libraryId: libraryId)

                    return (attachment, url)
                }
                
                items.append(LookupData(response: item, attachments: attachments))
            } catch let error {
                DDLogError("LookupActionHandler: can't parse data - \(error)")
            }
        }

        return items
    }

    private func showError(in viewModel: ViewModel<LookupActionHandler>) {

    }
}
