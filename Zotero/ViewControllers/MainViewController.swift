//
//  MainViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol ItemNavigationDelegate: class {
    func didShowLibraries()
    func showCollections(for libraryId: Int, libraryName: String)
    func showItems(libraryData: (Int, String), collectionData: (String, String)?)
}

fileprivate enum PrimaryColumnState {
    case minimum
    case dynamic(CGFloat)
}

class MainViewController: UISplitViewController {
    // Constants
    private static let minPrimaryColumnWidth: CGFloat = 300
    private static let maxPrimaryColumnFraction: CGFloat = 0.4
    private static let averageCharacterWidth: CGFloat = 10.0
    private let controllers: Controllers
    private let disposeBag: DisposeBag
    // Variables
    private var currentLandscapePrimaryColumnFraction: CGFloat = 0
    private var isViewingLibraries: Bool {
        return (self.viewControllers.first as? UINavigationController)?.topViewController is LibrariesViewController
    }
    private var maxSize: CGFloat {
        return max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
    }

    // MARK: - Lifecycle

    init(controllers: Controllers) {
        self.controllers = controllers
        self.disposeBag = DisposeBag()

        super.init(nibName: nil, bundle: nil)

        let librariesStore = LibrariesStore(dbStorage: controllers.dbStorage)
        let leftController = LibrariesViewController(store: librariesStore, delegate: self)
        let leftNavigationController = UINavigationController(rootViewController: leftController)

        let itemState = ItemsState(libraryId: RLibrary.myLibraryId, collectionId: nil, title: "My Library")
        let itemStore = ItemsStore(initialState: itemState, apiClient: controllers.apiClient,
                                   fileStorage: controllers.fileStorage, dbStorage: controllers.dbStorage,
                                   itemFieldsController: controllers.itemFieldsController)
        let rightNavigationController = UINavigationController(rootViewController: ItemsViewController(store: itemStore))

        self.minimumPrimaryColumnWidth = MainViewController.minPrimaryColumnWidth
        self.maximumPrimaryColumnWidth = self.maxSize * MainViewController.maxPrimaryColumnFraction
        self.viewControllers = [leftNavigationController, rightNavigationController]
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self
        self.setPrimaryColumn(state: .minimum, animated: false)
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

    // MARK: - Actions

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

    private func calculatePrimaryColumnFraction(from collections: [CollectionCellData]) -> CGFloat {
        guard !collections.isEmpty else { return 0 }

        var maxCollection: CollectionCellData?
        var maxWidth: CGFloat = 0

        collections.forEach { data in
            let width = (CGFloat(data.level) * CollectionCell.levelOffset) +
                        (CGFloat(data.name.count) * MainViewController.averageCharacterWidth)
            if width > maxWidth {
                maxCollection = data
                maxWidth = width
            }
        }

        guard let collection = maxCollection else { return 0 }

        let titleSize = collection.name.size(withAttributes:[.font: UIFont.systemFont(ofSize: 18.0)])
        let actualWidth = titleSize.width + (CGFloat(collection.level) * CollectionCell.levelOffset) + (2 * CollectionCell.baseOffset)

        return min(1.0, (actualWidth / self.maxSize))
    }

    private func showSecondaryController(_ controller: UIViewController) {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            (self.viewControllers.last as? UINavigationController)?.setViewControllers([controller], animated: false)
        case .phone:
            (self.viewControllers.first as? UINavigationController)?.pushViewController(controller, animated: true)
        default: break
        }
    }
}

extension MainViewController: ItemNavigationDelegate {

    func didShowLibraries() {
        guard UIDevice.current.orientation.isLandscape else { return }
        self.setPrimaryColumn(state: .minimum, animated: true)
    }

    func showCollections(for libraryId: Int, libraryName: String) {
        guard let navigationController = self.viewControllers.first as? UINavigationController else { return }

        let state = CollectionsState(libraryId: libraryId, title: libraryName)
        let store = CollectionsStore(initialState: state, dbStorage: self.controllers.dbStorage)
        let controller = CollectionsViewController(store: store, delegate: self)
        navigationController.pushViewController(controller, animated: true)

        navigationController.transitionCoordinator?.animate(alongsideTransition: nil, completion: { _ in
            let newFraction = self.calculatePrimaryColumnFraction(from: store.state.value.cellData)
            self.currentLandscapePrimaryColumnFraction = newFraction

            if UIDevice.current.orientation.isLandscape {
                self.setPrimaryColumn(state: .dynamic(newFraction), animated: true)
            }
        })
    }

    func showItems(libraryData: (Int, String), collectionData: (String, String)?) {
        let title = collectionData?.1 ?? libraryData.1
        let state = ItemsState(libraryId: libraryData.0, collectionId: collectionData?.0, title: title)
        let store = ItemsStore(initialState: state, apiClient: self.controllers.apiClient,
                               fileStorage: self.controllers.fileStorage, dbStorage: self.controllers.dbStorage,
                               itemFieldsController: self.controllers.itemFieldsController)
        let controller = ItemsViewController(store: store)
        self.showSecondaryController(controller)
    }
}

extension MainViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController,
                             collapseSecondary secondaryViewController: UIViewController,
                             onto primaryViewController: UIViewController) -> Bool {
        return true
    }
}
