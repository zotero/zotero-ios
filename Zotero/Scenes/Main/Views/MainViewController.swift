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

    private struct InitialLoadData {
        let collection: Collection
        let library: Library
    }

    // Constants
    private let controllers: Controllers
    private let defaultCollection: Collection
    private let disposeBag: DisposeBag
    // Variables
    private var didAppear: Bool = false
    private var syncToolbarController: SyncToolbarController?
    private(set) var masterCoordinator: MasterCoordinator?
    private(set) var detailCoordinator: DetailCoordinator?

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

        if let data = self.loadInitialDetailData(collectionId: Defaults.shared.selectedCollectionId, libraryId: Defaults.shared.selectedLibrary) {
            self.showItems(for: data.collection, in: data.library, searchItemKeys: nil)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.set(userActivity: .mainActivity)
        self.didAppear = true
    }

    private func showItems(for collection: Collection, in library: Library, searchItemKeys: [String]?) {
        let navigationController = UINavigationController()

        let coordinator = DetailCoordinator(library: library, collection: collection, searchItemKeys: searchItemKeys, navigationController: navigationController, controllers: self.controllers)
        coordinator.start(animated: false)
        self.detailCoordinator = coordinator

        self.showDetailViewController(navigationController, sender: nil)
    }

    private func loadInitialDetailData(collectionId: CollectionIdentifier, libraryId: LibraryIdentifier) -> InitialLoadData? {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return nil }

        var collection: Collection?
        var library: Library?

        do {
            try dbStorage.perform(on: .main, with: { coordinator in
                switch collectionId {
                case .collection(let key):
                    let rCollection = try coordinator.perform(request: ReadCollectionDbRequest(libraryId: libraryId, key: key))
                    collection = Collection(object: rCollection, itemCount: 0)
                case .search(let key):
                    let rSearch = try coordinator.perform(request: ReadSearchDbRequest(libraryId: libraryId, key: key))
                    collection = Collection(object: rSearch)
                case .custom(let type):
                    collection = Collection(custom: type)
                }
                library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))
            })
        } catch let error {
            DDLogError("MainViewController: can't load initial data - \(error)")
            return nil
        }

        if let collection = collection, let library = library {
            return InitialLoadData(collection: collection, library: library)
        }
        return nil
    }

    // MARK: - Setups

    private func setupControllers() {
        let masterCoordinator = MasterCoordinator(mainController: self, controllers: self.controllers)
        masterCoordinator.start()
        self.masterCoordinator = masterCoordinator

        if let progressObservable = self.controllers.userControllers?.syncScheduler.syncController.progressObservable,
           let dbStorage = self.controllers.userControllers?.dbStorage {
            self.syncToolbarController = SyncToolbarController(parent: masterCoordinator.topCoordinator.navigationController, progressObservable: progressObservable, dbStorage: dbStorage)
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

            try dbStorage.perform(on: .main, with: { coordinator in
                library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))

                let isAnyInTrash = try coordinator.perform(request: CheckAnyItemIsInTrashDbRequest(libraryId: libraryId, keys: keys))
                collectionType = isAnyInTrash ? .trash : .all
            })

            guard let library = library, let collectionType = collectionType else { return }

            self.masterCoordinator?.topCoordinator.showCollections(for: libraryId, preselectedCollection: .custom(collectionType), animated: true)
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
