//
//  SyncScheduler.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
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

/// Controller that schedules synchronisation of local and remote data. All syncs are requested through this controller and it decides if/when next sync should be started.
/// If a sync fails this controller can also retry it with increasing interval to resolve issues.
final class SyncScheduler: SynchronizationScheduler, WebSocketScheduler {
    /// Specifies synchronisation parameters
    struct Sync {
        /// Specifies type of sync
        let type: SyncController.Kind
        /// Specifies which libraries should be synced
        let libraries: SyncController.Libraries
        /// This number indicates number of retry attempts before this sync.
        let retryAttempt: Int
        /// If `true`, next `retryAttempt` is set to max attempt count so that sync is not retried again.
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

    // Current sync in progress
    private var syncInProgress: Sync?
    // Queue of scheduled syncs
    private var syncQueue: [Sync]
    private var lastSyncFinishDate: Date
    private var lastFullSyncDate: Date
    private var timerDisposeBag: DisposeBag?

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

    /// Requests a new sync of given type with specified libraries.
    /// - parameter type: Sync type
    /// - parameter libraries: Libraries to sync
    func request(sync type: SyncController.Kind, libraries: SyncController.Libraries) {
        DDLogInfo("SyncScheduler: requested \(type) sync for \(libraries)")
        self.enqueueAndStart(sync: Sync(type: type, libraries: libraries))
    }

    /// Requests a sync based on websocket reported changes in given library.
    /// - parameter libraryId: Library to sync
    func webSocketUpdate(libraryId: LibraryIdentifier) {
        DDLogInfo("SyncScheduler: websocket sync for \(libraryId)")
        self.enqueueAndStart(sync: Sync(type: .normal, libraries: .specific([libraryId])))
    }

    /// Cancels ongoing sync and all scheduled syncs.
    func cancelSync() {
        DDLogInfo("SyncScheduler: cancel sync")
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.syncController.cancel()
            self.timerDisposeBag = nil
            self.syncInProgress = nil
            self.syncQueue = []
        }
    }

    /// Adds sync to queue and starts next sync in queue if possible.
    /// - parameter sync:
    private func enqueueAndStart(sync: Sync) {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.enqueue(sync: sync)
            self.startNextSync()
        }
    }

    /// Adds a sync to queue. Full sync overrides all queued syncs, since it synchronizes everything, so there's no need to run other syncs before it. Retry sync is scheduled before all syncs
    /// requested externally, so that the currently running sync can try to finish successfully. Duplicate syncs are not added to queue, no need to run the same sync multiple times in succession.
    /// - parameter sync: Sync to add to queue
    private func enqueue(sync: Sync) {
        if sync.type == .full && sync.libraries == .all {
            guard self.canPerformFullSync else { return }
            DDLogInfo("SyncScheduler: clean queue, enqueue full sync")
            // Full sync overrides all queued syncs, since it will sync up everything
            self.syncQueue = [sync]
            // Also reset timer in case we're already waiting for delayed re-sync
            self.timerDisposeBag = nil
        } else if self.syncQueue.isEmpty {
            self.syncQueue.append(sync)
        } else if sync.retryAttempt > 0 {
            // Retry sync should be added to the beginning of queue so that retries are processed before new syncs
            DDLogInfo("SyncScheduler: enqueue retry sync #\(sync.retryAttempt); queue count = \(self.syncQueue.count)")
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

    /// Start next sync in queue. In case of normal/external syncs wait at least `syncTimeout` between syncs. In case of retry syncs wait for specified delay based on current retry attempt count.
    private func startNextSync() {
        // Ignore this if there is a sync in progress.
        guard self.syncInProgress == nil else { return }
        // Otherwise pick next sync in queue.
        guard let nextSync = self.syncQueue.first else {
            // Report finished queue
            self.inProgress.accept(false)
            return
        }

        // If we're waiting on some sync already, cancel timer
        self.timerDisposeBag = nil

        // Get delay for next sync
        let delay: Int
        if nextSync.retryAttempt > 0 {
            let index = min(nextSync.retryAttempt, self.retryIntervals.count)
            delay = self.retryIntervals[index - 1]
        } else {
            delay = SyncScheduler.syncTimeout
        }

        // Apply delay if needed
        let timeSinceLastSync = Int(ceil(Date().timeIntervalSince(self.lastSyncFinishDate) * 1000))
        if timeSinceLastSync < delay {
            DDLogInfo("SyncScheduler: delay sync for \(delay - timeSinceLastSync)")
            self.delay(for: delay - timeSinceLastSync)
            return
        }

        if !self.inProgress.value {
            // Report sync start
            self.inProgress.accept(true)
        }

        DDLogInfo("SyncScheduler: start \(nextSync.type) sync for \(nextSync.libraries)")
        self.syncQueue.removeFirst()
        self.syncInProgress = nextSync
        self.syncController.start(type: nextSync.type, libraries: nextSync.libraries, retryAttempt: nextSync.retryAttempt)
    }

    /// Wait for given timeout before trying to start a sync again.
    /// - parameter timeout: Time in miliseconds to wait before calling `startNextSync` again.
    private func delay(for timeout: Int) {
        guard self.syncInProgress == nil else { return }

        let disposeBag = DisposeBag()
        self.timerDisposeBag = disposeBag

        Single<Int>.timer(.milliseconds(timeout), scheduler: self.scheduler)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.startNextSync()
                   })
                   .disposed(by: disposeBag)
    }
}
