//
//  SyncRefreshController.swift
//  Zotero
//
//  Created by Michal Rentka on 31.05.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol RefreshableView: AnyObject {
    var refreshControl: UIRefreshControl? { get set }
}

extension UITableView: RefreshableView {}
extension UICollectionView: RefreshableView {}

final class SyncRefreshController {
    private let libraryId: LibraryIdentifier?
    private let disposeBag: DisposeBag

    private weak var refreshableView: RefreshableView?
    private weak var scheduler: SynchronizationScheduler?

    init(libraryId: LibraryIdentifier?, view: RefreshableView, syncScheduler: SynchronizationScheduler) {
        self.libraryId = libraryId
        refreshableView = view
        scheduler = syncScheduler
        disposeBag = DisposeBag()
        
        setupPullToRefresh()
    }

    deinit {
        refreshableView?.refreshControl = nil
    }

    @objc private func startSync() {
        let libraries: SyncController.Libraries
        if let libraryId {
            libraries = .specific([libraryId])
        } else {
            libraries = .all
        }
        scheduler?.request(sync: .ignoreIndividualDelays, libraries: libraries)
    }

    private func update(progress: SyncProgress) {
        switch progress {
        case .aborted, .finished:
            refreshableView?.refreshControl?.endRefreshing()

        default:
            break
        }
    }

    private func setupPullToRefresh() {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(SyncRefreshController.startSync), for: .valueChanged)
        refreshableView?.refreshControl = control

        guard let scheduler else { return }

        scheduler.syncController
            .progressObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] progress in
                self?.update(progress: progress)
            })
            .disposed(by: disposeBag)
    }
}
