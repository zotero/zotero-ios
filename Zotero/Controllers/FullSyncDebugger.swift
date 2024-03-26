//
//  FullSyncDebugger.swift
//  Zotero
//
//  Created by Michal Rentka on 26.03.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

final class FullSyncDebugger {
    var syncTypeInProgress: Observable<SyncController.Kind?> {
        return syncScheduler.inProgress.map({ [weak self] progress in
            if !progress {
                return nil
            }
            return self?.syncScheduler.syncTypeInProgress
        })
    }

    private unowned let sessionController: SessionController
    private unowned let syncScheduler: SynchronizationScheduler
    private unowned let debugLogging: DebugLogging
    private let disposeBag: DisposeBag
    private var shouldStopLogging: Bool

    init(syncScheduler: SynchronizationScheduler, debugLogging: DebugLogging, sessionController: SessionController) {
        self.sessionController = sessionController
        self.syncScheduler = syncScheduler
        self.debugLogging = debugLogging
        disposeBag = DisposeBag()
        shouldStopLogging = false

        syncTypeInProgress.observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] type in
                guard let self, shouldStopLogging && type == nil else { return }
                let userId = sessionController.sessionData?.userId
                debugLogging.stop(ignoreEmptyLogs: true, userId: userId ?? 0, customAlertMessage: { L10n.fullSyncDebug($0) })
                shouldStopLogging = false
            })
            .disposed(by: disposeBag)
    }

    func start() {
        guard syncScheduler.syncTypeInProgress == nil else { return }
        shouldStopLogging = true
        debugLogging.start(type: .immediate)
        syncScheduler.request(sync: .full, libraries: .all)
    }
}
