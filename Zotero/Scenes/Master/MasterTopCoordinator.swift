//
//  MasterTopCoordinator.swift
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
    func showCiteExport(for itemIds: Set<String>, libraryId: LibraryIdentifier)
    func showCiteExportError()
    func showSearch(for state: CollectionsState, in controller: UIViewController, selectAction: @escaping (Collection) -> Void)
}

final class MasterTopCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
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
        guard let userControllers = self.controllers.userControllers else { return }
        let librariesController = self.createLibrariesViewController(dbStorage: userControllers.dbStorage)
        let collectionsController = self.createCollectionsViewController(libraryId: self.visibleLibraryId, selectedCollectionId: Defaults.shared.selectedCollectionId,
                                                                         dbStorage: userControllers.dbStorage, attachmentDownloader: userControllers.fileDownloader)
        self.navigationController.setViewControllers([librariesController, collectionsController], animated: animated)
    }

    private func createLibrariesViewController(dbStorage: DbStorage) -> UIViewController {
        let viewModel = ViewModel(initialState: LibrariesState(), handler: LibrariesActionHandler(dbStorage: dbStorage))
        let controller = LibrariesViewController(viewModel: viewModel)
        controller.coordinatorDelegate = self
        return controller
    }

    private func createCollectionsViewController(libraryId: LibraryIdentifier, selectedCollectionId: CollectionIdentifier, dbStorage: DbStorage, attachmentDownloader: AttachmentDownloader) -> CollectionsViewController {
        let handler = CollectionsActionHandler(dbStorage: dbStorage, fileStorage: self.controllers.fileStorage, attachmentDownloader: attachmentDownloader)
        let state = CollectionsState(libraryId: libraryId, selectedCollectionId: selectedCollectionId)
        return CollectionsViewController(viewModel: ViewModel(initialState: state, handler: handler), dragDropController: self.controllers.dragDropController, coordinatorDelegate: self)
    }

    private func storeIfNeeded(libraryId: LibraryIdentifier, preselectedCollection collectionId: CollectionIdentifier? = nil) -> CollectionIdentifier {
        if Defaults.shared.selectedLibrary == libraryId {
            if let collectionId = collectionId {
                Defaults.shared.selectedCollectionId = collectionId
                return collectionId
            }
            return Defaults.shared.selectedCollectionId
        }

        let collectionId = collectionId ?? .custom(.all)
        Defaults.shared.selectedLibrary = libraryId
        Defaults.shared.selectedCollectionId = collectionId
        return collectionId
    }
}

extension MasterTopCoordinator: MasterLibrariesCoordinatorDelegate {
    func showDefaultLibrary() {
        guard let userControllers = self.controllers.userControllers else { return }

        let libraryId = LibraryIdentifier.custom(.myLibrary)
        let collectionId = self.storeIfNeeded(libraryId: libraryId)

        let controller = self.createCollectionsViewController(libraryId: libraryId, selectedCollectionId: collectionId, dbStorage: userControllers.dbStorage, attachmentDownloader: userControllers.fileDownloader)

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
        guard let userControllers = self.controllers.userControllers else { return }

        let collectionId = self.storeIfNeeded(libraryId: libraryId)

        let controller = self.createCollectionsViewController(libraryId: libraryId, selectedCollectionId: collectionId, dbStorage: userControllers.dbStorage, attachmentDownloader: userControllers.fileDownloader)
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showCollections(for libraryId: LibraryIdentifier, preselectedCollection collectionId: CollectionIdentifier, animated: Bool) {
        guard let userControllers = self.controllers.userControllers else { return }

        let collectionId = self.storeIfNeeded(libraryId: libraryId, preselectedCollection: collectionId)

        if self.navigationController.viewControllers.count == 1 {
            // If only "Libraries" screen is visible, push collections
            let controller = self.createCollectionsViewController(libraryId: libraryId, selectedCollectionId: collectionId, dbStorage: userControllers.dbStorage, attachmentDownloader: userControllers.fileDownloader)
            self.navigationController.pushViewController(controller, animated: animated)
        } else if libraryId != self.visibleLibraryId {
            // If Collections screen is visible, but for different library, switch controllers
            let controller = self.createCollectionsViewController(libraryId: libraryId, selectedCollectionId: collectionId, dbStorage: userControllers.dbStorage, attachmentDownloader: userControllers.fileDownloader)

            var viewControllers = self.navigationController.viewControllers
            _ = viewControllers.popLast()
            viewControllers.append(controller)

            self.navigationController.setViewControllers(viewControllers, animated: animated)
        } else if let controller = self.navigationController.visibleViewController as? CollectionsViewController, controller.selectedIdentifier != .custom(.all) {
            // Correct Collections screen is visible, just select proper collection
            controller.viewModel.process(action: .select(.custom(.all)))
        }
    }

    func showSettings() {
        let navigationController = NavigationViewController()
        let containerController = ContainerViewController(rootViewController: navigationController)
        let coordinator = SettingsCoordinator(startsWithExport: false, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(containerController, animated: true, completion: nil)
    }
}

extension MasterTopCoordinator: MasterCollectionsCoordinatorDelegate {
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

    func showCiteExport(for itemIds: Set<String>, libraryId: LibraryIdentifier) {
        let navigationController = NavigationViewController()
        let containerController = ContainerViewController(rootViewController: navigationController)
        let coordinator = CitationBibliographyExportCoordinator(itemIds: itemIds, libraryId: libraryId, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(containerController, animated: true, completion: nil)
    }

    func showCiteExportError() {
        let controller = UIAlertController(title: L10n.error, message: L10n.Errors.Collections.bibliographyFailed, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showSearch(for state: CollectionsState, in controller: UIViewController, selectAction: @escaping (Collection) -> Void) {
        let searchState = CollectionsSearchState(collectionsTree: state.collectionTree)
        let viewModel = ViewModel(initialState: searchState, handler: CollectionsSearchActionHandler())

        let searchController = CollectionsSearchViewController(viewModel: viewModel, selectAction: selectAction)
        searchController.modalPresentationStyle = .overCurrentContext
        searchController.modalTransitionStyle = .crossDissolve
        searchController.isModalInPresentation = true

        controller.present(searchController, animated: true, completion: nil)
    }
}
