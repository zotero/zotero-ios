//
//  SyncScheduler.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxCocoa
import RxSwift

protocol SynchronizationScheduler: class {
    var syncController: SynchronizationController { get }

    func request(syncType: SyncController.SyncType)
    func request(syncType: SyncController.SyncType, for libraries: [LibraryIdentifier])
    func cancelSync()
}

protocol WebSocketScheduler: class {
    func webSocketUpdate(libraries: [LibraryIdentifier])
}

fileprivate typealias SchedulerAction = (syncType: SyncController.SyncType, librarySyncType: SyncController.LibrarySyncType)

final class SyncScheduler: SynchronizationScheduler, WebSocketScheduler {
    /// Timeout in which a new `LibrarySyncType.specific` is started. It's required so that local changes are not submitted immediately or in case of multiple quick changes we don't enqueue multiple syncs.
    private static let timeout: RxTimeInterval = .seconds(3)
    /// Time limit in which a `LibrarySyncType.specific` can be re-enqueued. It's required to avoid double syncs from websocket notifications, which are reported from our changes as well.
    private static let enqueueTimeLimit: CFAbsoluteTime = 10 // seconds
    let syncController: SynchronizationController
    private let queue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag

    private var inProgress: SchedulerAction?
    private var nextAction: SchedulerAction?
    private var lastAction: (CFAbsoluteTime, SyncController.LibrarySyncType)?
    private var timerDisposeBag: DisposeBag

    init(controller: SyncController) {
        self.syncController = controller
        let queue = DispatchQueue(label: "org.zotero.SchedulerAccessQueue", qos: .utility, attributes: .concurrent)
        self.queue = queue
        self.scheduler = SerialDispatchQueueScheduler(queue: queue,
                                                      internalSerialQueueName: "org.zotero.SchedulerAccessQueue")
        self.disposeBag = DisposeBag()
        self.timerDisposeBag = DisposeBag()

        controller.observable
                  .observeOn(self.scheduler)
                  .subscribe(onNext: { [weak self] data in
                      self?.inProgress = nil
                      if let data = data { // We're retrying, enqueue the new sync
                          self?._enqueueAndStartTimer(action: data)
                      } else if self?.nextAction != nil {
                          // We're not retrying, start timer so that next in queue is processed
                          self?.startTimer()
                      }
                  }, onError: { [weak self] _ in
                      self?.inProgress = nil
                      if self?.nextAction != nil {
                          self?.startTimer()
                      }
                  })
                  .disposed(by: self.disposeBag)
    }

    func request(syncType: SyncController.SyncType) {
        self.enqueueAndStartTimer(action: (syncType, .all))
    }

    func request(syncType: SyncController.SyncType, for libraries: [LibraryIdentifier]) {
        self.enqueueAndStartTimer(action: (syncType, .specific(libraries)))
    }

    func webSocketUpdate(libraries: [LibraryIdentifier]) {
        self.enqueueAndStartTimer(action: (.normal, .specific(libraries)), ignoreTimeLimit: false)
    }

    func cancelSync() {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.syncController.cancel()
            self.timerDisposeBag = DisposeBag()
            self.inProgress = nil
            self.nextAction = nil
        }
    }

    private func enqueueAndStartTimer(action: SchedulerAction, ignoreTimeLimit: Bool = true) {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self._enqueueAndStartTimer(action: action)
        }
    }

    private func _enqueueAndStartTimer(action: SchedulerAction) {
        guard self.canEnqueue(action: action) else { return }

        self.enqueue(action: action)

        switch action.1 {
        case .all:
            self.startNextAction()
        case .specific:
            self.startTimer()
        }
    }

    private func canEnqueue(action: SchedulerAction) -> Bool {
        guard case .specific(let libraries) = action.librarySyncType,
              let (lastTime, lastSyncType) = self.lastAction else { return true }

        let enqueueEnabled = (CFAbsoluteTimeGetCurrent() - lastTime) > SyncScheduler.enqueueTimeLimit
        switch lastSyncType {
        case .all:
            return enqueueEnabled
        case .specific(let lastLibraries):
            // Either enough time has passed or there is a library to be synced that wasn't synced before
            return enqueueEnabled || libraries.contains(where: { !lastLibraries.contains($0) })
        }
    }

    private func enqueue(action: SchedulerAction) {
        guard let (nextSyncType, nextLibrarySyncType) = self.nextAction else {
            self.nextAction = action
            return
        }

        let type = nextSyncType > action.syncType ? nextSyncType : action.syncType
        switch (nextLibrarySyncType, action.librarySyncType) {
        case (.all, .all):
            self.nextAction = (type, .all)
        case (.specific, .all):
            self.nextAction = (type, .all)
        case (.specific(let nextIds), .specific(let newIds)):
            let unionedIds = Array(Set(nextIds).union(Set(newIds)))
            self.nextAction = (type, .specific(unionedIds))
        case (.all, .specific): break // If full sync is enqueued we don't "degrade" it to specific
        }
    }

    private func startTimer() {
        self.timerDisposeBag = DisposeBag()
        Single<Int>.timer(SyncScheduler.timeout, scheduler: self.scheduler)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.startNextAction()
                   })
                   .disposed(by: self.timerDisposeBag)
    }

    private func startNextAction() {
        guard self.inProgress == nil, let (syncType, librarySyncType) = self.nextAction else { return }
        self.inProgress = self.nextAction
        self.nextAction = nil
        self.lastAction = (CFAbsoluteTimeGetCurrent(), librarySyncType)
        self.syncController.start(type: syncType, libraries: librarySyncType)
    }
}

extension SyncController.SyncType: Comparable {
    static func < (lhs: SyncController.SyncType, rhs: SyncController.SyncType) -> Bool {
        switch (lhs, rhs) {
        case (.collectionsOnly, .normal),
             (.collectionsOnly, .ignoreIndividualDelays),
             (.collectionsOnly, .all),
             (.normal, .ignoreIndividualDelays),
             (.normal, .all),
             (.ignoreIndividualDelays, .all):
            return true
        default:
            return false
        }
    }
}
