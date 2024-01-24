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

protocol HtmlEpubReaderCoordinatorDelegate: AnyObject {
    func show(error: HtmlEpubReaderState.Error)
    func showToolSettings(tool: AnnotationTool, colorHex: String?, sizeValue: Float?, sender: SourceView, userInterfaceStyle: UIUserInterfaceStyle, valueChanged: @escaping (String?, Float?) -> Void)
}

protocol HtmlEpubSidebarCoordinatorDelegate: AnyObject {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, userInterfaceStyle: UIUserInterfaceStyle?, picked: @escaping ([Tag]) -> Void)
    func showCellOptions(
        for annotation: HtmlEpubAnnotation,
        userId: Int,
        library: Library,
        sender: UIButton,
        userInterfaceStyle: UIUserInterfaceStyle,
        saveAction: @escaping AnnotationEditSaveAction,
        deleteAction: @escaping AnnotationEditDeleteAction
    )
    func showAnnotationPopover(
        viewModel: ViewModel<HtmlEpubReaderActionHandler>,
        sourceRect: CGRect,
        popoverDelegate: UIPopoverPresentationControllerDelegate,
        userInterfaceStyle: UIUserInterfaceStyle
    ) -> PublishSubject<AnnotationPopoverState>?
    func showFilterPopup(
        from barButton: UIBarButtonItem,
        filter: AnnotationsFilter?,
        availableColors: [String],
        availableTags: [Tag],
        userInterfaceStyle: UIUserInterfaceStyle,
        completed: @escaping (AnnotationsFilter?) -> Void
    )
    func showSettings(with settings: HtmlEpubSettings, sender: UIBarButtonItem) -> ViewModel<ReaderSettingsActionHandler>
}

final class HtmlEpubCoordinator: Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    weak var navigationController: UINavigationController?

    private let key: String
    private let library: Library
    private let url: URL
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(key: String, library: Library, url: URL, navigationController: NavigationViewController, controllers: Controllers) {
        self.key = key
        self.library = library
        self.url = url
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        navigationController.dismissHandler = {
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    deinit {
        DDLogInfo("HtmlEpubCoordinator: deinitialized")
    }

    func start(animated: Bool) {
        let username = Defaults.shared.username
        guard let dbStorage = self.controllers.userControllers?.dbStorage,
              let userId = self.controllers.sessionController.sessionData?.userId,
              !username.isEmpty,
              let parentNavigationController = self.parentCoordinator?.navigationController
        else { return }

        let handler = HtmlEpubReaderActionHandler(
            dbStorage: dbStorage,
            schemaController: controllers.schemaController,
            htmlAttributedStringConverter: controllers.htmlAttributedStringConverter,
            dateParser: controllers.dateParser,
            idleTimerController: controllers.idleTimerController
        )
        let state = HtmlEpubReaderState(url: url, key: key, settings: Defaults.shared.htmlEpubSettings, library: library, userId: userId, username: username)
        let controller = HtmlEpubReaderViewController(
            viewModel: ViewModel(initialState: state, handler: handler),
            compactSize: UIDevice.current.isCompactWidth(size: parentNavigationController.view.frame.size)
        )
        controller.coordinatorDelegate = self

        self.navigationController?.setViewControllers([controller], animated: false)
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
        self.navigationController?.present(controller, animated: true)
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
            self.navigationController?.present(controller, animated: true, completion: nil)

        default:
            let navigationController = UINavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .formSheet
            navigationController.overrideUserInterfaceStyle = userInterfaceStyle
            self.navigationController?.present(navigationController, animated: true, completion: nil)
        }
    }
}

extension HtmlEpubCoordinator: HtmlEpubSidebarCoordinatorDelegate {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, userInterfaceStyle: UIUserInterfaceStyle?, picked: @escaping ([Tag]) -> Void) {
        guard let navigationController else { return }
        (self.parentCoordinator as? DetailCoordinator)?.showTagPicker(
            libraryId: libraryId,
            selected: selected,
            userInterfaceStyle: userInterfaceStyle,
            navigationController: navigationController,
            picked: picked
        )
    }
    
    func showCellOptions(
        for annotation: HtmlEpubAnnotation,
        userId: Int,
        library: Library,
        sender: UIButton,
        userInterfaceStyle: UIUserInterfaceStyle,
        saveAction: @escaping AnnotationEditSaveAction,
        deleteAction: @escaping AnnotationEditDeleteAction
    ) {
        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle

        let coordinator = AnnotationEditCoordinator(
            data: AnnotationEditState.AnnotationData(
                type: annotation.type,
                isEditable: annotation.editability(currentUserId: userId, library: library) == .editable,
                color: annotation.color,
                lineWidth: 0,
                pageLabel: annotation.pageLabel,
                highlightText: annotation.text ?? ""
            ),
            saveAction: saveAction,
            deleteAction: deleteAction,
            navigationController: navigationController,
            controllers: self.controllers
        )
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.sourceView = sender
            navigationController.popoverPresentationController?.permittedArrowDirections = .left
        }

        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    func showAnnotationPopover(
        viewModel: ViewModel<HtmlEpubReaderActionHandler>,
        sourceRect: CGRect,
        popoverDelegate: UIPopoverPresentationControllerDelegate,
        userInterfaceStyle: UIUserInterfaceStyle
    ) -> PublishSubject<AnnotationPopoverState>? {
        guard let currentNavigationController = self.navigationController, let annotation = viewModel.state.selectedAnnotationKey.flatMap({ viewModel.state.annotations[$0] }) else { return nil }

        DDLogInfo("HtmlEpubCoordinator: show annotation popover")

        if let coordinator = self.childCoordinators.last, coordinator is AnnotationPopoverCoordinator {
            return nil
        }

        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle

        let author = viewModel.state.library.identifier == .custom(.myLibrary) ? "" : annotation.author
        let comment = viewModel.state.comments[annotation.key] ?? NSAttributedString()
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
            highlightText: annotation.text ?? "",
            tags: annotation.tags,
            showsDeleteButton: editability != .notEditable
        )
        let coordinator = AnnotationPopoverCoordinator(data: data, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
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

    func showFilterPopup(
        from barButton: UIBarButtonItem,
        filter: AnnotationsFilter?,
        availableColors: [String],
        availableTags: [Tag],
        userInterfaceStyle: UIUserInterfaceStyle,
        completed: @escaping (AnnotationsFilter?) -> Void
    ) {
        DDLogInfo("HtmlEpubCoordinator: show annotations filter popup")

        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle

        let coordinator = AnnotationsFilterPopoverCoordinator(
            initialFilter: filter,
            availableColors: availableColors,
            availableTags: availableTags,
            navigationController: navigationController,
            controllers: self.controllers,
            completionHandler: completed
        )
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.barButtonItem = barButton
            navigationController.popoverPresentationController?.permittedArrowDirections = .down
        }

        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    func showSettings(with settings: HtmlEpubSettings, sender: UIBarButtonItem) -> ViewModel<ReaderSettingsActionHandler> {
        DDLogInfo("HtmlEpubCoordinator: show settings")

        let state = ReaderSettingsState(settings: settings)
        let viewModel = ViewModel(initialState: state, handler: ReaderSettingsActionHandler())
        let baseController = ReaderSettingsViewController(visibleRows: [.appearance, .sleep], viewModel: viewModel)

        let controller: UIViewController
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller = baseController
        } else {
            controller = UINavigationController(rootViewController: baseController)
        }

        controller.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        controller.popoverPresentationController?.barButtonItem = sender
        controller.preferredContentSize = CGSize(width: 480, height: 92)
        controller.overrideUserInterfaceStyle = settings.appearance.userInterfaceStyle
        self.navigationController?.present(controller, animated: true, completion: nil)

        return viewModel
    }
}
