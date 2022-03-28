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
    func showItems(for collection: Collection, in library: Library, isInitial: Bool)
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
    private let defaultCollection: Collection
    private let disposeBag: DisposeBag
    // Variables
    private var didAppear: Bool = false
    private var syncToolbarController: SyncToolbarController?
    private var isViewingLibraries: Bool {
        return (self.viewControllers.first as? UINavigationController)?.viewControllers.count == 1
    }
    private var maxSize: CGFloat {
        return max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
    }
    private var masterCoordinator: MasterCoordinator?
    private var detailCoordinator: DetailCoordinator?

    // MARK: - Lifecycle

    init(controllers: Controllers) {
        self.controllers = controllers
        self.defaultCollection = Collection(custom: .all)
        self.disposeBag = DisposeBag()

        super.init(nibName: nil, bundle: nil)

        self.setupControllers()

        self.preferredDisplayMode = .oneBesideSecondary
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self

        self.preferredPrimaryColumnWidthFraction = 1/3
        self.maximumPrimaryColumnWidth = .infinity
        self.minimumPrimaryColumnWidth = 320
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    private func showItems(for collection: Collection, in library: Library, searchItemKeys: [String]?) {
        let navigationController = UINavigationController()

        let coordinator = DetailCoordinator(library: library, collection: collection, searchItemKeys: searchItemKeys, navigationController: navigationController, controllers: self.controllers)
        coordinator.start(animated: false)
        self.detailCoordinator = coordinator

        self.showDetailViewController(navigationController, sender: nil)
    }

    // MARK: - Setups

    private func setupControllers() {
        let masterController = UINavigationController()
        let masterCoordinator = MasterCoordinator(navigationController: masterController, mainCoordinatorDelegate: self, controllers: self.controllers)
        masterCoordinator.start(animated: false)
        self.masterCoordinator = masterCoordinator

        self.viewControllers = [masterController]

        if let progressObservable = self.controllers.userControllers?.syncScheduler.syncController.progressObservable,
           let dbStorage = self.controllers.userControllers?.dbStorage {
            self.syncToolbarController = SyncToolbarController(parent: masterController, progressObservable: progressObservable, dbStorage: dbStorage)
            self.syncToolbarController?.coordinatorDelegate = self
        }
    }
}

extension MainViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController,
                             collapseSecondary secondaryViewController: UIViewController,
                             onto primaryViewController: UIViewController) -> Bool {
        // The search bar is hidden when the app goes to background for unknown reason. This is a workaround to reset it if needed when
        // the app returns to active state.
        if let controller = (secondaryViewController as? UINavigationController)?.topViewController as? ItemsViewController {
            controller.setSearchBarNeedsReset()
        }
        return false
    }
}

extension MainViewController: MainCoordinatorDelegate {
    func showItems(for collection: Collection, in library: Library, isInitial: Bool) {
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

            try dbStorage.perform(with: { coordinator in
                library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))

                let isAnyInTrash = try coordinator.perform(request: CheckAnyItemIsInTrashDbRequest(libraryId: libraryId, keys: keys))
                collectionType = isAnyInTrash ? .trash : .all

                coordinator.invalidate()
            })

            guard let library = library, let collectionType = collectionType else { return }

            self.masterCoordinator?.showCollections(for: libraryId, preselectedCollection: .custom(collectionType))
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
