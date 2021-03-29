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
    func requestNormalSync(for libraries: [LibraryIdentifier])
    func cancelSync()
}

protocol WebSocketScheduler: class {
    func webSocketUpdate(libraryId: LibraryIdentifier)
}

fileprivate typealias SchedulerAction = (syncType: SyncController.SyncType, librarySyncType: SyncController.LibrarySyncType)

final class SyncScheduler: SynchronizationScheduler, WebSocketScheduler {
    /// Timeout in which a new `LibrarySyncType.specific` is started. It's required so that local changes are not submitted immediately or in case of multiple quick changes we don't enqueue multiple syncs.
    private static let timeout: RxTimeInterval = .seconds(3)
    private static let fullSyncTimeout: Double = 3600 // 1 hour
    let syncController: SynchronizationController
    private let queue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag

    private var inProgress: SchedulerAction?
    private var nextAction: SchedulerAction?
    private var lastFullSyncDate: Date?
    private var timerDisposeBag: DisposeBag

    private var canPerformFullSync: Bool {
        guard let date = self.lastFullSyncDate else { return true }
        return Date().timeIntervalSince(date) <= SyncScheduler.fullSyncTimeout
    }

    init(controller: SyncController) {
        self.syncController = controller
        let queue = DispatchQueue(label: "org.zotero.SchedulerAccessQueue", qos: .utility, attributes: .concurrent)
        self.queue = queue
        self.scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.SchedulerAccessQueue")
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

    func requestNormalSync(for libraries: [LibraryIdentifier]) {
        self.enqueueAndStartTimer(action: (.normal, .specific(libraries)))
    }

    func webSocketUpdate(libraryId: LibraryIdentifier) {
        self.enqueueAndStartTimer(action: (.normal, .specific([libraryId])))
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

    private func enqueueAndStartTimer(action: SchedulerAction) {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self._enqueueAndStartTimer(action: action)
        }
    }

    private func _enqueueAndStartTimer(action: SchedulerAction) {
        guard action.syncType != .full || self.canPerformFullSync else { return }

        self.enqueue(action: action)

        switch action.1 {
        case .all:
            self.startNextAction()
        case .specific:
            self.startTimer()
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
        guard self.inProgress == nil else { return }

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

        if syncType == .full {
            self.lastFullSyncDate = Date()
        }

        self.syncController.start(type: syncType, libraries: librarySyncType)
    }
}

extension SyncController.SyncType: Comparable {
    static func < (lhs: SyncController.SyncType, rhs: SyncController.SyncType) -> Bool {
        switch (lhs, rhs) {
        case (.collectionsOnly, .normal),
             (.collectionsOnly, .ignoreIndividualDelays),
             (.collectionsOnly, .full),
             (.normal, .ignoreIndividualDelays),
             (.normal, .full),
             (.ignoreIndividualDelays, .full):
            return true
        default:
            return false
        }
    }
}
