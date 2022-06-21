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
    private var doiRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"10.\d{4,9}\/[-._;()\/:A-Z0-9]+"#)
        } catch let error {
            DDLogError("LookupActionHandler: can't create doi expression - \(error)")
            return nil
        }
    }()
    private var isbnRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: #"[0-9]+[- ][0-9]+[- ][0-9]+[- ][0-9]*[- ]*[xX0-9]"#)
        } catch let error {
            DDLogError("LookupActionHandler: can't create isbn expression - \(error)")
            return nil
        }
    }()

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
                   .subscribe(onNext: { [weak self, weak viewModel] result in
                       switch result {
                       case .success(let data):
                           self?.backgroundQueue.async {
                               guard let `self` = self, let viewModel = viewModel else { return }
                               self.process(data: data, in: viewModel)
                           }
                       case .failure(let error):
                           DDLogError("LookupActionHandler: lookup failed - \(error)")
                           inMainThread {
                               guard let `self` = self, let viewModel = viewModel else { return }
                               self.showError(in: viewModel)
                           }
                       }
                   })
                   .disposed(by: self.disposeBag)

        case .lookUp(let identifier):
            guard !identifier.isEmpty else { return }
            self.update(viewModel: viewModel) { state in
                state.state = .loading
            }
            self.lookupWebViewHandler?.lookUp(identifier: identifier)

        case .processScannedText(let text):
            self.process(scannedText: text, in: viewModel)
        }
    }

    private func process(scannedText: String, in viewModel: ViewModel<LookupActionHandler>) {
        var identifiers: [String] = []
        if let expression = self.doiRegex {
            identifiers = self.getResults(withExpression: expression, from: scannedText)
        }
        if let expression = self.isbnRegex {
            identifiers += self.getResults(withExpression: expression, from: scannedText)
        }

        guard !identifiers.isEmpty else { return }

        self.update(viewModel: viewModel) { state in
            state.scannedText = identifiers.joined(separator: ", ")
        }
    }

    private func getResults(withExpression expression: NSRegularExpression, from text: String) -> [String] {
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { result in
            let startIndex = text.index(text.startIndex, offsetBy: result.range.lowerBound)
            let endIndex = text.index(text.startIndex, offsetBy: result.range.upperBound)
            return String(text[startIndex..<endIndex])
        }
    }

    private func process(data: LookupWebViewHandler.Data, in viewModel: ViewModel<LookupActionHandler>) {
        switch data {
        case .identifiers(let identifiers):
            let lookupData = identifiers.map({ LookupState.LookupData(identifier: self.identifier(from: $0), state: .enqueued) })
            self.update(viewModel: viewModel) { state in
                state.state = .lookup(lookupData)
            }

        case .item(let data):
            guard let lookupId = data["identifier"] as? [String: String] else { return }
            let identifier = self.identifier(from: lookupId)

            if data.keys.count == 1 {
                self.update(identifier: identifier, with: LookupState.LookupData(identifier: identifier, state: .inProgress), in: viewModel)
                return
            }

            if let error = data["error"] {
                DDLogError("LookupActionHandler: \(identifier) lookup failed - \(error)")
                self.update(identifier: identifier, with: LookupState.LookupData(identifier: identifier, state: .failed), in: viewModel)
                return
            }

            // TODO: Process and show

            break
        }
    }

    private func update(identifier: String, with lookupData: LookupState.LookupData, in viewModel: ViewModel<LookupActionHandler>) {
        switch viewModel.state.state {
        case .lookup(let oldData):
            var newData = oldData
            guard let index = oldData.firstIndex(where: { $0.identifier == identifier }) else { return }
            newData[index] = lookupData
            self.update(viewModel: viewModel) { state in
                state.state = .lookup(newData)
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

    private func storeDataAndDownloadAttachmentIfNecessary(_ data: [[String: Any]], in viewModel: ViewModel<LookupActionHandler>) {
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
    private func parse(_ data: [[String: Any]], viewModel: ViewModel<LookupActionHandler>, schemaController: SchemaController) -> [LookupState.TranslatedLookupData] {
        let collectionKeys = viewModel.state.collectionKeys
        let libraryId = viewModel.state.libraryId
        var items: [LookupState.TranslatedLookupData] = []

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
                
                items.append(LookupState.TranslatedLookupData(response: item, attachments: attachments))
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
