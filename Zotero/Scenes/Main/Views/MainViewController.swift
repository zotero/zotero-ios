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
            if let detailCoordinatorGetter,
               detailCoordinatorGetter.libraryId == nil || detailCoordinatorGetter.libraryId == detailCoordinator.libraryId,
               detailCoordinatorGetter.collectionId == nil || detailCoordinatorGetter.collectionId == detailCoordinator.collection.identifier {
                detailCoordinatorGetter.completion(detailCoordinator)
                self.detailCoordinatorGetter = nil
            }
        }
    }
    private var detailCoordinatorGetter: (libraryId: LibraryIdentifier?, collectionId: CollectionIdentifier?, completion: (DetailCoordinator) -> Void)?

    // MARK: - Lifecycle

    init(controllers: Controllers) {
        self.controllers = controllers
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
        setupControllers()
        preferredDisplayMode = .oneBesideSecondary

        func setupControllers() {
            let masterController = MasterContainerViewController()
            let masterCoordinator = MasterCoordinator(navigationController: masterController, mainCoordinatorDelegate: self, controllers: controllers)
            masterController.coordinatorDelegate = masterCoordinator
            masterCoordinator.start(animated: false)
            // In iOS 26 setting the viewControllers here (or in viewDidLoad for that matter), doesn't set the view controller's children initially.
            viewControllers = [masterController]
            self.masterCoordinator = masterCoordinator
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    deinit {
        DDLogInfo("MainViewController: deinitialized")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        preferredPrimaryColumnWidthFraction = 1 / 3
        maximumPrimaryColumnWidth = .infinity
        minimumPrimaryColumnWidth = 320

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

    func getDetailCoordinator(for libraryId: LibraryIdentifier?, and collectionId: CollectionIdentifier?, completion: @escaping (DetailCoordinator) -> Void) {
        if let detailCoordinator, libraryId == nil || libraryId == detailCoordinator.libraryId, collectionId == nil || collectionId == detailCoordinator.collection.identifier {
            completion(detailCoordinator)
            return
        }
        detailCoordinatorGetter = (libraryId, collectionId, completion)
    }

    private func showItems(for collection: Collection, in libraryId: LibraryIdentifier, searchItemKeys: [String]?) {
        let navigationController = UINavigationController()
        let tagFilterController = (viewControllers.first as? MasterContainerViewController)?.bottomController as? ItemsTagFilterDelegate

        let newDetailCoordinator = DetailCoordinator(
            libraryId: libraryId,
            collection: collection,
            searchItemKeys: searchItemKeys,
            navigationController: navigationController,
            itemsTagFilterDelegate: tagFilterController,
            controllers: controllers
        )
        newDetailCoordinator.start(animated: false)
        if let detailCoordinator, presentedViewController != nil {
            // Detail coordinator is about to change while there is a presented view controller.
            // This can happen if e.g. a URL opens an item, and while it is being presented, the collection changes underneath.
            // Existing children are moved to the new instance, so they are properly retained by the new parent coordinator.
            detailCoordinator.childCoordinators.forEach {
                $0.parentCoordinator = newDetailCoordinator
                newDetailCoordinator.childCoordinators.append($0)
            }
            detailCoordinator.childCoordinators = []
        }
        detailCoordinator = newDetailCoordinator

        showDetailViewController(navigationController, sender: nil)
    }
}

extension MainViewController: UISplitViewControllerDelegate { }

extension MainViewController: MainCoordinatorDelegate {
    func showItems(for collection: Collection, in libraryId: LibraryIdentifier) {
        guard isCollapsed || detailCoordinator?.libraryId != libraryId || detailCoordinator?.collection.identifier != collection.identifier else { return }
        showItems(for: collection, in: libraryId, searchItemKeys: nil)
    }
}

extension MainViewController: MainCoordinatorSyncToolbarDelegate {
    func showItems(with keys: [String], in libraryId: LibraryIdentifier) {
        guard let dbStorage = controllers.userControllers?.dbStorage else { return }

        do {
            var collectionType: CollectionIdentifier.CustomType?

            try dbStorage.perform(on: .main, with: { coordinator in
                let isAnyInTrash = try coordinator.perform(request: CheckAnyItemIsInTrashDbRequest(libraryId: libraryId, keys: keys))
                collectionType = isAnyInTrash ? .trash : .all
            })

            guard let collectionType else { return }

            masterCoordinator?.showCollections(for: libraryId, preselectedCollection: .custom(collectionType), animated: true)
            showItems(for: Collection(custom: collectionType), in: libraryId, searchItemKeys: keys)
        } catch let error {
            DDLogError("MainViewController: can't load searched keys - \(error)")
        }
    }
}
