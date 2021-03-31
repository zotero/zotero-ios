//
//  MasterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 12/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SafariServices
import SwiftUI

import RxSwift

protocol MasterLibrariesCoordinatorDelegate: class {
    func showCollections(for libraryId: LibraryIdentifier)
    func showSettings()
    func show(error: LibrariesError)
    func showDeleteGroupQuestion(id: Int, name: String, viewModel: ViewModel<LibrariesActionHandler>)
    func showDefaultLibrary()

    var visibleLibraryId: LibraryIdentifier { get }
}

protocol MasterCollectionsCoordinatorDelegate: MainCoordinatorDelegate {
    func showEditView(for data: CollectionStateEditingData, library: Library)
    func showCollectionsMenu(button: UIBarButtonItem, viewModel: ViewModel<CollectionsActionHandler>)
}

protocol MasterSettingsCoordinatorDelegate: class {
    func showPrivacyPolicy()
    func showAboutBeta()
    func dismiss()
}

final class MasterCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private(set) var visibleLibraryId: LibraryIdentifier

    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private unowned let mainCoordinatorDelegate: MainCoordinatorDelegate
    private let disposeBag: DisposeBag

    init(navigationController: UINavigationController, mainCoordinatorDelegate: MainCoordinatorDelegate, controllers: Controllers) {
        self.navigationController = navigationController
        self.mainCoordinatorDelegate = mainCoordinatorDelegate
        self.controllers = controllers
        self.childCoordinators = []
        self.visibleLibraryId = Defaults.shared.selectedLibrary
        self.disposeBag = DisposeBag()

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
        guard let syncScheduler = self.controllers.userControllers?.syncScheduler,
              let webSocketController = self.controllers.userControllers?.webSocketController,
              let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = SettingsState(isSyncing: syncScheduler.syncController.inProgress,
                                  isLogging: self.controllers.debugLogging.isEnabled,
                                  isUpdatingTranslators: self.controllers.translatorsController.isLoading.value,
                                  lastTranslatorUpdate: self.controllers.translatorsController.lastUpdate,
                                  websocketConnectionState: webSocketController.connectionState.value)
        let handler = SettingsActionHandler(dbStorage: dbStorage,
                                            fileStorage: self.controllers.fileStorage,
                                            sessionController: self.controllers.sessionController,
                                            webSocketController: webSocketController,
                                            syncScheduler: syncScheduler,
                                            debugLogging: self.controllers.debugLogging,
                                            translatorsController: self.controllers.translatorsController)
        let viewModel = ViewModel(initialState: state, handler: handler)

        // Showing alerts in SwiftUI in this case doesn't work. Observe state here and show appropriate alerts.
        viewModel.stateObservable
                 .observeOn(MainScheduler.instance)
                 .subscribe(onNext: { [weak self, weak viewModel] state in
                     guard let `self` = self, let viewModel = viewModel else { return }

                     if state.showDeleteAllQuestion {
                         self.showDeleteAllStorageAlert(viewModel: viewModel)
                     }

                     if let library = state.showDeleteLibraryQuestion {
                         self.showDeleteLibraryStorageAlert(for: library, viewModel: viewModel)
                     }

                    if state.showDeleteCacheQuestion {
                        self.showDeleteCacheStorageAlert(viewModel: viewModel)
                    }
                 })
                 .disposed(by: self.disposeBag)

        var view = SettingsView()
        view.coordinatorDelegate = self

        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.isModalInPresentation = true
        controller.modalPresentationStyle = .formSheet
        self.navigationController.parent?.present(controller, animated: true, completion: nil)
    }

    private func showDeleteAllStorageAlert(viewModel: ViewModel<SettingsActionHandler>) {
        self.showDeleteQuestion(title: L10n.Settings.Storage.deleteAllQuestion,
                                deleteAction: { [weak viewModel] in
                                    viewModel?.process(action: .deleteAllDownloads)
                                },
                                cancelAction: { [weak viewModel] in
                                    viewModel?.process(action: .showDeleteAllQuestion(false))
                                })
    }

    private func showDeleteLibraryStorageAlert(for library: Library, viewModel: ViewModel<SettingsActionHandler>) {
        self.showDeleteQuestion(title: L10n.Settings.Storage.deleteLibraryQuestion(library.name),
                                deleteAction: { [weak viewModel] in
                                    viewModel?.process(action: .deleteDownloadsInLibrary(library.identifier))
                                },
                                cancelAction: { [weak viewModel] in
                                    viewModel?.process(action: .showDeleteLibraryQuestion(nil))
                                })
    }

    private func showDeleteCacheStorageAlert(viewModel: ViewModel<SettingsActionHandler>) {
        self.showDeleteQuestion(title: L10n.Settings.Storage.deleteCacheQuestion,
                                deleteAction: { [weak viewModel] in
                                    viewModel?.process(action: .deleteCache)
                                },
                                cancelAction: { [weak viewModel] in
                                    viewModel?.process(action: .showDeleteCacheQuestion(false))
                                })
    }

    private func showDeleteQuestion(title: String, deleteAction: @escaping () -> Void, cancelAction: @escaping () -> Void) {
        let controller = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { _ in
            deleteAction()
        }))

        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { _ in
            cancelAction()
        }))

        // Settings are already presented, so present over them
        self.navigationController.presentedViewController?.present(controller, animated: true, completion: nil)
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

    func showCollectionsMenu(button: UIBarButtonItem, viewModel: ViewModel<CollectionsActionHandler>) {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.addAction(UIAlertAction(title: L10n.Collections.createTitle, style: .default, handler: { [weak viewModel] _ in
            viewModel?.process(action: .startEditing(.add))
        }))
        if viewModel.state.hasExpandableCollection {
            let allExpanded = viewModel.state.areAllExpanded
            controller.addAction(UIAlertAction(title: (allExpanded ? L10n.Collections.collapseAll : L10n.Collections.expandAll), style: .default, handler: { [weak viewModel] _ in
                viewModel?.process(action: (allExpanded ? .collapseAll : .expandAll))
            }))
        }
        controller.popoverPresentationController?.barButtonItem = button
        self.navigationController.present(controller, animated: true, completion: nil)
    }
}

extension MasterCoordinator: MasterSettingsCoordinatorDelegate {
    func showAboutBeta() {
        self.showSafar(with: URL(string: "https://www.zotero.org/support/ios_beta?app=1")!)
    }

    func showPrivacyPolicy() {
        self.showSafar(with: URL(string: "https://www.zotero.org/support/privacy?app=1")!)
    }

    private func showSafar(with url: URL) {
        let controller = SFSafariViewController(url: url)
        self.navigationController.presentedViewController?.present(controller, animated: true, completion: nil)
    }

    func dismiss() {
        self.navigationController.dismiss(animated: true, completion: nil)
    }
}
