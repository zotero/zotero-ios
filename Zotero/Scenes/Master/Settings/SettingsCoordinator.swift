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
    func showSync()
    func showPrivacyPolicy()
    func showSupport()
    func showAboutBeta()
    func showCitationSettings()
    func showCitationStyleManagement(viewModel: ViewModel<CiteActionHandler>)
    func showExportSettings()
    func showStorageSettings()
    func showDebugging()
    func showSavingSettings()
    func showGeneralSettings()
    func dismiss()
    func showLogoutAlert(viewModel: ViewModel<SyncSettingsActionHandler>)
}

protocol CitationStyleSearchSettingsCoordinatorDelegate: AnyObject {
    func showError(retryAction: @escaping () -> Void, cancelAction: @escaping () -> Void)
}

protocol ExportSettingsCoordinatorDelegate: AnyObject {
    func showStylePicker(picked: @escaping (Style) -> Void)
    func showLocalePicker(picked: @escaping (ExportLocale) -> Void)
}

protocol StorageSettingsSettingsCoordinatorDelegate: AnyObject {
    func showDeleteAllStorageAlert(viewModel: ViewModel<StorageSettingsActionHandler>)
    func showDeleteLibraryStorageAlert(for library: Library, viewModel: ViewModel<StorageSettingsActionHandler>)
}

final class SettingsCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private let startsWithExport: Bool
    private let disposeBag: DisposeBag
    private static let defaultSize: CGSize = CGSize(width: 580, height: 620)

    private var searchController: UISearchController?

    init(startsWithExport: Bool, navigationController: NavigationViewController, controllers: Controllers) {
        self.navigationController = navigationController
        self.controllers = controllers
        self.startsWithExport = startsWithExport
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
        guard let listController = self.createListController() else { return }

        var controllers: [UIViewController] = [listController]
        if self.startsWithExport {
            controllers.append(self.createExportController())
        }
        self.navigationController.setViewControllers(controllers, animated: animated)
    }

    private func createListController() -> UIViewController? {
        let handler = SettingsActionHandler(sessionController: self.controllers.sessionController)
        let viewModel = ViewModel(initialState: SettingsState(), handler: handler)
        var view = SettingsListView()
        view.coordinatorDelegate = self

        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = SettingsCoordinator.defaultSize
        return controller
    }

    private func createExportController() -> UIViewController {
        let style = try? self.controllers.bundledDataStorage.createCoordinator().perform(request: ReadStyleDbRequest(identifier: Defaults.shared.quickCopyStyleId))

        let language: String
        if let defaultLocale = style?.defaultLocale, !defaultLocale.isEmpty {
            language = Locale.current.localizedString(forLanguageCode: defaultLocale) ?? defaultLocale
        } else {
            let localeId = Defaults.shared.quickCopyLocaleId
            language = Locale.current.localizedString(forLanguageCode: localeId) ?? localeId
        }

        let state = ExportState(style: (style?.title ?? L10n.unknown), language: language, languagePickerEnabled: (style?.defaultLocale.isEmpty ?? true), copyAsHtml: Defaults.shared.quickCopyAsHtml)
        let handler = ExportActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        var view = ExportSettingsView()
        view.coordinatorDelegate = self

        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = SettingsCoordinator.defaultSize
        return controller
    }
}

extension SettingsCoordinator: StorageSettingsSettingsCoordinatorDelegate {
    func showDeleteAllStorageAlert(viewModel: ViewModel<StorageSettingsActionHandler>) {
        self.showDeleteQuestion(message: L10n.Settings.Storage.deleteAllQuestion,
                                deleteAction: { [weak viewModel] in
                                    viewModel?.process(action: .deleteAll)
                                })
    }

    func showDeleteLibraryStorageAlert(for library: Library, viewModel: ViewModel<StorageSettingsActionHandler>) {
        self.showDeleteQuestion(message: L10n.Settings.Storage.deleteLibraryQuestion(library.name),
                                deleteAction: { [weak viewModel] in
                                    viewModel?.process(action: .deleteInLibrary(library.identifier))
                                })
    }

    private func showDeleteQuestion(message: String, deleteAction: @escaping () -> Void) {
        let controller = UIAlertController(title: L10n.warning, message: message, preferredStyle: .alert)

        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { _ in
            deleteAction()
        }))

        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))

        // Settings are already presented, so present over them
        self.navigationController.present(controller, animated: true, completion: nil)
    }
}

extension SettingsCoordinator: SettingsCoordinatorDelegate {
    func showSync() {
        let handler = SyncSettingsActionHandler(sessionController: self.controllers.sessionController, webDavController: self.controllers.webDavController)
        let state = SyncSettingsState(account: Defaults.shared.username,
                                      fileSyncType: (self.controllers.webDavController.sessionStorage.isEnabled ? .webDav : .zotero),
                                      scheme: self.controllers.webDavController.sessionStorage.scheme,
                                      url: self.controllers.webDavController.sessionStorage.url,
                                      username: self.controllers.webDavController.sessionStorage.username,
                                      password: self.controllers.webDavController.sessionStorage.password)
        let viewModel = ViewModel(initialState: state, handler: handler)
        var view = ProfileView()
        view.coordinatorDelegate = self

        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = SettingsCoordinator.defaultSize
        self.navigationController.pushViewController(controller, animated: true)
    }

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
        let handler = CiteActionHandler(apiClient: self.controllers.apiClient, bundledDataStorage: self.controllers.bundledDataStorage, fileStorage: self.controllers.fileStorage)
        let viewModel = ViewModel(initialState: CiteState(), handler: handler)
        var view = CiteSettingsView()
        view.coordinatorDelegate = self

        viewModel.stateObservable.subscribe(onNext: { [weak self] state in
            if let error = state.error {
                self?.showCitationSettings(error: error)
            }
        }).disposed(by: self.disposeBag)

        self.pushDefaultSize(view: view.environmentObject(viewModel))
    }

    private func showCitationSettings(error: CiteState.Error) {
        let message: String
        switch error {
        case .deletion(let name, _):
            message = L10n.Errors.Styles.deletion(name)
        case .addition(let name, _):
            message = L10n.Errors.Styles.addition(name)
        case .loading:
            message = L10n.Errors.Styles.loading
        }

        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showCitationStyleManagement(viewModel: ViewModel<CiteActionHandler>) {
        var installedIds: Set<String> = []
        for style in viewModel.state.styles {
            installedIds.insert(style.identifier)
        }

        let handler = CiteSearchActionHandler(apiClient: self.controllers.apiClient)
        let state = CiteSearchState(installedIds: installedIds)
        let searchViewModel = ViewModel(initialState: state, handler: handler)

        let controller = CiteSearchViewController(viewModel: searchViewModel) { [weak viewModel] style in
            viewModel?.process(action: .add(style))
        }
        controller.coordinatorDelegate = self
        controller.preferredContentSize = UIScreen.main.bounds.size
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showExportSettings() {
        let controller = self.createExportController()
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showStorageSettings() {
        guard let dbStorage = self.controllers.userControllers?.dbStorage,
              let fileCleanupController = self.controllers.userControllers?.fileCleanupController else { return }

        let handler = StorageSettingsActionHandler(dbStorage: dbStorage, fileStorage: self.controllers.fileStorage, fileCleanupController: fileCleanupController)
        let viewModel = ViewModel(initialState: StorageSettingsState(), handler: handler)
        var view = StorageSettingsView()
        view.coordinatorDelegate = self
        self.pushDefaultSize(view: view.environmentObject(viewModel))
    }

    func showDebugging() {
        let handler = DebuggingActionHandler(debugLogging: self.controllers.debugLogging)
        let viewModel = ViewModel(initialState: DebuggingState(isLogging: self.controllers.debugLogging.isEnabled), handler: handler)
        let view = DebuggingView().environmentObject(viewModel)
        self.pushDefaultSize(view: view)
    }

    func showSavingSettings() {
        let viewModel = ViewModel(initialState: SavingSettingsState(), handler: SavingSettingsActionHandler())
        let view = SavingSettingsView().environmentObject(viewModel)
        self.pushDefaultSize(view: view)
    }

    func showLogoutAlert(viewModel: ViewModel<SyncSettingsActionHandler>) {
        let controller = UIAlertController(title: L10n.warning, message: L10n.Settings.logoutWarning, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: .default, handler: { [weak viewModel] _ in
            viewModel?.process(action: .logout)
        }))
        controller.addAction(UIAlertAction(title: L10n.no, style: .cancel, handler: nil))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showGeneralSettings() {
        let viewModel = ViewModel(initialState: GeneralSettingsState(), handler: GeneralSettingsActionHandler())
        let view = GeneralSettingsView().environmentObject(viewModel)
        self.pushDefaultSize(view: view)
    }

    func dismiss() {
        self.navigationController.dismiss(animated: true, completion: nil)
    }

    private func pushDefaultSize<V: View>(view: V) {
        let controller = UIHostingController(rootView: view)
        controller.preferredContentSize = SettingsCoordinator.defaultSize
        self.navigationController.pushViewController(controller, animated: true)
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
    func showStylePicker(picked: @escaping (Style) -> Void) {
        let handler = StylePickerActionHandler(dbStorage: self.controllers.bundledDataStorage)
        let state = StylePickerState(selected: Defaults.shared.quickCopyStyleId)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let view = StylePickerView(picked: picked)
        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = SettingsCoordinator.defaultSize
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showLocalePicker(picked: @escaping (ExportLocale) -> Void) {
        let handler = ExportLocalePickerActionHandler(fileStorage: self.controllers.fileStorage)
        let state = ExportLocalePickerState(selected: Defaults.shared.quickCopyLocaleId)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let view = ExportLocalePickerView(picked: picked)
        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = SettingsCoordinator.defaultSize
        self.navigationController.pushViewController(controller, animated: true)
    }
}

extension SettingsCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard viewController.preferredContentSize.width > 0 && viewController.preferredContentSize.height > 0 else { return }
        navigationController.preferredContentSize = viewController.preferredContentSize
    }
}
