//
//  HtmlEpubCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 28.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

protocol HtmlEpubReaderCoordinatorDelegate: ReaderCoordinatorDelegate, ReaderSidebarCoordinatorDelegate {
    func showDocumentChangedAlert(completed: @escaping () -> Void)
    func show(url: URL)
}

final class HtmlEpubCoordinator: ReaderCoordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    weak var navigationController: UINavigationController?

    private let key: String
    private let parentKey: String?
    private let libraryId: LibraryIdentifier
    private let url: URL
    internal unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(key: String, parentKey: String?, libraryId: LibraryIdentifier, url: URL, navigationController: NavigationViewController, controllers: Controllers) {
        self.key = key
        self.parentKey = parentKey
        self.libraryId = libraryId
        self.url = url
        self.navigationController = navigationController
        self.controllers = controllers
        childCoordinators = []
        disposeBag = DisposeBag()

        navigationController.dismissHandler = { [weak self] in
            guard let self else { return }
            parentCoordinator?.childDidFinish(self)
        }
    }

    deinit {
        DDLogInfo("HtmlEpubCoordinator: deinitialized")
    }

    func start(animated: Bool) {
        let username = Defaults.shared.username
        guard let dbStorage = controllers.userControllers?.dbStorage,
              let userId = controllers.sessionController.sessionData?.userId,
              !username.isEmpty,
              let parentNavigationController = parentCoordinator?.navigationController
        else { return }

        let settings = Defaults.shared.htmlEpubSettings
        let handler = HtmlEpubReaderActionHandler(
            dbStorage: dbStorage,
            schemaController: controllers.schemaController,
            htmlAttributedStringConverter: controllers.htmlAttributedStringConverter,
            dateParser: controllers.dateParser,
            fileStorage: controllers.fileStorage,
            idleTimerController: controllers.idleTimerController
        )
        let state = HtmlEpubReaderState(
            url: url,
            key: key,
            parentKey: parentKey,
            title: try? dbStorage.perform(request: ReadFilenameDbRequest(libraryId: libraryId, key: key), on: .main),
            settings: Defaults.shared.htmlEpubSettings,
            libraryId: libraryId,
            userId: userId,
            username: username,
            interfaceStyle: settings.appearance == .automatic ? parentNavigationController.view.traitCollection.userInterfaceStyle : settings.appearance.userInterfaceStyle
        )
        let controller = HtmlEpubReaderViewController(
            viewModel: ViewModel(initialState: state, handler: handler),
            compactSize: UIDevice.current.isCompactWidth(size: parentNavigationController.view.frame.size)
        )
        controller.coordinatorDelegate = self
        navigationController?.setViewControllers([controller], animated: false)
    }
}

extension HtmlEpubCoordinator: HtmlEpubReaderCoordinatorDelegate {
    func showDocumentChangedAlert(completed: @escaping () -> Void) {
        let controller = UIAlertController(title: L10n.warning, message: L10n.Errors.Pdf.documentChanged, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: { _ in completed() }))
        navigationController?.present(controller, animated: true)
    }

    func show(url: URL) {
        (parentCoordinator as? DetailCoordinator)?.show(url: url)
    }
}
