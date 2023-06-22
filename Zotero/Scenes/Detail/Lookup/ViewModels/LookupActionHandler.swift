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

final class LookupActionHandler: ViewModelActionHandler {
    typealias State = LookupState
    typealias Action = LookupAction

    private unowned let identifierLookupController: IdentifierLookupController
    private unowned let translatorsController: TranslatorsAndStylesController
    private unowned let schemaController: SchemaController
    private unowned let dateParser: DateParser
    private let disposeBag: DisposeBag

    private var lookupWebViewHandler: LookupWebViewHandler?

    init(identifierLookupController: IdentifierLookupController, translatorsController: TranslatorsAndStylesController, schemaController: SchemaController, dateParser: DateParser) {
        self.identifierLookupController = identifierLookupController
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
                   .observe(on: MainScheduler.instance)
                   .subscribe(with: viewModel, onNext: { [weak self] viewModel, result in
                       self?.process(result: result, in: viewModel)
                   })
                   .disposed(by: self.disposeBag)

            identifierLookupController.observable
                .observe(on: MainScheduler.instance)
                .subscribe(with: viewModel) { [weak self] viewModel, update in
                    guard let self else { return }
                    switch update.kind {
                    case .itemStored:
                        break
                        
                    case .pendingAttachments:
                        let translatedData = LookupState.LookupData(identifier: update.identifier, state: .translated(update.parsedData))
                        self.update(lookupData: translatedData, in: viewModel)
                        
                    case .itemCreationFailed:
                        let failedData = LookupState.LookupData(identifier: update.identifier, state: .failed)
                        self.update(lookupData: failedData, in: viewModel)
                    }
                }
                .disposed(by: self.disposeBag)

        case .lookUp(let identifier):
            self.lookUp(identifier: identifier, in: viewModel)
        }
    }

    private func process(result: Result<LookupWebViewHandler.LookupData, Error>, in viewModel: ViewModel<LookupActionHandler>) {
        switch result {
        case .success(let data):
            self.process(data: data, in: viewModel)

        case .failure(let error):
            DDLogError("LookupActionHandler: lookup failed - \(error)")
            self.update(viewModel: viewModel) { state in
                state.lookupState = .failed(error)
            }
        }
    }

    private func lookUp(identifier: String, in viewModel: ViewModel<LookupActionHandler>) {
        var splitChars = CharacterSet.newlines
        splitChars.formUnion(CharacterSet(charactersIn: ","))
        let newIdentifier = identifier.components(separatedBy: splitChars).map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }).joined(separator: ",")

        guard !newIdentifier.isEmpty else { return }

        if !viewModel.state.multiLookupEnabled {
            self.update(viewModel: viewModel) { state in
                state.lookupState = .loadingIdentifiers
            }
        }

        self.lookupWebViewHandler?.lookUp(identifier: newIdentifier)
    }

    private func process(data: LookupWebViewHandler.LookupData, in viewModel: ViewModel<LookupActionHandler>) {
        switch data {
        case .identifiers(let identifiers):
            guard !identifiers.isEmpty else {
                self.update(viewModel: viewModel) { state in
                    state.lookupState = .failed(LookupState.Error.noIdentifiersDetected)
                }
                return
            }

            var lookupData = identifiers.map({ LookupState.LookupData(identifier: self.identifier(from: $0), state: .enqueued) })

            self.update(viewModel: viewModel) { state in
                if !state.multiLookupEnabled {
                    state.lookupState = .lookup(lookupData)
                } else {
                    switch state.lookupState {
                    case .lookup(let data):
                        lookupData.append(contentsOf: data)
                    default: break
                    }

                    state.lookupState = .lookup(lookupData)
                }
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

            identifierLookupController.process(identifier: identifier, response: parsedData.response, attachments: parsedData.attachments)
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
}

extension IdentifierLookupController.Update {
    var parsedData: LookupState.TranslatedLookupData {
        .init(response: response, attachments: attachments)
    }
}
