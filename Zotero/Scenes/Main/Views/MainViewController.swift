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

protocol MainCoordinatorDelegate: SplitControllerDelegate {
    func showItems(for collection: Collection, in library: Library, saveCollectionToDefaults: Bool)
}

protocol SplitControllerDelegate: AnyObject {
    var isSplit: Bool { get }
}

protocol MainCoordinatorSyncToolbarDelegate: AnyObject {
    func showItems(with keys: [String], in libraryId: LibraryIdentifier)
}

final class MainViewController: UISplitViewController {
    // Constants
    private let controllers: Controllers
    private let disposeBag: DisposeBag
    // Variables
    private var didAppear: Bool = false
    private var syncToolbarController: SyncToolbarController?
    private(set) var masterCoordinator: MasterCoordinator?
    private var detailCoordinator: DetailCoordinator? {
        didSet {
            if let action = self.detailCoordinatorGetter, let coordinator = self.detailCoordinator {
                action(coordinator)
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.set(userActivity: .mainActivity)
        self.didAppear = true
    }

    func getDetailCoordinator(completed: @escaping (DetailCoordinator) -> Void) {
        if let coordinator = self.detailCoordinator {
            completed(coordinator)
            return
        }
        self.detailCoordinatorGetter = completed
    }

    private func showItems(for collection: Collection, in library: Library, searchItemKeys: [String]?) {
        let navigationController = UINavigationController()
        let tagFilterController = (self.viewControllers.first as? MasterContainerViewController)?.bottomController as? ItemsTagFilterDelegate

        let coordinator = DetailCoordinator(
            library: library,
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

        if let progressObservable = self.controllers.userControllers?.syncScheduler.syncController.progressObservable, let dbStorage = self.controllers.userControllers?.dbStorage {
            self.syncToolbarController = SyncToolbarController(parent: masterController, progressObservable: progressObservable, dbStorage: dbStorage)
            self.syncToolbarController?.coordinatorDelegate = self
        }
    }
}

extension MainViewController: UISplitViewControllerDelegate {
}

extension MainViewController: MainCoordinatorDelegate {
    func showItems(for collection: Collection, in library: Library, saveCollectionToDefaults: Bool) {
        if saveCollectionToDefaults {
            Defaults.shared.selectedCollectionId = collection.identifier
        }
        guard !self.isSplit || self.detailCoordinator?.library != library || self.detailCoordinator?.collection.identifier != collection.identifier else { return }
        self.showItems(for: collection, in: library, searchItemKeys: nil)
    }
}

extension MainViewController: MainCoordinatorSyncToolbarDelegate {
    func showItems(with keys: [String], in libraryId: LibraryIdentifier) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        do {
            var library: Library?
            var collectionType: CollectionIdentifier.CustomType?

            try dbStorage.perform(on: .main, with: { coordinator in
                library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))

                let isAnyInTrash = try coordinator.perform(request: CheckAnyItemIsInTrashDbRequest(libraryId: libraryId, keys: keys))
                collectionType = isAnyInTrash ? .trash : .all
            })

            guard let library = library, let collectionType = collectionType else { return }

            self.masterCoordinator?.showCollections(for: libraryId, preselectedCollection: .custom(collectionType), animated: true)
            self.showItems(for: Collection(custom: collectionType), in: library, searchItemKeys: keys)
        } catch let error {
            DDLogError("MainViewController: can't load searched keys - \(error)")
        }
    }
}

extension MainViewController: SplitControllerDelegate {
    var isSplit: Bool {
        return !self.isCollapsed
    }
}
