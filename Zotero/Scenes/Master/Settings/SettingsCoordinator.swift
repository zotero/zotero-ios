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
    func showCitationStyleManagement(viewModel: ViewModel<CitationStylesActionHandler>)
    func showExportSettings()
    func dismiss()
}

protocol CitationStyleSearchSettingsCoordinatorDelegate: AnyObject {
    func showError(retryAction: @escaping () -> Void, cancelAction: @escaping () -> Void)
}

protocol ExportSettingsCoordinatorDelegate: AnyObject {
    func showStylePicker(picked: @escaping (String) -> Void)
    func showLocalePicker(picked: @escaping (String) -> Void)
}

final class SettingsCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag
    private static let defaultSize: CGSize = CGSize(width: 580, height: 620)

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
                                  isUpdatingTranslators: self.controllers.translatorsAndStylesController.isLoading.value,
                                  lastTranslatorUpdate: self.controllers.translatorsAndStylesController.lastUpdate,
                                  websocketConnectionState: webSocketController.connectionState.value)
        let handler = SettingsActionHandler(dbStorage: dbStorage,
                                            bundledDataStorage: self.controllers.bundledDataStorage,
                                            fileStorage: self.controllers.fileStorage,
                                            sessionController: self.controllers.sessionController,
                                            webSocketController: webSocketController,
                                            syncScheduler: syncScheduler,
                                            debugLogging: self.controllers.debugLogging,
                                            translatorsAndStylesController: self.controllers.translatorsAndStylesController,
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
        let handler = CitationStylesActionHandler(apiClient: self.controllers.apiClient, bundledDataStorage: self.controllers.bundledDataStorage, fileStorage: self.controllers.fileStorage)
        let state = CitationStylesState()
        let viewModel = ViewModel(initialState: state, handler: handler)
        var view = CitationStylesSettingsView()
        view.coordinatorDelegate = self

        viewModel.stateObservable.subscribe(onNext: { [weak self] state in
            if let error = state.error {
                self?.showCitationSettings(error: error)
            }
        }).disposed(by: self.disposeBag)

        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = UIScreen.main.bounds.size
        self.navigationController.pushViewController(controller, animated: true)
    }

    private func showCitationSettings(error: CitationStylesState.Error) {
        let message: String
        switch error {
        case .deletion(let name, _):
            message = L10n.Errors.Styles.addition(name)
        case .addition(let name, _):
            message = L10n.Errors.Styles.deletion(name)
        case .loading:
            message = L10n.Errors.Styles.loading
        }

        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showCitationStyleManagement(viewModel: ViewModel<CitationStylesActionHandler>) {
        var installedIds: Set<String> = []
        for style in viewModel.state.styles {
            installedIds.insert(style.identifier)
        }

        let handler = CitationStylesSearchActionHandler(apiClient: self.controllers.apiClient)
        let state = CitationStylesSearchState(installedIds: installedIds)
        let searchViewModel = ViewModel(initialState: state, handler: handler)

        let controller = CitationStyleSearchViewController(viewModel: searchViewModel) { [weak viewModel] style in
            viewModel?.process(action: .add(style))
        }
        controller.coordinatorDelegate = self
        controller.preferredContentSize = UIScreen.main.bounds.size
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showExportSettings() {
        let localeId = Defaults.shared.exportDefaultLocaleId
        let language = Locale.current.localizedString(forLanguageCode: localeId) ?? localeId
        let styleId = Defaults.shared.exportDefaultStyleId
        let style = (try? self.controllers.bundledDataStorage.createCoordinator().perform(request: ReadStyleDbRequest(identifier: styleId)))?.title ?? styleId
        
        let state = ExportState(style: style, language: language, copyAsHtml: Defaults.shared.exportCopyAsHtml)
        let handler = ExportActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        var view = ExportSettingsView()
        view.coordinatorDelegate = self

        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = SettingsCoordinator.defaultSize
        self.navigationController.pushViewController(controller, animated: true)
    }

    func dismiss() {
        self.navigationController.dismiss(animated: true, completion: nil)
    }
}

extension SettingsCoordinator: CitationStyleSearchSettingsCoordinatorDelegate {
    func showError(retryAction: @escaping () -> Void, cancelAction: @escaping () -> Void) {
        let controller = UIAlertController(title: L10n.error, message: L10n.Errors.StylesSearch.loading, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.retry, style: .default, handler: { _ in
            retryAction()
        }))
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { _ in
            cancelAction()
        }))
        self.navigationController.present(controller, animated: true, completion: nil)
    }
}

extension SettingsCoordinator: ExportSettingsCoordinatorDelegate {
    func showStylePicker(picked: @escaping (String) -> Void) {
        let handler = StylePickerActionHandler(dbStorage: self.controllers.bundledDataStorage)
        let state = StylePickerState(selected: Defaults.shared.exportDefaultStyleId)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let view = StylePickerView(picked: picked)
        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = UIScreen.main.bounds.size
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showLocalePicker(picked: @escaping (String) -> Void) {
        let handler = ExportLocalePickerActionHandler(fileStorage: self.controllers.fileStorage)
        let state = ExportLocalePickerState(selected: Defaults.shared.exportDefaultLocaleId)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let view = ExportLocalePickerView(picked: picked)
        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = UIScreen.main.bounds.size
        self.navigationController.pushViewController(controller, animated: true)
    }
}

extension SettingsCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard viewController.preferredContentSize.width > 0 && viewController.preferredContentSize.height > 0 else { return }
        navigationController.preferredContentSize = viewController.preferredContentSize
    }
}
