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
    func showCollections(for library: Library)
    func showSettings()
    func show(error: LibrariesError)
    func showDeleteGroupQuestion(id: Int, name: String, viewModel: ViewModel<LibrariesActionHandler>)
}

protocol MasterCollectionsCoordinatorDelegate: MainCoordinatorDelegate {
    func showEditView(for data: CollectionStateEditingData, library: Library)
}

protocol MasterSettingsCoordinatorDelegate: class {
    func showPrivacyPolicy()
    func showAboutBeta()
    func dismiss()
}

final class MasterCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    let defaultLibrary: Library
    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private unowned let mainCoordinatorDelegate: MainCoordinatorDelegate
    private let disposeBag: DisposeBag

    init(navigationController: UINavigationController, mainCoordinatorDelegate: MainCoordinatorDelegate, controllers: Controllers) {
        self.navigationController = navigationController
        self.mainCoordinatorDelegate = mainCoordinatorDelegate
        self.controllers = controllers
        self.childCoordinators = []
        self.defaultLibrary = Library(identifier: .custom(.myLibrary),
                                      name: RCustomLibraryType.myLibrary.libraryName,
                                      metadataEditable: true,
                                      filesEditable: true)
        self.disposeBag = DisposeBag()

        super.init()
    }

    func start(animated: Bool) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let librariesController = self.createLibrariesViewController(dbStorage: dbStorage)
        let collectionsController = self.createCollectionsViewController(library: self.defaultLibrary, dbStorage: dbStorage)
        self.navigationController.setViewControllers([librariesController, collectionsController], animated: animated)
    }

    private func createLibrariesViewController(dbStorage: DbStorage) -> UIViewController {
        let viewModel = ViewModel(initialState: LibrariesState(), handler: LibrariesActionHandler(dbStorage: dbStorage))
        let controller = LibrariesViewController(viewModel: viewModel)
        controller.coordinatorDelegate = self
        return controller
    }

    private func createCollectionsViewController(library: Library, dbStorage: DbStorage) -> CollectionsViewController {
        let handler = CollectionsActionHandler(dbStorage: dbStorage)
        let state = CollectionsState(library: library)
        let controller = CollectionsViewController(viewModel: ViewModel(initialState: state, handler: handler),
                                                   dragDropController: self.controllers.dragDropController)
        controller.coordinatorDelegate = self
        return controller
    }
}

extension MasterCoordinator: MasterLibrariesCoordinatorDelegate {
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

    func showCollections(for library: Library) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let controller = self.createCollectionsViewController(library: library, dbStorage: dbStorage)
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

    func show(collection: Collection, in library: Library) {
        self.mainCoordinatorDelegate.show(collection: collection, in: library)
    }

    var isSplit: Bool {
        return self.mainCoordinatorDelegate.isSplit
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
