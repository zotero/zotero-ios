//
//  HtmlEpubCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 28.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import SafariServices
import SwiftUI
import UIKit

import CocoaLumberjackSwift
import RxSwift

protocol HtmlEpubReaderCoordinatorDelegate: ReaderCoordinatorDelegate, ReaderSidebarCoordinatorDelegate, ReadAloudCoordinatorDelegate {
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
    internal unowned let controllers: Controllers
    private let remoteVoicesController: RemoteVoicesController
    private let disposeBag: DisposeBag

    init(
        key: String,
        parentKey: String?,
        libraryId: LibraryIdentifier,
        url: URL,
        readerURL: URL?,
        preselectedAnnotationKey: String?,
        navigationController: NavigationViewController,
        controllers: Controllers
    ) {
        self.key = key
        self.parentKey = parentKey
        self.libraryId = libraryId
        self.url = url
        self.readerURL = readerURL
        self.preselectedAnnotationKey = preselectedAnnotationKey
        self.navigationController = navigationController
        self.controllers = controllers
        remoteVoicesController = RemoteVoicesController(apiClient: controllers.apiClient)
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
        guard let userControllers = controllers.userControllers,
              let userId = controllers.sessionController.sessionData?.userId,
              !username.isEmpty,
              let parentNavigationController = parentCoordinator?.navigationController
        else { return }

        let dbStorage = userControllers.dbStorage
        let settings = Defaults.shared.htmlEpubSettings
        let handler = HtmlEpubReaderActionHandler(
            dbStorage: dbStorage,
            schemaController: controllers.schemaController,
            htmlAttributedStringConverter: controllers.htmlAttributedStringConverter,
            dateParser: controllers.dateParser,
            fileStorage: controllers.fileStorage,
            idleTimerController: controllers.idleTimerController,
            lastReadWatcher: userControllers.lastReadWatcher
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
            interfaceStyle: settings.appearance == .automatic ? parentNavigationController.view.traitCollection.userInterfaceStyle : settings.appearance.userInterfaceStyle
        )
        let controller = HtmlEpubReaderViewController(
            viewModel: ViewModel(initialState: state, handler: handler),
            compactSize: UIDevice.current.isCompactWidth(size: parentNavigationController.view.frame.size),
            dbStorage: dbStorage,
            documentWorkerController: userControllers.documentWorkerController,
            remoteVoicesController: remoteVoicesController
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

extension HtmlEpubCoordinator: ReadAloudCoordinatorDelegate {
    func showVoicePicker(
        for voice: SpeechVoice,
        language: String?,
        detectedLanguage: String,
        userInterfaceStyle: UIUserInterfaceStyle,
        selectionChanged: @escaping (ReadAloudVoiceChange) -> Void
    ) {
        guard let navigationController else { return }
        let view = ReadAloudVoicePickerView(
            selectedVoice: voice,
            language: language,
            detectedLanguage: detectedLanguage,
            remoteVoicesController: remoteVoicesController,
            dismiss: { change in
                selectionChanged(change)
                navigationController.dismiss(animated: true)
            }
        )
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = userInterfaceStyle
        controller.modalPresentationStyle = .formSheet
        controller.isModalInPresentation = true
        if let presentedController = navigationController.presentedViewController {
            presentedController.present(controller, animated: true)
        } else {
            navigationController.present(controller, animated: true)
        }
    }

    func showReadAloudOnboarding(from presenter: UIViewController, language: String?, detectedLanguage: String, userInterfaceStyle: UIUserInterfaceStyle, completion: @escaping (SpeechVoice?) -> Void) {
        let view = ReadAloudOnboardingView(
            language: language,
            detectedLanguage: detectedLanguage,
            remoteVoicesController: remoteVoicesController,
            dismiss: { selectedVoice in
                presenter.dismiss(animated: true) {
                    completion(selectedVoice)
                }
            }
        )
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = userInterfaceStyle
        controller.modalPresentationStyle = .formSheet
        presenter.present(controller, animated: true)
    }

    func showReadAloudAddMoreTime(from presenter: UIViewController) {
        guard let url = URL(string: "https://www.zotero.org/settings/readaloud") else { return }
        let controller = SFSafariViewController(url: url)
        controller.modalPresentationStyle = .formSheet
        (presenter.presentedViewController ?? presenter).present(controller, animated: true)
    }
}
