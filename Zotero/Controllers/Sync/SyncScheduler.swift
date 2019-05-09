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
    var progressObservable: BehaviorRelay<SyncProgress?> { get }

    func requestFullSync()
    func requestFullSync(ignoringLocalVersions: Bool)
    func requestSync(for libraries: [LibraryIdentifier])
    func requestSync(for libraries: [LibraryIdentifier], ignoringLocalVersions: Bool)
    func cancelSync()
}

fileprivate typealias SchedulerAction = (SyncController.SyncType, SyncController.LibrarySyncType)

final class SyncScheduler: SynchronizationScheduler {
    private static let timeout = 3.0
    let syncController: SynchronizationController
    private let queue: DispatchQueue
    private let scheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag

    private var inProgress: SchedulerAction?
    private var nextAction: SchedulerAction?
    private var timerDisposeBag: DisposeBag

    var progressObservable: BehaviorRelay<SyncProgress?> {
        return self.syncController.progressObservable
    }

    init(controller: SynchronizationController) {
        self.syncController = controller
        let queue = DispatchQueue(label: "org.zotero.SchedulerAccessQueue", qos: .utility, attributes: .concurrent)
        self.queue = queue
        self.scheduler = SerialDispatchQueueScheduler(queue: queue,
                                                      internalSerialQueueName: "org.zotero.SchedulerAccessQueue")
        self.disposeBag = DisposeBag()
        self.timerDisposeBag = DisposeBag()

        self.syncController.observable
                           .observeOn(self.scheduler)
                           .subscribe(onNext: { [weak self] data in
                               if data.0 && data.1 != .retry {
                                   self?.enqueue(action: (.retry, data.2))
                               }
                               self?.inProgress = nil
                               self?.startTimer()
                           }, onError: { [weak self] _ in
                               self?.inProgress = nil
                               self?.startTimer()
                           })
                           .disposed(by: self.disposeBag)
    }

    func requestFullSync() {
        self.enqueueAndStartTimer(action: (.normal, .all))
    }

    func requestFullSync(ignoringLocalVersions: Bool) {
        self.enqueueAndStartTimer(action: ((ignoringLocalVersions ? .ignoreVersions : .normal), .all))
    }

    func requestSync(for libraries: [LibraryIdentifier]) {
        self.enqueueAndStartTimer(action: (.normal, .specific(libraries)))
    }

    func requestSync(for libraries: [LibraryIdentifier], ignoringLocalVersions: Bool) {
        self.enqueueAndStartTimer(action: ((ignoringLocalVersions ? .ignoreVersions : .normal), .specific(libraries)))
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
            self.enqueue(action: action)

            switch action.1 {
            case .all:
                self.startNextAction()
            case .specific:
                self.startTimer()
            }
        }
    }

    private func enqueue(action: SchedulerAction) {
        guard let nextAction = self.nextAction else {
            self.nextAction = action
            return
        }

        let type = nextAction.0 > action.0 ? nextAction.0 : action.0
        switch (nextAction.1, action.1) {
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
        guard self.inProgress == nil, let action = self.nextAction else { return }
        self.nextAction = nil
        self.inProgress = action
        self.syncController.start(type: action.0, libraries: action.1)
    }
}

extension SyncController.SyncType: Comparable {
    static func < (lhs: SyncController.SyncType, rhs: SyncController.SyncType) -> Bool {
        switch (lhs, rhs) {
        case (.normal, .ignoreVersions),
             (.retry, .ignoreVersions),
             (.retry, .normal):
            return true
        default:
            return false
        }
    }
}
