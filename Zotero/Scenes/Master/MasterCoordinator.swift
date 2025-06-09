//
//  MasterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 12/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

import CocoaLumberjackSwift
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
    func showDefaultCollection()
}

protocol MasterContainerCoordinatorDelegate: AnyObject {
    func showDefaultCollection()
    func createBottomController() -> DraggableViewController?
}

final class MasterCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private(set) var visibleLibraryId: LibraryIdentifier
    weak var navigationController: UINavigationController?

    private unowned let controllers: Controllers
    private unowned let mainCoordinatorDelegate: MainCoordinatorDelegate

    init(navigationController: UINavigationController, mainCoordinatorDelegate: MainCoordinatorDelegate, controllers: Controllers) {
        self.navigationController = navigationController
        self.mainCoordinatorDelegate = mainCoordinatorDelegate
        self.controllers = controllers
        childCoordinators = []
        visibleLibraryId = Defaults.shared.selectedLibraryId

        super.init()
    }

    func start(animated: Bool) {
        guard let userControllers = controllers.userControllers, let navigationController else { return }
        let librariesController = createLibrariesViewController(dbStorage: userControllers.dbStorage, syncScheduler: userControllers.syncScheduler)
        userControllers.identifierLookupController.webViewProvider = librariesController
        userControllers.citationController.webViewProvider = librariesController
        userControllers.pdfWorkerController.webViewProvider = librariesController
        userControllers.recognizerController.webViewProvider = librariesController
        let collectionsController = createCollectionsViewController(
            libraryId: visibleLibraryId,
            selectedCollectionId: Defaults.shared.selectedCollectionId,
            dbStorage: userControllers.dbStorage,
            syncScheduler: userControllers.syncScheduler,
            attachmentDownloader: userControllers.fileDownloader,
            fileCleanupController: userControllers.fileCleanupController
        )
        navigationController.setViewControllers([librariesController, collectionsController], animated: animated)

        func createLibrariesViewController(dbStorage: DbStorage, syncScheduler: SynchronizationScheduler) -> LibrariesViewController {
            let viewModel = ViewModel(initialState: LibrariesState(), handler: LibrariesActionHandler(dbStorage: dbStorage))
            let controller = LibrariesViewController(viewModel: viewModel, syncScheduler: syncScheduler)
            controller.coordinatorDelegate = self
            return controller
        }
    }

    private func createCollectionsViewController(
        libraryId: LibraryIdentifier,
        selectedCollectionId: CollectionIdentifier,
        dbStorage: DbStorage,
        syncScheduler: SynchronizationScheduler,
        attachmentDownloader: AttachmentDownloader,
        fileCleanupController: AttachmentFileCleanupController
    ) -> CollectionsViewController {
        DDLogInfo("MasterTopCoordinator: show collections for \(selectedCollectionId.id); \(libraryId)")
        let handler = CollectionsActionHandler(dbStorage: dbStorage, fileStorage: controllers.fileStorage, attachmentDownloader: attachmentDownloader, fileCleanupController: fileCleanupController)
        let state = CollectionsState(libraryId: libraryId, selectedCollectionId: selectedCollectionId)
        let viewModel = ViewModel(initialState: state, handler: handler)
        return CollectionsViewController(viewModel: viewModel, dbStorage: dbStorage, dragDropController: controllers.dragDropController, syncScheduler: syncScheduler, coordinatorDelegate: self)
    }

    private func storeIfNeeded(libraryId: LibraryIdentifier, preselectedCollection collectionId: CollectionIdentifier? = nil) -> CollectionIdentifier {
        if Defaults.shared.selectedLibraryId == libraryId {
            if let collectionId {
                Defaults.shared.selectedCollectionId = collectionId
                return collectionId
            }
            return Defaults.shared.selectedCollectionId
        }

        let collectionId = collectionId ?? .custom(.all)
        Defaults.shared.selectedLibraryId = libraryId
        Defaults.shared.selectedCollectionId = collectionId
        return collectionId
    }
}

extension MasterCoordinator: MasterLibrariesCoordinatorDelegate {
    func showDefaultLibrary() {
        guard let userControllers = controllers.userControllers, let navigationController else { return }

        let libraryId = LibraryIdentifier.custom(.myLibrary)
        let collectionId = storeIfNeeded(libraryId: libraryId)

        let controller = createCollectionsViewController(
            libraryId: libraryId,
            selectedCollectionId: collectionId,
            dbStorage: userControllers.dbStorage,
            syncScheduler: userControllers.syncScheduler,
            attachmentDownloader: userControllers.fileDownloader,
            fileCleanupController: userControllers.fileCleanupController
        )

        let animated: Bool
        var viewControllers = navigationController.viewControllers

        if let index = viewControllers.firstIndex(where: { $0 is CollectionsViewController }) {
            // If `CollectionsViewController` is visible, replace it with new controller without animation
            viewControllers[index] = controller
            animated = false
        } else {
            // If `CollectionsViewController` is not visible, just push it with animation
            viewControllers.append(controller)
            animated = true
        }

        navigationController.setViewControllers(viewControllers, animated: animated)
    }

    func show(error: LibrariesError) {
        guard let navigationController else { return }
        let title: String
        let message: String

        switch error {
        case .cantLoadData:
            title = L10n.error
            message = L10n.Errors.Libraries.cantLoad
        }

        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        navigationController.present(controller, animated: true, completion: nil)
    }

    func showDeleteGroupQuestion(id: Int, name: String, viewModel: ViewModel<LibrariesActionHandler>) {
        guard let navigationController else { return }
        let controller = UIAlertController(title: L10n.delete, message: L10n.Libraries.deleteQuestion(name), preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: .destructive, handler: { [weak viewModel] _ in
            viewModel?.process(action: .deleteGroup(id))
        }))
        controller.addAction(UIAlertAction(title: L10n.no, style: .cancel, handler: nil))
        navigationController.present(controller, animated: true, completion: nil)
    }

    func showCollections(for libraryId: LibraryIdentifier) {
        guard let userControllers = controllers.userControllers, let navigationController else { return }

        let collectionId = storeIfNeeded(libraryId: libraryId)

        let controller = createCollectionsViewController(
            libraryId: libraryId,
            selectedCollectionId: collectionId,
            dbStorage: userControllers.dbStorage,
            syncScheduler: userControllers.syncScheduler,
            attachmentDownloader: userControllers.fileDownloader,
            fileCleanupController: userControllers.fileCleanupController
        )
        navigationController.pushViewController(controller, animated: true)
    }

    func showCollections(for libraryId: LibraryIdentifier, preselectedCollection collectionId: CollectionIdentifier, animated: Bool) {
        guard let userControllers = controllers.userControllers, let navigationController else { return }

        let collectionId = storeIfNeeded(libraryId: libraryId, preselectedCollection: collectionId)

        if navigationController.viewControllers.count == 1 {
            // If only "Libraries" screen is visible, push collections
            let controller = createCollectionsViewController(
                libraryId: libraryId,
                selectedCollectionId: collectionId,
                dbStorage: userControllers.dbStorage,
                syncScheduler: userControllers.syncScheduler,
                attachmentDownloader: userControllers.fileDownloader,
                fileCleanupController: userControllers.fileCleanupController
            )
            navigationController.pushViewController(controller, animated: animated)
        } else if libraryId != visibleLibraryId {
            // If Collections screen is visible, but for different library, switch controllers
            let controller = createCollectionsViewController(
                libraryId: libraryId,
                selectedCollectionId: collectionId,
                dbStorage: userControllers.dbStorage,
                syncScheduler: userControllers.syncScheduler,
                attachmentDownloader: userControllers.fileDownloader,
                fileCleanupController: userControllers.fileCleanupController
            )

            var viewControllers = navigationController.viewControllers
            _ = viewControllers.popLast()
            viewControllers.append(controller)

            navigationController.setViewControllers(viewControllers, animated: animated)
        } else if let controller = navigationController.visibleViewController as? CollectionsViewController, controller.selectedIdentifier != .custom(.all) {
            // Correct Collections screen is visible, just select proper collection
            controller.viewModel.process(action: .select(.custom(.all)))
        }
    }

    func showSettings() {
        guard let navigationController else { return }
        let settingsNavigationController = NavigationViewController()
        let containerController = ContainerViewController(rootViewController: settingsNavigationController)
        let coordinator = SettingsCoordinator(navigationController: settingsNavigationController, controllers: controllers)
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        navigationController.present(containerController, animated: true, completion: nil)
    }
}

extension MasterCoordinator: MasterCollectionsCoordinatorDelegate {
    func showEditView(for data: CollectionStateEditingData, library: Library) {
        guard let navigationController else { return }
        let editNavigationController = UINavigationController()
        editNavigationController.isModalInPresentation = true
        editNavigationController.modalPresentationStyle = .formSheet

        let coordinator = CollectionEditingCoordinator(data: data, library: library, navigationController: editNavigationController, controllers: controllers)
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        navigationController.present(editNavigationController, animated: true, completion: nil)
    }

    func showItems(for collection: Collection, in libraryId: LibraryIdentifier) {
        visibleLibraryId = libraryId
        mainCoordinatorDelegate.showItems(for: collection, in: libraryId)
    }

    func showCiteExport(for itemIds: Set<String>, libraryId: LibraryIdentifier) {
        guard let navigationController else { return }
        let exportNavigationController = NavigationViewController()
        let containerController = ContainerViewController(rootViewController: exportNavigationController)
        let coordinator = CitationBibliographyExportCoordinator(itemIds: itemIds, libraryId: libraryId, navigationController: exportNavigationController, controllers: controllers)
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        navigationController.present(containerController, animated: true, completion: nil)
    }

    func showCiteExportError() {
        guard let navigationController else { return }
        let controller = UIAlertController(title: L10n.error, message: L10n.Errors.Collections.bibliographyFailed, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        navigationController.present(controller, animated: true, completion: nil)
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
    
    func showDefaultCollection() {
        showItems(for: Collection(custom: .all), in: visibleLibraryId)
    }
}

extension MasterCoordinator: MasterContainerCoordinatorDelegate {
    func createBottomController() -> DraggableViewController? {
        guard UIDevice.current.userInterfaceIdiom == .pad, let dbStorage = controllers.userControllers?.dbStorage else { return nil }
        let state = TagFilterState(selectedTags: [], showAutomatic: Defaults.shared.tagPickerShowAutomaticTags, displayAll: Defaults.shared.tagPickerDisplayAllTags)
        let handler = TagFilterActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        return TagFilterViewController(viewModel: viewModel, dragDropController: controllers.dragDropController)
    }
}
