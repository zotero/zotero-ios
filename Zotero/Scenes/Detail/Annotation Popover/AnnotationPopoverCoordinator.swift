//
//  AnnotationPopoverCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 20.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol AnnotationPopover: AnyObject {}

protocol AnnotationPopoverAnnotationCoordinatorDelegate: AnyObject {
    func createShareAnnotationMenu(sender: UIButton) -> UIMenu?
    func showEdit(state: AnnotationPopoverState, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction)
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
    func showFontSizePicker(picked: @escaping (CGFloat) -> Void)
    func didFinish()
}

protocol AnnotationEditCoordinatorDelegate: AnyObject {
    func showPageLabelEditor(label: String, updateSubsequentPages: Bool, saveAction: @escaping AnnotationPageLabelSaveAction)
    func showFontSizePicker(picked: @escaping (CGFloat) -> Void)
}

final class AnnotationPopoverCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    weak var navigationController: UINavigationController?
    private var finishing: Bool

    var viewModelObservable: PublishSubject<AnnotationPopoverState>? {
        return (navigationController?.viewControllers.first as? AnnotationPopoverViewController)?.viewModel.stateObservable
    }

    private let data: AnnotationPopoverState.Data
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(data: AnnotationPopoverState.Data, navigationController: NavigationViewController, controllers: Controllers) {
        self.data = data
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()
        finishing = false

        super.init()

        navigationController.delegate = self
        navigationController.dismissHandler = { [weak self] in
            self?.didFinish()
        }
    }

    func start(animated: Bool) {
        let state = AnnotationPopoverState(data: data)
        let handler = AnnotationPopoverActionHandler()
        let controller = AnnotationPopoverViewController(viewModel: ViewModel(initialState: state, handler: handler))
        controller.coordinatorDelegate = self
        self.navigationController?.isNavigationBarHidden = true
        self.navigationController?.setViewControllers([controller], animated: animated)
    }
}

extension AnnotationPopoverCoordinator: AnnotationPopoverAnnotationCoordinatorDelegate {
    func showFontSizePicker(picked: @escaping (CGFloat) -> Void) {
        let controller = FontSizePickerViewController(pickAction: picked)
        self.navigationController?.pushViewController(controller, animated: true)
    }

    func createShareAnnotationMenu(sender: UIButton) -> UIMenu? {
        return (parentCoordinator as? PDFCoordinator)?.createShareAnnotationMenuForSelectedAnnotation(sender: sender)
    }

    func showEdit(state: AnnotationPopoverState, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction) {
        let data = AnnotationEditState.Data(
            type: state.type,
            isEditable: state.isEditable,
            color: state.color,
            lineWidth: state.lineWidth,
            pageLabel: state.pageLabel,
            highlightText: state.highlightText,
            highlightFont: state.highlightFont,
            fontSize: nil
        )
        let state = AnnotationEditState(data: data)
        let handler = AnnotationEditActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationEditViewController(
            viewModel: viewModel,
            properties: AnnotationEditViewController.PropertyRow.from(type: state.type, isAdditionalSettings: true),
            saveAction: saveAction,
            deleteAction: deleteAction
        )
        controller.coordinatorDelegate = self
        self.navigationController?.pushViewController(controller, animated: true)
    }

    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: picked)
        controller.preferredContentSize = AnnotationPopoverLayout.tagPickerPreferredSize
        self.navigationController?.preferredContentSize = controller.preferredContentSize
        self.navigationController?.pushViewController(controller, animated: true)
    }

    func didFinish() {
        guard !finishing else { return }
        finishing = true
        parentCoordinator?.childDidFinish(self)
    }
}

extension AnnotationPopoverCoordinator: AnnotationEditCoordinatorDelegate {
    func showPageLabelEditor(label: String, updateSubsequentPages: Bool, saveAction: @escaping AnnotationPageLabelSaveAction) {
        let state = AnnotationPageLabelState(label: label, updateSubsequentPages: updateSubsequentPages)
        let handler = AnnotationPageLabelActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationPageLabelViewController(viewModel: viewModel, saveAction: saveAction)
        self.navigationController?.pushViewController(controller, animated: true)
    }
}

extension AnnotationPopoverCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        navigationController.setNavigationBarHidden((viewController is AnnotationPopoverViewController), animated: animated)
    }
}
