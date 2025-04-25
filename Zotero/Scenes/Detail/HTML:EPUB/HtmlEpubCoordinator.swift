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

protocol HtmlEpubReaderCoordinatorDelegate: ReaderCoordinatorDelegate {
    func showDocumentChangedAlert(completed: @escaping () -> Void)
    func show(url: URL)
}

protocol HtmlEpubSidebarCoordinatorDelegate: ReaderSidebarCoordinatorDelegate {
    func showAnnotationPopover(
        viewModel: ViewModel<HtmlEpubReaderActionHandler>,
        sourceRect: CGRect,
        popoverDelegate: UIPopoverPresentationControllerDelegate,
        userInterfaceStyle: UIUserInterfaceStyle
    ) -> PublishSubject<AnnotationPopoverState>?
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
    func show(error: HtmlEpubReaderState.Error) {
        let title: String
        let message: String

        switch error {
        case .cantAddAnnotations:
            title = L10n.error
            message = L10n.Errors.Pdf.cantAddAnnotations

        case .cantDeleteAnnotation:
            title = L10n.error
            message = L10n.Errors.Pdf.cantDeleteAnnotations

        case .cantUpdateAnnotation:
            title = L10n.error
            message = L10n.Errors.Pdf.cantUpdateAnnotation

        case .incompatibleDocument:
            title = L10n.error
            message = L10n.Errors.Pdf.cantUpdateAnnotation

        case .unknown:
            title = L10n.error
            message = L10n.Errors.unknown
        }

        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .default))
        navigationController?.present(controller, animated: true)
    }

    func showToolSettings(tool: AnnotationTool, colorHex: String?, sizeValue: Float?, sender: SourceView, userInterfaceStyle: UIUserInterfaceStyle, valueChanged: @escaping (String?, Float?) -> Void) {
        DDLogInfo("HtmlEpubCoordinator: show tool settings for \(tool)")
        let state = AnnotationToolOptionsState(tool: tool, colorHex: colorHex, size: sizeValue)
        let handler = AnnotationToolOptionsActionHandler()
        let controller = AnnotationToolOptionsViewController(viewModel: ViewModel(initialState: state, handler: handler), valueChanged: valueChanged)

        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            controller.overrideUserInterfaceStyle = userInterfaceStyle
            controller.modalPresentationStyle = .popover

            switch sender {
            case .view(let view, _):
                controller.popoverPresentationController?.sourceView = view

            case .item(let item):
                controller.popoverPresentationController?.barButtonItem = item
            }
            navigationController?.present(controller, animated: true, completion: nil)

        default:
            let navigationController = UINavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .formSheet
            navigationController.overrideUserInterfaceStyle = userInterfaceStyle
            self.navigationController?.present(navigationController, animated: true, completion: nil)
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

extension HtmlEpubCoordinator: HtmlEpubSidebarCoordinatorDelegate {
    func showAnnotationPopover(
        viewModel: ViewModel<HtmlEpubReaderActionHandler>,
        sourceRect: CGRect,
        popoverDelegate: UIPopoverPresentationControllerDelegate,
        userInterfaceStyle: UIUserInterfaceStyle
    ) -> PublishSubject<AnnotationPopoverState>? {
        guard let currentNavigationController = navigationController, let annotation = viewModel.state.annotationPopoverKey.flatMap({ viewModel.state.annotations[$0] }) else { return nil }

        DDLogInfo("HtmlEpubCoordinator: show annotation popover")

        if let coordinator = childCoordinators.last, coordinator is AnnotationPopoverCoordinator {
            return nil
        }

        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle
        let author = viewModel.state.library.identifier == .custom(.myLibrary) ? "" : annotation.author
        let comment: NSAttributedString = (self.navigationController?.viewControllers.first as? ReaderAnnotationsDelegate)?
            .parseAndCacheIfNeededAttributedComment(for: annotation) ?? .init(string: "")
        let highlightFont = viewModel.state.textFont
        let highlightText: NSAttributedString = (self.navigationController?.viewControllers.first as? ReaderAnnotationsDelegate)?
            .parseAndCacheIfNeededAttributedText(for: annotation, with: highlightFont) ?? .init(string: "")
        let editability = annotation.editability(currentUserId: viewModel.state.userId, library: viewModel.state.library)
        let data = AnnotationPopoverState.Data(
            libraryId: viewModel.state.library.identifier,
            type: annotation.type,
            isEditable: editability == .editable,
            author: author,
            comment: comment,
            color: annotation.color,
            lineWidth: 0,
            pageLabel: annotation.pageLabel,
            highlightText: highlightText,
            highlightFont: highlightFont,
            tags: annotation.tags,
            showsDeleteButton: editability != .notEditable
        )
        let coordinator = AnnotationPopoverCoordinator(data: data, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.sourceView = currentNavigationController.view
            navigationController.popoverPresentationController?.sourceRect = sourceRect
            navigationController.popoverPresentationController?.permittedArrowDirections = [.left, .right]
            navigationController.popoverPresentationController?.delegate = popoverDelegate
        }

        currentNavigationController.present(navigationController, animated: true, completion: nil)

        return coordinator.viewModelObservable
    }
}
