//
//  AnnotationPopoverCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 20.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol AnnotationPopover: AnyObject {
    var annotationKey: String { get }
}

#if PDFENABLED

protocol AnnotationPopoverAnnotationCoordinatorDelegate: AnyObject {
    func showEdit(annotation: Annotation, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction)
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
    func didFinish()
}

protocol AnnotationEditCoordinatorDelegate: AnyObject {
    func showPageLabelEditor(label: String, updateSubsequentPages: Bool, saveAction: @escaping AnnotationPageLabelSaveAction)
}

final class AnnotationPopoverCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    unowned let navigationController: UINavigationController
    private unowned let viewModel: ViewModel<PDFReaderActionHandler>
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(navigationController: NavigationViewController, controllers: Controllers, viewModel: ViewModel<PDFReaderActionHandler>) {
        self.navigationController = navigationController
        self.controllers = controllers
        self.viewModel = viewModel
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
        let controller = AnnotationViewController(viewModel: self.viewModel, attributedStringConverter: self.controllers.htmlAttributedStringConverter)
        controller.coordinatorDelegate = self
        self.navigationController.isNavigationBarHidden = true
        self.navigationController.setViewControllers([controller], animated: animated)
    }
}

extension AnnotationPopoverCoordinator: AnnotationPopoverAnnotationCoordinatorDelegate {
    func showEdit(annotation: Annotation, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction) {
        let state = AnnotationEditState(annotation: annotation)
        let handler = AnnotationEditActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationEditViewController(viewModel: viewModel, includeColorPicker: false, saveAction: saveAction, deleteAction: deleteAction)
        controller.coordinatorDelegate = self
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: picked)
        controller.preferredContentSize = AnnotationPopoverLayout.tagPickerPreferredSize
        self.navigationController.preferredContentSize = controller.preferredContentSize
        self.navigationController.pushViewController(controller, animated: true)
    }

    func didFinish() {
        self.parentCoordinator?.childDidFinish(self)
    }
}

extension AnnotationPopoverCoordinator: AnnotationEditCoordinatorDelegate {
    func showPageLabelEditor(label: String, updateSubsequentPages: Bool, saveAction: @escaping AnnotationPageLabelSaveAction) {
        let state = AnnotationPageLabelState(label: label, updateSubsequentPages: updateSubsequentPages)
        let handler = AnnotationPageLabelActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationPageLabelViewController(viewModel: viewModel, saveAction: saveAction)
        self.navigationController.pushViewController(controller, animated: true)
    }
}

extension AnnotationPopoverCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        navigationController.setNavigationBarHidden((viewController is AnnotationViewController), animated: animated)
    }
}

#endif
