//
//  MasterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 12/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

import RxSwift

protocol MasterLibrariesCoordinatorDelegate: AnyObject {
    func showCollections(for libraryId: LibraryIdentifier)
    func showSettings()
    func show(error: LibrariesError)
    func showDeleteGroupQuestion(id: Int, name: String, viewModel: ViewModel<LibrariesActionHandler>)
    func showDefaultLibrary()

    var visibleLibraryId: LibraryIdentifier { get }
}

protocol MasterCollectionsCoordinatorDelegate: MainCoordinatorDelegate {
    func showEditView(for data: CollectionStateEditingData, library: Library)
}

final class MasterCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private(set) var visibleLibraryId: LibraryIdentifier

    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private unowned let mainCoordinatorDelegate: MainCoordinatorDelegate

    init(navigationController: UINavigationController, mainCoordinatorDelegate: MainCoordinatorDelegate, controllers: Controllers) {
        self.navigationController = navigationController
        self.mainCoordinatorDelegate = mainCoordinatorDelegate
        self.controllers = controllers
        self.childCoordinators = []
        self.visibleLibraryId = Defaults.shared.selectedLibrary

        super.init()
    }

    func start(animated: Bool) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let librariesController = self.createLibrariesViewController(dbStorage: dbStorage)
        let collectionsController = self.createCollectionsViewController(libraryId: self.visibleLibraryId, selectedCollectionId: Defaults.shared.selectedCollectionId, dbStorage: dbStorage)
        self.navigationController.setViewControllers([librariesController, collectionsController], animated: animated)
    }

    private func createLibrariesViewController(dbStorage: DbStorage) -> UIViewController {
        let viewModel = ViewModel(initialState: LibrariesState(), handler: LibrariesActionHandler(dbStorage: dbStorage))
        let controller = LibrariesViewController(viewModel: viewModel)
        controller.coordinatorDelegate = self
        return controller
    }

    private func createCollectionsViewController(libraryId: LibraryIdentifier, selectedCollectionId: CollectionIdentifier, dbStorage: DbStorage) -> CollectionsViewController {
        let handler = CollectionsActionHandler(dbStorage: dbStorage)
        let state = CollectionsState(libraryId: libraryId, selectedCollectionId: selectedCollectionId)
        let controller = CollectionsViewController(viewModel: ViewModel(initialState: state, handler: handler), dragDropController: self.controllers.dragDropController)
        controller.coordinatorDelegate = self
        return controller
    }

    private func storeIfNeeded(libraryId: LibraryIdentifier) -> CollectionIdentifier {
        if Defaults.shared.selectedLibrary == libraryId {
            return Defaults.shared.selectedCollectionId
        } else {
            Defaults.shared.selectedLibrary = libraryId
            Defaults.shared.selectedCollectionId = .custom(.all)
            return .custom(.all)
        }
    }
}

extension MasterCoordinator: MasterLibrariesCoordinatorDelegate {
    func showDefaultLibrary() {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let libraryId = LibraryIdentifier.custom(.myLibrary)
        let collectionId = self.storeIfNeeded(libraryId: libraryId)

        let controller = self.createCollectionsViewController(libraryId: libraryId, selectedCollectionId: collectionId, dbStorage: dbStorage)

        let animated: Bool
        var viewControllers = self.navigationController.viewControllers

        if let index = viewControllers.firstIndex(where: { $0 is CollectionsViewController }) {
            // If `CollectionsViewController` is visible, replace it with new controller without animation
            viewControllers[index] = controller
            animated = false
        } else {
            // If `CollectionsViewController` is not visible, just push it with animation
            viewControllers.append(controller)
            animated = true
        }

        self.navigationController.setViewControllers(viewControllers, animated: animated)
    }

    func show(error: LibrariesError) {
        let title: String
        let message: String

        switch error {
        case .cantLoadData:
            title = L10n.error
            message = L10n.Errors.Libraries.cantLoad
        }

        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showDeleteGroupQuestion(id: Int, name: String, viewModel: ViewModel<LibrariesActionHandler>) {
        let controller = UIAlertController(title: L10n.delete, message: L10n.Libraries.deleteQuestion(name), preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: .destructive, handler: { [weak viewModel] _ in
            viewModel?.process(action: .deleteGroup(id))
        }))
        controller.addAction(UIAlertAction(title: L10n.no, style: .cancel, handler: nil))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showCollections(for libraryId: LibraryIdentifier) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let collectionId = self.storeIfNeeded(libraryId: libraryId)

        let controller = self.createCollectionsViewController(libraryId: libraryId, selectedCollectionId: collectionId, dbStorage: dbStorage)
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showSettings() {
        let navigationController = NavigationViewController()
        let containerController = ContainerViewController(rootViewController: navigationController)
        containerController.isModalInPresentation = true
        containerController.modalPresentationStyle = .formSheet

        let coordinator = SettingsCoordinator(startsWithExport: false, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(containerController, animated: true, completion: nil)
    }
}

extension MasterCoordinator: MasterCollectionsCoordinatorDelegate {
    func showEditView(for data: CollectionStateEditingData, library: Library) {
        let navigationController = UINavigationController()
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet

        let coordinator = CollectionEditingCoordinator(data: data,
                                                       library: library,
                                                       navigationController: navigationController,
                                                       controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(navigationController, animated: true, completion: nil)
    }

    func showItems(for collection: Collection, in library: Library, isInitial: Bool) {
        self.visibleLibraryId = library.identifier
        if !isInitial {
            Defaults.shared.selectedCollectionId = collection.identifier
        }
        self.mainCoordinatorDelegate.showItems(for: collection, in: library, isInitial: isInitial)
    }

    var isSplit: Bool {
        return self.mainCoordinatorDelegate.isSplit
    }
}
