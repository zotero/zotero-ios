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

import RxSwift

protocol MainCoordinatorDelegate: SplitControllerDelegate {
    func show(collection: Collection, in library: Library)
}

protocol SplitControllerDelegate: class {
    var isSplit: Bool { get }
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

        self.preferredDisplayMode = .allVisible
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

    // MARK: - Setups

    private func setupControllers() {
        let masterController = UINavigationController()
        let masterCoordinator = MasterCoordinator(navigationController: masterController,
                                                  mainCoordinatorDelegate: self,
                                                  controllers: self.controllers)
        masterCoordinator.start(animated: false)
        self.masterCoordinator = masterCoordinator

        self.viewControllers = [masterController]

        if let progressObservable = self.controllers.userControllers?.syncScheduler.syncController.progressObservable {
            self.syncToolbarController = SyncToolbarController(parent: masterController, progressObservable: progressObservable)
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
    func show(collection: Collection, in library: Library) {
        guard !self.isSplit || self.detailCoordinator?.library != library || self.detailCoordinator?.collection != collection else { return }

        let navigationController = UINavigationController()

        let coordinator = DetailCoordinator(library: library,
                                            collection: collection,
                                            navigationController: navigationController,
                                            controllers: self.controllers)
        coordinator.start(animated: false)
        self.detailCoordinator = coordinator

        self.showDetailViewController(navigationController, sender: nil)
    }
}

extension MainViewController: SplitControllerDelegate {
    var isSplit: Bool {
        return !self.isCollapsed
    }
}
