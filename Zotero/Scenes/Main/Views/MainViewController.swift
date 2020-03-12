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

fileprivate enum PrimaryColumnState {
    case minimum
    case dynamic(CGFloat)
}

protocol MainCoordinatorDelegate: class {
    func show(collection: Collection, in library: Library)
    func collectionsChanged(to collections: [Collection])
}

class MainViewController: UISplitViewController, ConflictPresenter {
    // Constants
    private static let minPrimaryColumnWidth: CGFloat = 300
    private static let maxPrimaryColumnFraction: CGFloat = 0.4
    private static let averageCharacterWidth: CGFloat = 10.0
    private let controllers: Controllers
    private let defaultCollection: Collection
    private let disposeBag: DisposeBag
    // Variables
    private var didAppear: Bool = false
    private var syncToolbarController: SyncToolbarController?
    private var currentLandscapePrimaryColumnFraction: CGFloat = 0
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
        self.minimumPrimaryColumnWidth = MainViewController.minPrimaryColumnWidth
        self.maximumPrimaryColumnWidth = self.maxSize * MainViewController.maxPrimaryColumnFraction
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self
        self.setPrimaryColumn(state: .minimum, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let isLandscape = size.width > size.height
        coordinator.animate(alongsideTransition: { _ in
            if !isLandscape || self.isViewingLibraries {
                self.setPrimaryColumn(state: .minimum, animated: false)
                return
            }
            self.setPrimaryColumn(state: .dynamic(self.currentLandscapePrimaryColumnFraction), animated: false)
        }, completion: nil)
    }

    // MARK: - Dynamic primary column

    private func reloadPrimaryColumnFraction(with data: [Collection], animated: Bool) {
        let newFraction = self.calculatePrimaryColumnFraction(from: data)
        self.currentLandscapePrimaryColumnFraction = newFraction
        if UIDevice.current.orientation.isLandscape {
            self.setPrimaryColumn(state: .dynamic(newFraction), animated: animated)
        }
    }

    private func setPrimaryColumn(state: PrimaryColumnState, animated: Bool) {
        let primaryColumnFraction: CGFloat
        switch state {
        case .minimum:
            primaryColumnFraction = 0.0
        case .dynamic(let fraction):
            primaryColumnFraction = fraction
        }

        guard primaryColumnFraction != self.preferredPrimaryColumnWidthFraction else { return }

        if !animated {
            self.preferredPrimaryColumnWidthFraction = primaryColumnFraction
            return
        }

        UIView.animate(withDuration: 0.2) {
            self.preferredPrimaryColumnWidthFraction = primaryColumnFraction
        }
    }

    private func calculatePrimaryColumnFraction(from collections: [Collection]) -> CGFloat {
        guard !collections.isEmpty else { return 0 }

        var maxCollection: Collection?
        var maxWidth: CGFloat = 0

        collections.forEach { data in
            let width = (CGFloat(data.level) * CollectionRow.levelOffset) +
                        (CGFloat(data.name.count) * MainViewController.averageCharacterWidth)
            if width > maxWidth {
                maxCollection = data
                maxWidth = width
            }
        }

        guard let collection = maxCollection else { return 0 }

        let titleSize = collection.name.size(withAttributes:[.font: UIFont.systemFont(ofSize: 18.0)])
        let actualWidth = titleSize.width + (CGFloat(collection.level) * CollectionRow.levelOffset) + (2 * CollectionRow.levelOffset)

        return min(1.0, (actualWidth / self.maxSize))
    }

    // MARK: - Setups

    private func setupControllers() {
        let masterController = UINavigationController()
        let detailController = UINavigationController()

        let masterCoordinator = MasterCoordinator(navigationController: masterController,
                                                  mainCoordinatorDelegate: self,
                                                  controllers: self.controllers)
        masterCoordinator.start(animated: false)
        self.masterCoordinator = masterCoordinator

        let detailCoordinator = DetailCoordinator(library: masterCoordinator.defaultLibrary,
                                                  collection: self.defaultCollection,
                                                  navigationController: detailController,
                                                  controllers: self.controllers)
        detailCoordinator.start(animated: false)
        self.detailCoordinator = detailCoordinator

        self.viewControllers = [masterController, detailController]

        if let progressObservable = self.controllers.userControllers?.syncScheduler.syncController.progressObservable {
            self.syncToolbarController = SyncToolbarController(parent: masterController, progressObservable: progressObservable)
        }
    }
}

extension MainViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController,
                             collapseSecondary secondaryViewController: UIViewController,
                             onto primaryViewController: UIViewController) -> Bool {
        return true
    }
}

extension MainViewController: MainCoordinatorDelegate {
    func show(collection: Collection, in library: Library) {
        guard let navigationController = self.viewControllers.last as? UINavigationController else { return }
        let coordinator = DetailCoordinator(library: library,
                                            collection: collection,
                                            navigationController: navigationController,
                                            controllers: self.controllers)
        coordinator.start(animated: false)
        self.detailCoordinator = coordinator
    }

    func collectionsChanged(to collections: [Collection]) {
        self.reloadPrimaryColumnFraction(with: collections, animated: self.didAppear)
    }
}
