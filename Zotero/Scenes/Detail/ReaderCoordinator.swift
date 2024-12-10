//
//  ReaderCoordinator.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 6/9/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import CocoaLumberjackSwift
import RxSwift

protocol ReaderError: Error {
    var title: String { get }
    var message: String { get }
}

protocol ReaderState {
    var userId: Int { get }
    var username: String { get }
    var displayName: String { get }

    var library: Library { get }

    var selectedReaderAnnotation: ReaderAnnotation? { get }

    var textFont: UIFont { get }
    var textEditorFont: UIFont { get }
    var commentFont: UIFont { get }
}

extension ReaderState {
    var displayName: String {
        return Defaults.shared.displayName
    }

    var textFont: UIFont {
        return PDFReaderLayout.annotationLayout.font
    }

    var textEditorFont: UIFont {
        return AnnotationPopoverLayout.annotationLayout.font
    }

    var commentFont: UIFont {
        return PDFReaderLayout.annotationLayout.font
    }
}

protocol ReaderCoordinatorDelegate: AnyObject {
    func show(error: ReaderError)
    func showToolSettings(tool: AnnotationTool, colorHex: String?, sizeValue: Float?, sender: SourceView, userInterfaceStyle: UIUserInterfaceStyle, valueChanged: @escaping (String?, Float?) -> Void)
}

protocol ReaderSidebarCoordinatorDelegate: AnyObject {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, userInterfaceStyle: UIUserInterfaceStyle?, picked: @escaping ([Tag]) -> Void)
    func showCellOptions(
        for annotation: ReaderAnnotation,
        userId: Int,
        library: Library,
        highlightFont: UIFont,
        sender: UIButton,
        userInterfaceStyle: UIUserInterfaceStyle,
        saveAction: @escaping AnnotationEditSaveAction,
        deleteAction: @escaping AnnotationEditDeleteAction
    )
    func showAnnotationPopover(
        state: ReaderState,
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
    func showSettings(with settings: ReaderSettings, sender: UIBarButtonItem) -> ViewModel<ReaderSettingsActionHandler>
}

protocol ReaderAnnotationsDelegate: AnyObject {
    func parseAndCacheIfNeededAttributedText(for annotation: ReaderAnnotation, with font: UIFont) -> NSAttributedString?
    func parseAndCacheIfNeededAttributedComment(for annotation: ReaderAnnotation) -> NSAttributedString?
}

protocol ReaderCoordinator: Coordinator, ReaderCoordinatorDelegate, ReaderSidebarCoordinatorDelegate {
    var controllers: Controllers { get }
}

extension ReaderCoordinator {
    func show(error: ReaderError) {
        let controller = UIAlertController(title: error.title, message: error.message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .default))
        navigationController?.present(controller, animated: true)
    }

    func showToolSettings(tool: AnnotationTool, colorHex: String?, sizeValue: Float?, sender: SourceView, userInterfaceStyle: UIUserInterfaceStyle, valueChanged: @escaping (String?, Float?) -> Void) {
        DDLogInfo("ReaderCoordinator: show tool settings for \(tool)")
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
}

extension ReaderCoordinator {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, userInterfaceStyle: UIUserInterfaceStyle?, picked: @escaping ([Tag]) -> Void) {
        guard let navigationController, let parentCoordinator = parentCoordinator as? DetailCoordinator else { return }
        parentCoordinator.showTagPicker(libraryId: libraryId, selected: selected, userInterfaceStyle: userInterfaceStyle, navigationController: navigationController, picked: picked)
    }

    func showCellOptions(
        for annotation: any ReaderAnnotation,
        userId: Int,
        library: Library,
        highlightFont: UIFont,
        sender: UIButton,
        userInterfaceStyle: UIUserInterfaceStyle,
        saveAction: @escaping AnnotationEditSaveAction,
        deleteAction: @escaping AnnotationEditDeleteAction
    ) {
        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle

        let highlightText: NSAttributedString = (self.navigationController?.viewControllers.first as? ReaderAnnotationsDelegate)?
            .parseAndCacheIfNeededAttributedText(for: annotation, with: highlightFont) ?? .init(string: "")
        let coordinator = AnnotationEditCoordinator(
            data: AnnotationEditState.Data(
                type: annotation.type,
                isEditable: annotation.editability(currentUserId: userId, library: library) == .editable,
                color: annotation.color,
                lineWidth: annotation.lineWidth ?? 0,
                pageLabel: annotation.pageLabel,
                highlightText: highlightText,
                highlightFont: highlightFont,
                fontSize: annotation.fontSize
            ),
            saveAction: saveAction,
            deleteAction: deleteAction,
            navigationController: navigationController,
            controllers: controllers
        )
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.sourceView = sender
            navigationController.popoverPresentationController?.permittedArrowDirections = .left
        }

        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    func showAnnotationPopover(
        state: ReaderState,
        sourceRect: CGRect,
        popoverDelegate: UIPopoverPresentationControllerDelegate,
        userInterfaceStyle: UIUserInterfaceStyle
    ) -> PublishSubject<AnnotationPopoverState>? {
        guard let currentNavigationController = navigationController, let annotation = state.selectedReaderAnnotation else { return nil }

        DDLogInfo("ReaderCoordinator: show annotation popover")

        if let coordinator = childCoordinators.last, coordinator is AnnotationPopoverCoordinator {
            DDLogWarn("ReaderCoordinator: another annotation popover is already showing, ignoring")
        }

        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle
        let author = state.library.identifier == .custom(.myLibrary) ? "" : annotation.author(displayName: state.displayName, username: state.username)
        let comment: NSAttributedString = (currentNavigationController.viewControllers.first as? ReaderAnnotationsDelegate)?
            .parseAndCacheIfNeededAttributedComment(for: annotation) ?? .init(string: "")
        let annotationText: NSAttributedString = (currentNavigationController.viewControllers.first as? ReaderAnnotationsDelegate)?
            .parseAndCacheIfNeededAttributedText(for: annotation, with: state.textEditorFont) ?? .init(string: "")
        let editability = annotation.editability(currentUserId: state.userId, library: state.library)
        let data = AnnotationPopoverState.Data(
            libraryId: state.library.identifier,
            type: annotation.type,
            isEditable: editability == .editable,
            author: author,
            comment: comment,
            color: annotation.color,
            lineWidth: annotation.lineWidth ?? 0,
            pageLabel: annotation.pageLabel,
            highlightText: annotationText,
            highlightFont: state.textEditorFont,
            tags: annotation.tags,
            showsDeleteButton: editability != .notEditable
        )
        let coordinator = AnnotationPopoverCoordinator(data: data, navigationController: navigationController, controllers: controllers)
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

    func showFilterPopup(
        from barButton: UIBarButtonItem,
        filter: AnnotationsFilter?,
        availableColors: [String],
        availableTags: [Tag],
        userInterfaceStyle: UIUserInterfaceStyle,
        completed: @escaping (AnnotationsFilter?) -> Void
    ) {
        DDLogInfo("ReaderCoordinator: show annotations filter popup")

        let navigationController = NavigationViewController()
        navigationController.overrideUserInterfaceStyle = userInterfaceStyle
        let coordinator = AnnotationsFilterPopoverCoordinator(
            initialFilter: filter,
            availableColors: availableColors,
            availableTags: availableTags,
            navigationController: navigationController,
            controllers: controllers,
            completionHandler: completed
        )
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.barButtonItem = barButton
            navigationController.popoverPresentationController?.permittedArrowDirections = .down
        }

        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    func showSettings(with settings: ReaderSettings, sender: UIBarButtonItem) -> ViewModel<ReaderSettingsActionHandler> {
        DDLogInfo("ReaderCoordinator: show settings")

        let state = ReaderSettingsState(settings: settings)
        let viewModel = ViewModel(initialState: state, handler: ReaderSettingsActionHandler())
        let baseController = ReaderSettingsViewController(rows: settings.rows, viewModel: viewModel)
        let controller: UIViewController
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller = baseController
        } else {
            controller = UINavigationController(rootViewController: baseController)
        }
        controller.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        controller.popoverPresentationController?.barButtonItem = sender
        controller.preferredContentSize = settings.preferredContentSize
        controller.overrideUserInterfaceStyle = settings.appearance.userInterfaceStyle
        navigationController?.present(controller, animated: true, completion: nil)

        return viewModel
    }
}
