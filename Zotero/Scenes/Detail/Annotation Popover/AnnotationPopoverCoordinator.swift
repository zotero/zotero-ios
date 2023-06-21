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
    var annotationKey: PDFReaderState.AnnotationKey? { get }
}

protocol AnnotationPopoverAnnotationCoordinatorDelegate: AnyObject {
    func createShareAnnotationMenu(sender: UIButton) -> UIMenu?
    func showEdit(annotation: Annotation, userId: Int, library: Library, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction)
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
    func didFinish()
}

protocol AnnotationEditCoordinatorDelegate: AnyObject {
    func showPageLabelEditor(label: String, updateSubsequentPages: Bool, saveAction: @escaping AnnotationPageLabelSaveAction)
}

final class AnnotationPopoverCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
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
        navigationController.dismissHandler = {
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
    func createShareAnnotationMenu(sender: UIButton) -> UIMenu? {
        guard let pdfCoordinator = parentCoordinator as? PDFCoordinator,
              let annotation = viewModel.state.selectedAnnotation
        else { return nil }
        return pdfCoordinator.createShareAnnotationMenu(
            state: viewModel.state,
            annotation: annotation,
            sender: sender
        )
    }
    
    func showEdit(annotation: Annotation, userId: Int, library: Library, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction) {
        let state = AnnotationEditState(annotation: annotation, userId: userId, library: library)
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
