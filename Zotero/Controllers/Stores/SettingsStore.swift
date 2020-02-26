//
//  SettingsStore.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import RxSwift

class SettingsStore: ObservableObject {
    struct State {
        var askForSyncPermission: Bool {
            didSet {
                Defaults.shared.askForSyncPermission = self.askForSyncPermission
            }
        }

        var isSyncing: Bool

        init(isSyncing: Bool) {
            self.isSyncing = isSyncing
            self.askForSyncPermission = Defaults.shared.askForSyncPermission

        }
    }

    @Published var state: State

    private unowned let sessionController: SessionController
    private unowned let syncScheduler: SynchronizationScheduler
    private let disposeBag: DisposeBag

    init(sessionController: SessionController, syncScheduler: SynchronizationScheduler) {
        self.sessionController = sessionController
        self.syncScheduler = syncScheduler
        self.state = State(isSyncing: syncScheduler.syncController.inProgress)
        self.disposeBag = DisposeBag()

        syncScheduler.syncController.progressObservable
                                    .observeOn(MainScheduler.instance)
                                    .subscribe(onNext: { [weak self] progress in
                                        self?.state.isSyncing = progress != nil
                                    })
                                    .disposed(by: self.disposeBag)
    }

    func startSync() {
        self.syncScheduler.requestFullSync()
    }

    func cancelSync() {
        self.syncScheduler.cancelSync()
    }

    func logout() {
        self.sessionController.reset()
    }
}
