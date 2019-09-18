//
//  MainViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI
import UIKit

import RxSwift

protocol ItemNavigationDelegate: class {
    func didShowLibraries()
    func showCollections(for libraryId: LibraryIdentifier, libraryName: String, metadataEditable: Bool, filesEditable: Bool)
    func showAllItems(for libraryId: LibraryIdentifier, metadataEditable: Bool, filesEditable: Bool)
    func showTrashItems(for libraryId: LibraryIdentifier, metadataEditable: Bool, filesEditable: Bool)
    func showPublications(for libraryId: LibraryIdentifier, metadataEditable: Bool, filesEditable: Bool)
    func showCollectionItems(libraryId: LibraryIdentifier, collectionData: (key: String, name: String),
                             metadataEditable: Bool, filesEditable: Bool)
    func showSearchItems(libraryId: LibraryIdentifier, searchData: (key: String, name: String),
                         metadataEditable: Bool, filesEditable: Bool)
}

fileprivate enum PrimaryColumnState {
    case minimum
    case dynamic(CGFloat)
}

class MainViewController: UISplitViewController, ConflictPresenter {
    // Constants
    private static let minPrimaryColumnWidth: CGFloat = 300
    private static let maxPrimaryColumnFraction: CGFloat = 0.4
    private static let averageCharacterWidth: CGFloat = 10.0
    private let controllers: Controllers
    private let disposeBag: DisposeBag
    // Variables
    private var currentLandscapePrimaryColumnFraction: CGFloat = 0
    private var isViewingLibraries: Bool {
        return false//(self.viewControllers.first as? UINavigationController)?.topViewController is LibrariesViewController
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
        let librariesController = UIViewController()//LibrariesViewController(store: librariesStore, delegate: self)

        let leftNavigationController = ProgressNavigationViewController(rootViewController: librariesController)
        leftNavigationController.syncScheduler = controllers.userControllers?.syncScheduler
        
        let collectionsStore = CollectionsStore(libraryId: .custom(.myLibrary),
                                                title: RCustomLibraryType.myLibrary.libraryName,
                                                metadataEditable: true,
                                                filesEditable: true,
                                                dbStorage: controllers.dbStorage)
        let collectionsController = UIHostingController(rootView: CollectionsView(store: collectionsStore))
        leftNavigationController.pushViewController(collectionsController, animated: false)

        let itemStore = NewItemsStore(libraryId: .custom(.myLibrary),
                                      type: .all,
                                      metadataEditable: true,
                                      filesEditable: true,
                                      dbStorage: controllers.dbStorage)
        let itemsController = UIHostingController(rootView: ItemsView(store: itemStore))
        let rightNavigationController = UINavigationController(rootViewController: itemsController)

        self.viewControllers = [leftNavigationController, rightNavigationController]
        self.minimumPrimaryColumnWidth = MainViewController.minPrimaryColumnWidth
        self.maximumPrimaryColumnWidth = self.maxSize * MainViewController.maxPrimaryColumnFraction

        let newFraction = self.calculatePrimaryColumnFraction(from: collectionsStore.state.cellData)
        self.currentLandscapePrimaryColumnFraction = newFraction
        if UIDevice.current.orientation.isLandscape {
            self.setPrimaryColumn(state: .dynamic(newFraction), animated: false)
        }
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

    private func calculatePrimaryColumnFraction(from collections: [Collection]) -> CGFloat {
        guard !collections.isEmpty else { return 0 }

        var maxCollection: Collection?
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

    func showCollections(for libraryId: LibraryIdentifier, libraryName: String, metadataEditable: Bool, filesEditable: Bool) {
        guard let navigationController = self.viewControllers.first as? UINavigationController else { return }

        let store = CollectionsStore(libraryId: libraryId, title: libraryName,
                                     metadataEditable: metadataEditable,
                                     filesEditable: filesEditable,
                                     dbStorage: self.controllers.dbStorage)
        let controller = UIHostingController(rootView: CollectionsView(store: store))
        navigationController.pushViewController(controller, animated: true)

        navigationController.transitionCoordinator?.animate(alongsideTransition: nil, completion: { _ in
            let newFraction = self.calculatePrimaryColumnFraction(from: store.state.cellData)
            self.currentLandscapePrimaryColumnFraction = newFraction

            if UIDevice.current.orientation.isLandscape {
                self.setPrimaryColumn(state: .dynamic(newFraction), animated: true)
            }
        })
    }

    func showAllItems(for libraryId: LibraryIdentifier, metadataEditable: Bool, filesEditable: Bool) {
        self.showItems(for: .all, libraryId: libraryId,
                       metadataEditable: metadataEditable, filesEditable: filesEditable)
    }

    func showTrashItems(for libraryId: LibraryIdentifier, metadataEditable: Bool, filesEditable: Bool) {
        self.showItems(for: .trash, libraryId: libraryId,
                       metadataEditable: metadataEditable, filesEditable: filesEditable)
    }

    func showPublications(for libraryId: LibraryIdentifier, metadataEditable: Bool, filesEditable: Bool) {
        self.showItems(for: .publications, libraryId: libraryId,
                       metadataEditable: metadataEditable, filesEditable: filesEditable)
    }

    func showSearchItems(libraryId: LibraryIdentifier, searchData: (key: String, name: String),
                         metadataEditable: Bool, filesEditable: Bool) {
        self.showItems(for: .search(searchData.key, searchData.name), libraryId: libraryId,
                       metadataEditable: metadataEditable, filesEditable: filesEditable)
    }

    func showCollectionItems(libraryId: LibraryIdentifier, collectionData: (key: String, name: String),
                             metadataEditable: Bool, filesEditable: Bool) {
        self.showItems(for: .collection(collectionData.key, collectionData.name), libraryId: libraryId,
                       metadataEditable: metadataEditable, filesEditable: filesEditable)
    }

    private func showItems(for type: NewItemsStore.State.ItemType, libraryId: LibraryIdentifier,
                           metadataEditable: Bool, filesEditable: Bool) {
        let store = NewItemsStore(libraryId: libraryId,
                                  type: type,
                                  metadataEditable: metadataEditable,
                                  filesEditable: filesEditable,
                                  dbStorage: self.controllers.dbStorage)
        let controller = UIHostingController(rootView: ItemsView(store: store))
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
