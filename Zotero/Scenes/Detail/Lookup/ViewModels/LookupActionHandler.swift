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
    private let disposeBag: DisposeBag

    init(identifierLookupController: IdentifierLookupController) {
        self.identifierLookupController = identifierLookupController
        self.disposeBag = DisposeBag()
    }

    func process(action: LookupAction, in viewModel: ViewModel<LookupActionHandler>) {
        switch action {
        case .initialize:
            let collectionKeys = viewModel.state.collectionKeys
            let libraryId = viewModel.state.libraryId
            identifierLookupController.initialize(libraryId: libraryId, collectionKeys: collectionKeys) { [weak self] initialized in
                guard let self, initialized else {
                    DDLogError("LookupActionHandler: can't create observer")
                    return
                }
                self.identifierLookupController.observable
                    .observe(on: MainScheduler.instance)
                    .subscribe(with: viewModel) { [weak self] viewModel, update in
                        guard let self else { return }
                        switch update.kind {
                        case .lookupError(let error):
                            self.update(viewModel: viewModel) { state in
                                state.lookupState = .failed(error)
                            }

                        case .noIdentifiersDetected:
                            self.update(viewModel: viewModel) { state in
                                state.lookupState = .failed(LookupState.Error.noIdentifiersDetected)
                            }
                            
                        case .identifiersDetected(let identifiers):
                            var lookupData = identifiers.map({ LookupState.LookupData(identifier: $0, state: .enqueued) })

                            self.update(viewModel: viewModel) { state in
                                if state.multiLookupEnabled {
                                    switch state.lookupState {
                                    case .lookup(let data):
                                        lookupData.append(contentsOf: data)
                                        
                                    default:
                                        break
                                    }
                                }

                                state.lookupState = .lookup(lookupData)
                            }
                            
                        case .lookupInProgress(let identifier):
                            self.update(lookupData: LookupState.LookupData(identifier: identifier, state: .inProgress), in: viewModel)
                            
                        case .lookupFailed(let identifier), .parseFailed(let identifier), .itemCreationFailed(let identifier, _, _):
                            self.update(lookupData: LookupState.LookupData(identifier: identifier, state: .failed), in: viewModel)
                            
                        case .itemStored:
                            break
                            
                        case .pendingAttachments(let identifier, let response, let attachments):
                            let parsedData = LookupState.TranslatedLookupData(response: response, attachments: attachments)
                            let translatedData = LookupState.LookupData(identifier: identifier, state: .translated(parsedData))
                            self.update(lookupData: translatedData, in: viewModel)
                        }
                    }
                    .disposed(by: self.disposeBag)
            }

        case .lookUp(let identifier):
            self.lookUp(identifier: identifier, in: viewModel)
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

        let collectionKeys = viewModel.state.collectionKeys
        let libraryId = viewModel.state.libraryId
        self.identifierLookupController.lookUp(libraryId: libraryId, collectionKeys: collectionKeys, identifier: newIdentifier)
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

        default:
            break
        }
    }
}
