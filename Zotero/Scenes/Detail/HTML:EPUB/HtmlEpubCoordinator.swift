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
    func showSearch(
        viewModel: ViewModel<HtmlEpubReaderActionHandler>,
        documentController: HtmlEpubDocumentViewController,
        text: String?,
        sender: UIBarButtonItem,
        userInterfaceStyle: UIUserInterfaceStyle
    )
}

final class HtmlEpubCoordinator: ReaderCoordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    weak var navigationController: UINavigationController?
    private var searchController: DocumentSearchViewController?

    private let key: String
    private let parentKey: String?
    private let libraryId: LibraryIdentifier
    private let url: URL
    private let readerURL: URL?
    private let preselectedAnnotationKey: String?
    private let sessionIdentifier: String
    internal unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(
        key: String,
        parentKey: String?,
        libraryId: LibraryIdentifier,
        url: URL,
        readerURL: URL?,
        preselectedAnnotationKey: String?,
        navigationController: NavigationViewController,
        sessionIdentifier: String,
        controllers: Controllers
    ) {
        self.key = key
        self.parentKey = parentKey
        self.libraryId = libraryId
        self.url = url
        self.readerURL = readerURL
        self.preselectedAnnotationKey = preselectedAnnotationKey
        self.navigationController = navigationController
        self.sessionIdentifier = sessionIdentifier
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
              let parentNavigationController = parentCoordinator?.navigationController,
              let openItemsController = controllers.userControllers?.openItemsController
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
            readerURL: readerURL,
            url: url,
            key: key,
            parentKey: parentKey,
            title: try? dbStorage.perform(request: ReadFilenameDbRequest(libraryId: libraryId, key: key), on: .main),
            preselectedAnnotationKey: preselectedAnnotationKey,
            settings: Defaults.shared.htmlEpubSettings,
            libraryId: libraryId,
            userId: userId,
            username: username,
            interfaceStyle: settings.appearance == .automatic ? parentNavigationController.view.traitCollection.userInterfaceStyle : settings.appearance.userInterfaceStyle,
            openItemsCount: openItemsController.getItems(for: sessionIdentifier).count
        )
        let controller = HtmlEpubReaderViewController(
            viewModel: ViewModel(initialState: state, handler: handler),
            compactSize: UIDevice.current.isCompactWidth(size: parentNavigationController.view.frame.size),
            openItemsController: openItemsController
        )
        controller.coordinatorDelegate = self
        navigationController?.setViewControllers([controller], animated: false)
    }
}

extension HtmlEpubCoordinator: HtmlEpubReaderCoordinatorDelegate {
    func showSearch(
        viewModel: ViewModel<HtmlEpubReaderActionHandler>,
        documentController: HtmlEpubDocumentViewController,
        text: String?,
        sender: UIBarButtonItem,
        userInterfaceStyle: UIUserInterfaceStyle
    ) {
        DDLogInfo("PDFCoordinator: show search")

        if let searchController {
            if let controller = searchController.presentingViewController {
                controller.dismiss(animated: true) { [weak self] in
                    self?.showSearch(viewModel: viewModel, documentController: documentController, text: text, sender: sender, userInterfaceStyle: userInterfaceStyle)
                }
                return
            }

            searchController.overrideUserInterfaceStyle = userInterfaceStyle
            setupPresentation(for: searchController, with: sender)
            searchController.text = text

            navigationController?.present(searchController, animated: true, completion: nil)
            return
        }

        let handler = HtmlEpubSearchHandler(viewModel: viewModel, documentController: documentController)
        let viewController = DocumentSearchViewController(text: text, handler: handler)
        viewController.overrideUserInterfaceStyle = userInterfaceStyle
        setupPresentation(for: viewController, with: sender)
        self.searchController = viewController
        self.navigationController?.present(viewController, animated: true, completion: nil)

        func setupPresentation(for pdfSearchController: DocumentSearchViewController, with sender: UIBarButtonItem) {
            pdfSearchController.modalPresentationStyle = .popover
            pdfSearchController.popoverPresentationController?.sourceItem = (navigationController?.isNavigationBarHidden == false) ? sender : navigationController?.view
            pdfSearchController.popoverPresentationController?.sourceRect = .zero
        }
    }

    func showDocumentChangedAlert(completed: @escaping () -> Void) {
        let controller = UIAlertController(title: L10n.warning, message: L10n.Errors.Pdf.documentChanged, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: { _ in completed() }))
        navigationController?.present(controller, animated: true)
    }

    func show(url: URL) {
        (parentCoordinator as? DetailCoordinator)?.show(url: url)
    }
}

extension HtmlEpubCoordinator: OpenItemsPresenter {
    func showItem(with presentation: ItemPresentation?) {
        (parentCoordinator as? OpenItemsPresenter)?.showItem(with: presentation)
    }
}
