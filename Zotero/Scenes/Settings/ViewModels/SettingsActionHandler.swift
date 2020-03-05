//
//  SettingsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import RxSwift

struct SettingsActionHandler: ViewModelActionHandler {
    typealias Action = SettingsAction
    typealias State = SettingsState

    private unowned let sessionController: SessionController
    private unowned let syncScheduler: SynchronizationScheduler
    private unowned let debugLogging: DebugLogging
    private let disposeBag: DisposeBag

    init(sessionController: SessionController, syncScheduler: SynchronizationScheduler, debugLogging: DebugLogging) {
        self.sessionController = sessionController
        self.syncScheduler = syncScheduler
        self.debugLogging = debugLogging
        self.disposeBag = DisposeBag()
    }

    func process(action: SettingsAction, in viewModel: ViewModel<SettingsActionHandler>) {
        switch action {
        case .setAskForSyncPermission(let value):
            Defaults.shared.askForSyncPermission = value
            self.update(viewModel: viewModel) { state in
                state.askForSyncPermission = value
            }

        case .setShowCollectionItemCounts(let value):
            Defaults.shared.showCollectionItemCount = value
            self.update(viewModel: viewModel) { state in
                state.showCollectionItemCount = value
            }

        case .startSync:
            self.syncScheduler.requestFullSync()

        case .cancelSync:
            self.syncScheduler.cancelSync()

        case .logout:
            self.sessionController.reset()

        case .startObservingSyncChanges:
            self.observeSyncChanges(in: viewModel)

        case .startImmediateLogging:
            self.debugLogging.start(type: .immediate)
            self.update(viewModel: viewModel) { state in
                state.isLogging = true
            }

        case .startLoggingOnNextLaunch:
            self.debugLogging.start(type: .nextLaunch)
            self.update(viewModel: viewModel) { state in
                state.isLogging = true
            }

        case .stopLogging:
            self.debugLogging.stop()
            self.update(viewModel: viewModel) { state in
                state.isLogging = false
            }
        }
    }

    private func observeSyncChanges(in viewModel: ViewModel<SettingsActionHandler>) {
        self.syncScheduler.syncController.progressObservable
                                         .observeOn(MainScheduler.instance)
                                         .subscribe(onNext: { [weak viewModel] progress in
                                             guard let viewModel = viewModel else { return }
                                             self.update(viewModel: viewModel) { state in
                                                 state.isSyncing = progress != nil
                                             }
                                         })
                                         .disposed(by: self.disposeBag)
    }
}
