//
//  MainViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import MobileCoreServices
import UIKit
import SafariServices
import SwiftUI

import CocoaLumberjackSwift
import RxSwift

protocol MainCoordinatorDelegate: AnyObject {
    func showItems(for collection: Collection, in libraryId: LibraryIdentifier)
}

protocol MainCoordinatorSyncToolbarDelegate: AnyObject {
    func showItems(with keys: [String], in libraryId: LibraryIdentifier)
}

final class MainViewController: UISplitViewController {
    // Constants
    private let controllers: Controllers
    private let disposeBag: DisposeBag
    // Variables
    private var syncToolbarController: SyncToolbarController?
    private(set) var masterCoordinator: MasterCoordinator?
    private var detailCoordinator: DetailCoordinator? {
        didSet {
            guard let detailCoordinator else { return }
            set(userActivity: .mainActivity().set(title: detailCoordinator.displayTitle))
            if let detailCoordinatorGetter {
                detailCoordinatorGetter(detailCoordinator)
                self.detailCoordinatorGetter = nil
            }
        }
    }
    private var detailCoordinatorGetter: ((DetailCoordinator) -> Void)?

    // MARK: - Lifecycle

    init(controllers: Controllers) {
        self.controllers = controllers
        self.disposeBag = DisposeBag()

        super.init(nibName: nil, bundle: nil)

        self.setupControllers()

        self.preferredDisplayMode = .oneBesideSecondary
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    deinit {
        DDLogInfo("MainViewController: deinitialized")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self

        self.preferredPrimaryColumnWidthFraction = 1 / 3
        self.maximumPrimaryColumnWidth = .infinity
        self.minimumPrimaryColumnWidth = 320

        DDLogInfo("MainViewController: viewDidLoad")
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        if syncToolbarController == nil,
           let progressObservable = controllers.userControllers?.syncScheduler.syncController.progressObservable,
           let dbStorage = controllers.userControllers?.dbStorage,
           let masterController = viewControllers.first {
            syncToolbarController = SyncToolbarController(parent: masterController, progressObservable: progressObservable, dbStorage: dbStorage)
            syncToolbarController?.coordinatorDelegate = self
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let detailCoordinator else { return }
        set(userActivity: .mainActivity().set(title: detailCoordinator.displayTitle))
    }

    func getDetailCoordinator(completed: @escaping (DetailCoordinator) -> Void) {
        if let coordinator = self.detailCoordinator {
            completed(coordinator)
            return
        }
        self.detailCoordinatorGetter = completed
    }

    private func showItems(for collection: Collection, in libraryId: LibraryIdentifier, searchItemKeys: [String]?) {
        let navigationController = UINavigationController()
        let tagFilterController = (self.viewControllers.first as? MasterContainerViewController)?.bottomController as? ItemsTagFilterDelegate

        let coordinator = DetailCoordinator(
            libraryId: libraryId,
            collection: collection,
            searchItemKeys: searchItemKeys,
            navigationController: navigationController,
            itemsTagFilterDelegate: tagFilterController,
            controllers: self.controllers
        )
        coordinator.start(animated: false)
        self.detailCoordinator = coordinator

        self.showDetailViewController(navigationController, sender: nil)
    }

    // MARK: - Setups

    private func setupControllers() {
        let masterController = MasterContainerViewController()
        let masterCoordinator = MasterCoordinator(navigationController: masterController, mainCoordinatorDelegate: self, controllers: self.controllers)
        masterController.coordinatorDelegate = masterCoordinator
        masterCoordinator.start(animated: false)
        self.viewControllers = [masterController]
        self.masterCoordinator = masterCoordinator
    }
}

extension MainViewController: UISplitViewControllerDelegate {
}

extension MainViewController: MainCoordinatorDelegate {
    func showItems(for collection: Collection, in libraryId: LibraryIdentifier) {
        guard isCollapsed || detailCoordinator?.libraryId != libraryId || detailCoordinator?.collection.identifier != collection.identifier else { return }
        showItems(for: collection, in: libraryId, searchItemKeys: nil)
    }
}

extension MainViewController: MainCoordinatorSyncToolbarDelegate {
    func showItems(with keys: [String], in libraryId: LibraryIdentifier) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        do {
            var collectionType: CollectionIdentifier.CustomType?

            try dbStorage.perform(on: .main, with: { coordinator in
                let isAnyInTrash = try coordinator.perform(request: CheckAnyItemIsInTrashDbRequest(libraryId: libraryId, keys: keys))
                collectionType = isAnyInTrash ? .trash : .all
            })

            guard let collectionType else { return }

            self.masterCoordinator?.showCollections(for: libraryId, preselectedCollection: .custom(collectionType), animated: true)
            self.showItems(for: Collection(custom: collectionType), in: libraryId, searchItemKeys: keys)
        } catch let error {
            DDLogError("MainViewController: can't load searched keys - \(error)")
        }
    }
}
