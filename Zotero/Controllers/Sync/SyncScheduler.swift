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

protocol SynchronizationScheduler: AnyObject {
    var syncController: SynchronizationController { get }
    var inProgress: BehaviorRelay<Bool> { get }

    func request(sync type: SyncController.Kind, libraries: SyncController.Libraries)
    func cancelSync()
}

protocol WebSocketScheduler: AnyObject {
    func webSocketUpdate(libraryId: LibraryIdentifier)
}

final class SyncScheduler: SynchronizationScheduler, WebSocketScheduler {
    struct Sync {
        let type: SyncController.Kind
        let libraries: SyncController.Libraries
        let retryAttempt: Int
        let retryOnce: Bool

        init(type: SyncController.Kind, libraries: SyncController.Libraries, retryAttempt: Int = 0, retryOnce: Bool = false) {
            self.type = type
            self.libraries = libraries
            self.retryAttempt = retryAttempt
            self.retryOnce = retryOnce
        }
    }

    // Minimum time between syncs
    private static let syncTimeout: Int = 3000 // 3s
    // Minimum time between full syncs
    private static let fullSyncTimeout: Double = 3600 // 1 hour
    let syncController: SynchronizationController
    // Intervals in which retry attempts should be scheduled
    private let retryIntervals: [Int]
    private let queue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag

    private var syncInProgress: Sync?
    private var syncQueue: [Sync]
    private var lastSyncFinishDate: Date
    private var lastFullSyncDate: Date
    private var timerDisposeBag: DisposeBag

    private var canPerformFullSync: Bool {
        return Date().timeIntervalSince(self.lastFullSyncDate) > SyncScheduler.fullSyncTimeout
    }

    var inProgress: BehaviorRelay<Bool>

    init(controller: SyncController, retryIntervals: [Int]) {
        let queue = DispatchQueue(label: "org.zotero.SchedulerAccessQueue", qos: .utility, attributes: .concurrent)

        self.syncController = controller
        self.retryIntervals = retryIntervals
        self.queue = queue
        self.inProgress = BehaviorRelay(value: false)
        self.syncQueue = []
        self.lastSyncFinishDate = Date(timeIntervalSince1970: 0)
        self.lastFullSyncDate = Date(timeIntervalSince1970: 0)
        self.scheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.SchedulerAccessQueue")
        self.disposeBag = DisposeBag()
        self.timerDisposeBag = DisposeBag()

        controller.observable
                  .observe(on: self.scheduler)
                  .subscribe(onNext: { [weak self] sync in
                      guard let self else { return }

                      self.syncInProgress = nil
                      self.lastSyncFinishDate = Date()

                      if let sync = sync {
                          // We're retrying, enqueue the new sync
                          self.enqueueAndStart(sync: sync)
                      } else if !self.syncQueue.isEmpty {
                          // We're not retrying, process next action
                          self.startNextSync()
                      }
                  })
                  .disposed(by: self.disposeBag)
    }

    func request(sync type: SyncController.Kind, libraries: SyncController.Libraries) {
        self.enqueueAndStart(sync: Sync(type: type, libraries: libraries))
    }

    func webSocketUpdate(libraryId: LibraryIdentifier) {
        self.enqueueAndStart(sync: Sync(type: .normal, libraries: .specific([libraryId])))
    }

    func cancelSync() {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.syncController.cancel()
            self.timerDisposeBag = DisposeBag()
            self.syncInProgress = nil
            self.syncQueue = []
        }
    }

    private func enqueueAndStart(sync: Sync) {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.enqueue(sync: sync)
            self.startNextSync()
        }
    }

    private func enqueue(sync: Sync) {
        if sync.type == .full && sync.libraries == .all {
            guard self.canPerformFullSync else { return }
            // Full sync overrides all queued syncs, since it will sync up everything
            self.syncQueue = [sync]
            // Also reset timer in case we're already waiting for delayed re-sync
            self.timerDisposeBag = DisposeBag()
        } else if self.syncQueue.isEmpty {
            self.syncQueue.append(sync)
        } else if sync.retryAttempt > 0 {
            // Retry sync should be added to the beginning of queue so that retries are processed before new syncs
            if let index = self.syncQueue.firstIndex(where: { $0.retryAttempt == 0 }) {
                self.syncQueue.insert(sync, at: index)
            } else {
                self.syncQueue.append(sync)
            }
        } else if !self.syncQueue.contains(where: { return $0.type == sync.type && $0.libraries == sync.libraries }) {
            // New sync request should be added to the end of queue if it's not a duplicate
            self.syncQueue.append(sync)
        }
    }

    private func startNextSync() {
        guard self.syncInProgress == nil, let nextSync = self.syncQueue.first else {
            if self.syncInProgress == nil && self.syncQueue.isEmpty {
                // Report finished queue
                self.inProgress.accept(false)
            }
            return
        }

        let delay: Int
        if nextSync.retryAttempt > 0 {
            let index = min(nextSync.retryAttempt, self.retryIntervals.count)
            delay = self.retryIntervals[index - 1]
        } else {
            delay = SyncScheduler.syncTimeout
        }

        let timeSinceLastSync = Int(ceil(Date().timeIntervalSince(self.lastSyncFinishDate) * 1000))
        if timeSinceLastSync < delay {
            self.delay(for: delay - timeSinceLastSync)
            return
        }

        if !self.inProgress.value {
            // Report sync start
            self.inProgress.accept(true)
        }

        self.syncQueue.removeFirst()
        self.syncInProgress = nextSync
        self.syncController.start(type: nextSync.type, libraries: nextSync.libraries, retryAttempt: nextSync.retryAttempt)
    }

    private func delay(for timeout: Int) {
        guard self.syncInProgress == nil else { return }

        self.timerDisposeBag = DisposeBag()

        Single<Int>.timer(.milliseconds(timeout), scheduler: self.scheduler)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.startNextSync()
                   })
                   .disposed(by: self.timerDisposeBag)
    }
}
