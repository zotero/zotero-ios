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

protocol MasterLibrariesCoordinatorDelegate: class {
    func showCollections(for library: Library)
    func showSettings()
}

protocol MasterCollectionsCoordinatorDelegate: MainCoordinatorDelegate {
    func showEditView(for data: CollectionStateEditingData, library: Library)
}

protocol MasterSettingsCoordinatorDelegate: class {
    func dismiss()
}

class MasterCoordinator: NSObject, Coordinator {
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
        // SWIFTUI BUG: - We need to call loadData here, because when we do so in `onAppear` in SwiftuI `View` we'll crash when data change
        // instantly in that function. If we delay it, the user will see unwanted animation of data on screen. If we call it here, data
        // is available immediately.
        viewModel.process(action: .loadData)
        var view = LibrariesView()
        view.coordinatorDelegate = self
        return UIHostingController(rootView: view.environmentObject(viewModel))
    }

    private func createCollectionsViewController(library: Library, dbStorage: DbStorage) -> CollectionsViewController {
        let handler = CollectionsActionHandler(dbStorage: dbStorage)
        let state = CollectionsState(library: library)
        let controller = CollectionsViewController(viewModel: ViewModel(initialState: state, handler: handler),
                                                   dbStorage: dbStorage,
                                                   dragDropController: self.controllers.dragDropController)
        controller.coordinatorDelegate = self
        return controller
    }
}

extension MasterCoordinator: MasterLibrariesCoordinatorDelegate {
    func showCollections(for library: Library) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let controller = self.createCollectionsViewController(library: library, dbStorage: dbStorage)
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showSettings() {
        guard let syncScheduler = self.controllers.userControllers?.syncScheduler,
              let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let state = SettingsState(isSyncing: syncScheduler.syncController.inProgress,
                                  isLogging: self.controllers.debugLogging.isEnabled,
                                  isUpdatingTranslators: self.controllers.translatorsController.isLoading.value,
                                  lastTranslatorUpdate: self.controllers.translatorsController.lastUpdate)
        let handler = SettingsActionHandler(dbStorage: dbStorage,
                                            fileStorage: self.controllers.fileStorage,
                                            sessionController: self.controllers.sessionController,
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
        let controller = UIAlertController(title: L10n.Settings.Storage.deleteAllQuestion, message: nil, preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { [weak viewModel] _ in
            viewModel?.process(action: .deleteAllDownloads)
        }))

        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { [weak viewModel] _ in
            viewModel?.process(action: .showDeleteAllQuestion(false))
        }))

        // Settings are already presented, so present over them
        self.navigationController.presentedViewController?.present(controller, animated: true, completion: nil)
    }

    private func showDeleteLibraryStorageAlert(for library: Library, viewModel: ViewModel<SettingsActionHandler>) {
        let controller = UIAlertController(title: L10n.Settings.Storage.deleteLibraryQuestion(library.name), message: nil, preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { [weak viewModel] _ in
            viewModel?.process(action: .deleteDownloadsInLibrary(library.identifier))
        }))

        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { [weak viewModel] _ in
            viewModel?.process(action: .showDeleteLibraryQuestion(nil))
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
    func dismiss() {
        self.navigationController.dismiss(animated: true, completion: nil)
    }
}
