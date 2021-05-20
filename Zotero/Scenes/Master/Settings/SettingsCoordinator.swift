//
//  SettingsCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

import SafariServices
import RxSwift

protocol SettingsCoordinatorDelegate: AnyObject {
    func showPrivacyPolicy()
    func showSupport()
    func showAboutBeta()
    func showCitationSettings()
    func showCitationStyleManagement(viewModel: ViewModel<CitationsActionHandler>)
    func dismiss()
}

final class SettingsCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag
    private static let defaultSize: CGSize = CGSize(width: 540, height: 620)

    private var searchController: UISearchController?

    init(navigationController: NavigationViewController, controllers: Controllers) {
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        super.init()

        navigationController.delegate = self
        navigationController.dismissHandler = { [weak self] in
            guard let `self` = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        guard let syncScheduler = self.controllers.userControllers?.syncScheduler,
              let webSocketController = self.controllers.userControllers?.webSocketController,
              let dbStorage = self.controllers.userControllers?.dbStorage,
              let fileCleanupController = self.controllers.userControllers?.fileCleanupController else { return }

        let state = SettingsState(isSyncing: syncScheduler.syncController.inProgress,
                                  isLogging: self.controllers.debugLogging.isEnabled,
                                  isUpdatingTranslators: self.controllers.translatorsController.isLoading.value,
                                  lastTranslatorUpdate: self.controllers.translatorsController.lastUpdate,
                                  websocketConnectionState: webSocketController.connectionState.value)
        let handler = SettingsActionHandler(dbStorage: dbStorage,
                                            bundledDataStorage: self.controllers.bundledDataStorage,
                                            fileStorage: self.controllers.fileStorage,
                                            sessionController: self.controllers.sessionController,
                                            webSocketController: webSocketController,
                                            syncScheduler: syncScheduler,
                                            debugLogging: self.controllers.debugLogging,
                                            translatorsController: self.controllers.translatorsController,
                                            fileCleanupController: fileCleanupController)
        let viewModel = ViewModel(initialState: state, handler: handler)

        // Showing alerts in SwiftUI in this case doesn't work. Observe state here and show appropriate alerts.
        viewModel.stateObservable
                 .observe(on: MainScheduler.instance)
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

        viewModel.process(action: .startObserving)

        var view = SettingsListView()
        view.coordinatorDelegate = self

        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = SettingsCoordinator.defaultSize
        self.navigationController.setViewControllers([controller], animated: animated)
    }
}

extension SettingsCoordinator {
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

extension SettingsCoordinator: SettingsCoordinatorDelegate {
    func showAboutBeta() {
        self.showSafari(with: URL(string: "https://www.zotero.org/support/ios_beta?app=1")!)
    }

    func showSupport() {
        UIApplication.shared.open(URL(string: "https://forums.zotero.org/")!)
    }

    func showPrivacyPolicy() {
        self.showSafari(with: URL(string: "https://www.zotero.org/support/privacy?app=1")!)
    }

    private func showSafari(with url: URL) {
        let controller = SFSafariViewController(url: url)
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showCitationSettings() {
        let handler = CitationsActionHandler(apiClient: self.controllers.apiClient, bundledDataStorage: self.controllers.bundledDataStorage, fileStorage: self.controllers.fileStorage)
        let state = CitationsState()
        let viewModel = ViewModel(initialState: state, handler: handler)
        var view = CitationSettingsView()
        view.coordinatorDelegate = self

        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = SettingsCoordinator.defaultSize
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showCitationStyleManagement(viewModel: ViewModel<CitationsActionHandler>) {
        let view = CitationStyleDownloadView { [weak viewModel] style in
            viewModel?.process(action: .addStyle(style))
        }
        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = UIScreen.main.bounds.size
        // Setup search controller here, since SwiftUI doesn't support it
        controller.navigationItem.searchController = self.createSettingsSearchController(viewModel: viewModel)
        self.navigationController.pushViewController(controller, animated: true)
    }

    private func createSettingsSearchController(viewModel: ViewModel<CitationsActionHandler>) -> UISearchController {
        let searchController = UISearchController()
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.Items.searchTitle
        searchController.searchBar.rx.text.observe(on: MainScheduler.instance)
                                  .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                                  .subscribe(onNext: { [weak viewModel] text in
                                      viewModel?.process(action: .searchRemote(text ?? ""))
                                  })
                                  .disposed(by: self.disposeBag)
        return searchController
    }

    func dismiss() {
        self.navigationController.dismiss(animated: true, completion: nil)
    }
}

extension SettingsCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        navigationController.preferredContentSize = viewController.preferredContentSize
    }
}
