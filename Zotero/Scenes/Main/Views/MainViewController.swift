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
    private var didAppear: Bool = false
    private var syncToolbarController: SyncToolbarController?
    private var currentLandscapePrimaryColumnFraction: CGFloat = 0
    private var isViewingLibraries: Bool {
        return (self.viewControllers.first as? UINavigationController)?.viewControllers.count == 1
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

    // MARK: - Navigation

    private func showCollections(for library: Library) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let controller = self.collectionsViewController(library: library, dbStorage: dbStorage)
        (self.viewControllers.first as? UINavigationController)?.pushViewController(controller, animated: true)
    }

    private func presentSettings() {
        guard let syncScheduler = self.controllers.userControllers?.syncScheduler else { return }
        let state = SettingsState(isSyncing: syncScheduler.syncController.inProgress,
                                  isLogging: self.controllers.debugLogging.isLoggingInProgress,
                                  isWaitingOnTermination: self.controllers.debugLogging.isWaitingOnTermination)
        let handler = SettingsActionHandler(sessionController: self.controllers.sessionController,
                                            syncScheduler: syncScheduler,
                                            debugLogging: self.controllers.debugLogging)
        let view = SettingsView(closeAction: { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        })
        .environmentObject(ViewModel(initialState: state, handler: handler))

        let controller = UIHostingController(rootView: view)
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func showSecondaryController(_ controller: UIViewController) {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            let navigationController = self.viewControllers.last as? UINavigationController
            navigationController?.setToolbarHidden(true, animated: false)
            navigationController?.setViewControllers([controller], animated: false)
        case .phone:
            (self.viewControllers.first as? UINavigationController)?.pushViewController(controller, animated: true)
        default: break
        }
    }

    private func itemsViewController(collection: Collection, library: Library, dbStorage: DbStorage) -> ItemsViewController {
        let type = self.fetchType(from: collection)
        let state = ItemsState(type: type, library: library, results: nil, sortType: .default, error: nil)
        let handler = ItemsActionHandler(dbStorage: dbStorage,
                                         fileStorage: self.controllers.fileStorage,
                                         schemaController: self.controllers.schemaController)
        return ItemsViewController(viewModel: ViewModel(initialState: state, handler: handler), controllers: self.controllers)
    }

    private func collectionsViewController(library: Library, dbStorage: DbStorage) -> CollectionsViewController {
        let handler = CollectionsActionHandler(dbStorage: dbStorage)
        let state = CollectionsState(library: library)
        let controller = CollectionsViewController(viewModel: ViewModel(initialState: state, handler: handler),
                                                   dbStorage: dbStorage,
                                                   dragDropController: self.controllers.dragDropController)
        controller.collectionsChanged = { [weak self] collections in
            guard let `self` = self else { return }
            self.reloadPrimaryColumnFraction(with: collections, animated: self.didAppear)
        }
        controller.navigationDelegate = self
        return controller
    }

    private func librariesViewController(dbStorage: DbStorage) -> UIViewController {
        let viewModel = ViewModel(initialState: LibrariesState(), handler: LibrariesActionHandler(dbStorage: dbStorage))
        // SWIFTUI BUG: - We need to call loadData here, because when we do so in `onAppear` in SwiftuI `View` we'll crash when data change
        // instantly in that function. If we delay it, the user will see unwanted animation of data on screen. If we call it here, data
        // is available immediately.
        viewModel.process(action: .loadData)
        let librariesView = LibrariesView(pushCollectionsView: { [weak self] library in
                                             self?.showCollections(for: library)
                                          },
                                          showSettings: { [weak self] in
                                              self?.presentSettings()
                                          })
                                    .environmentObject(viewModel)
        return UIHostingController(rootView: librariesView)
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

    // MARK: - Helpers

    private func fetchType(from collection: Collection) -> ItemFetchType {
        switch collection.type {
        case .collection:
            return .collection(collection.key, collection.name)
        case .search:
            return .search(collection.key, collection.name)
        case .custom(let customType):
            switch customType {
            case .all:
                return .all
            case .publications:
                return .publications
            case .trash:
                return .trash
            }
        }
    }

    // MARK: - Setups

    private func setupControllers() {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let librariesController = self.librariesViewController(dbStorage: dbStorage)
        let collectionsController = self.collectionsViewController(library: self.defaultLibrary, dbStorage: dbStorage)
        let itemsController = self.itemsViewController(collection: self.defaultCollection, library: self.defaultLibrary, dbStorage: dbStorage)

        let masterController = UINavigationController()
        masterController.viewControllers = [librariesController, collectionsController]
        let detailController = UINavigationController(rootViewController: itemsController)

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

extension MainViewController: CollectionsNavigationDelegate {
    func show(collection: Collection, in library: Library) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let controller = self.itemsViewController(collection: collection, library: library, dbStorage: dbStorage)
        self.showSecondaryController(controller)
    }
}
