//
//  MainViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

import RxSwift

fileprivate enum PrimaryColumnState {
    case minimum
    case dynamic(CGFloat)
}

class MainViewController: UISplitViewController, ConflictPresenter {
    // Constants
    private static let minPrimaryColumnWidth: CGFloat = 300
    private static let maxPrimaryColumnFraction: CGFloat = 0.4
    private static let averageCharacterWidth: CGFloat = 10.0
    private let defaultLibrary: Library
    private let defaultCollection: Collection
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
        self.defaultLibrary = Library(identifier: .custom(.myLibrary),
                                      name: RCustomLibraryType.myLibrary.libraryName,
                                      metadataEditable: true,
                                      filesEditable: true)
        self.defaultCollection = Collection(custom: .all)
        self.controllers = controllers
        self.disposeBag = DisposeBag()

        super.init(nibName: nil, bundle: nil)

        self.setupControllers()

        self.preferredDisplayMode = .allVisible
        self.minimumPrimaryColumnWidth = MainViewController.minPrimaryColumnWidth
        self.maximumPrimaryColumnWidth = self.maxSize * MainViewController.maxPrimaryColumnFraction

//        let newFraction = self.calculatePrimaryColumnFraction(from: collectionsStore.state.cellData)
//        self.currentLandscapePrimaryColumnFraction = newFraction
//        if UIDevice.current.orientation.isLandscape {
//            self.setPrimaryColumn(state: .dynamic(newFraction), animated: false)
//        }
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

    private func showCollections(in library: Library) {
        let view = CollectionsView(store: CollectionsStore(library: library,
                                                           dbStorage: self.controllers.dbStorage),
                                   rowSelected: self.showItems)
        (self.viewControllers.first as? UINavigationController)?.pushViewController(UIHostingController(rootView: view), animated: true)

        self.showItems(in: Collection(custom: .all), library: library)
    }

    private func showItems(in collection: Collection, library: Library) {
        let view = ItemsView(store: self.itemsStore(for: collection, library: library))
                        .environment(\.dbStorage, self.controllers.dbStorage)
                        .environment(\.apiClient, self.controllers.apiClient)
                        .environment(\.fileStorage, self.controllers.fileStorage)
                        .environment(\.schemaController, self.controllers.schemaController)
        self.showSecondaryController(UIHostingController(rootView: view))
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

    private func itemsStore(for collection: Collection, library: Library) -> NewItemsStore {
        let type: NewItemsStore.State.ItemType

        switch collection.type {
        case .collection:
            type = .collection(collection.key, collection.name)
        case .search:
            type = .search(collection.key, collection.name)
        case .custom(let customType):
            switch customType {
            case .all:
                type = .all
            case .publications:
                type = .publications
            case .trash:
                type = .trash
            }
        }

        return NewItemsStore(type: type, library: library, dbStorage: self.controllers.dbStorage)
    }

    // MARK: - Dynamic primary column

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

    // MARK: - Setups

    private func setupControllers() {
        let librariesView = LibrariesView(store: LibrariesStore(dbStorage: self.controllers.dbStorage),
                                          librarySelected: self.showCollections)
        let collectionsView = CollectionsView(store: CollectionsStore(library: self.defaultLibrary,
                                                                      dbStorage: self.controllers.dbStorage),
                                              rowSelected: self.showItems)

        let masterController = UINavigationController()
        masterController.viewControllers = [UIHostingController(rootView: librariesView),
                                            UIHostingController(rootView: collectionsView)]

        let itemsView = ItemsView(store: self.itemsStore(for: self.defaultCollection,
                                                         library: self.defaultLibrary))
                            .environment(\.dbStorage, self.controllers.dbStorage)
                            .environment(\.apiClient, self.controllers.apiClient)
                            .environment(\.fileStorage, self.controllers.fileStorage)
                            .environment(\.schemaController, self.controllers.schemaController)

        let detailController = UINavigationController(rootViewController: UIHostingController(rootView: itemsView))

        self.viewControllers = [masterController, detailController]
    }
}

extension MainViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController,
                             collapseSecondary secondaryViewController: UIViewController,
                             onto primaryViewController: UIViewController) -> Bool {
        return true
    }
}
