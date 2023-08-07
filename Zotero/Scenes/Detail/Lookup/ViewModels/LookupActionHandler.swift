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
            initialize(with: collectionKeys, in: libraryId)

        case .lookUp(let identifier):
            self.lookUp(identifier: identifier, in: viewModel)
            
        case .cancelAllLookups:
            identifierLookupController.cancelAllLookups()
            self.update(viewModel: viewModel) { state in
                state.lookupState = .waitingInput
            }
        }
        
        func initialize(with collectionKeys: Set<String>, in libraryId: LibraryIdentifier) {
            identifierLookupController.initialize(libraryId: libraryId, collectionKeys: collectionKeys) { [weak self] lookupData in
                guard let self, let lookupData else {
                    DDLogError("LookupActionHandler: can't create observer")
                    return
                }
                if viewModel.state.restoreLookupState, !lookupData.isEmpty {
                    DDLogInfo("LookupActionHandler: restoring lookup state")
                    self.update(viewModel: viewModel) { state in
                        state.lookupState = .lookup(lookupData)
                    }
                }
                self.identifierLookupController.observable
                    .observe(on: MainScheduler.instance)
                    .subscribe(with: viewModel) { [weak self] viewModel, update in
                        guard let self else { return }
                        switch viewModel.state.lookupState {
                        case .failed, .waitingInput:
                            // Ignore identifier lookup controller updates if waiting for input
                            return
                            
                        default:
                            break
                        }
                        switch update.kind {
                        case .lookupError(let error):
                            self.update(viewModel: viewModel) { state in
                                state.lookupState = .failed(error)
                            }

                        case .identifiersDetected(let identifiers):
                            if identifiers.isEmpty {
                                if update.lookupData.isEmpty {
                                    self.update(viewModel: viewModel) { state in
                                        state.lookupState = .failed(LookupState.Error.noIdentifiersDetectedAndNoLookupData)
                                    }
                                } else {
                                    self.update(viewModel: viewModel) { state in
                                        state.lookupState = .failed(LookupState.Error.noIdentifiersDetectedWithLookupData)
                                    }
                                }
                                return
                            }
                            self.update(viewModel: viewModel) { state in
                                state.lookupState = .lookup(update.lookupData)
                            }
                            
                        case .lookupInProgress, .lookupFailed, .parseFailed, .itemCreationFailed, .itemStored, .pendingAttachments:
                            self.update(viewModel: viewModel) { state in
                                state.lookupState = .lookup(update.lookupData)
                            }
                                                        
                        case .finishedAllLookups:
                            break
                        }
                    }
                    .disposed(by: self.disposeBag)
            }
        }
    }

    private func lookUp(identifier: String, in viewModel: ViewModel<LookupActionHandler>) {
        var splitChars = CharacterSet.newlines
        splitChars.formUnion(CharacterSet(charactersIn: ","))
        let newIdentifier = identifier.components(separatedBy: splitChars).map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }).joined(separator: ",")

        guard !newIdentifier.isEmpty else { return }

        switch viewModel.state.lookupState {
        case .waitingInput, .failed:
            self.update(viewModel: viewModel) { state in
                state.lookupState = .loadingIdentifiers
            }
            
        case .loadingIdentifiers, .lookup:
            break
        }
        
        let collectionKeys = viewModel.state.collectionKeys
        let libraryId = viewModel.state.libraryId
        identifierLookupController.lookUp(libraryId: libraryId, collectionKeys: collectionKeys, identifier: newIdentifier)
    }
}
