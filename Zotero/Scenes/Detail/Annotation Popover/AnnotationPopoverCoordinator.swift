//
//  AnnotationPopoverCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 20.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

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
    private weak var mainController: UIViewController?

    unowned let navigationController: UINavigationController
    private let sourceRect: CGRect
    private unowned let popoverDelegate: UIPopoverPresentationControllerDelegate
    private unowned let viewModel: ViewModel<PDFReaderActionHandler>
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(parentNavigationController: UINavigationController, popoverDelegate: UIPopoverPresentationControllerDelegate,
         sourceRect: CGRect, controllers: Controllers, viewModel: ViewModel<PDFReaderActionHandler>) {
        self.navigationController = parentNavigationController
        self.sourceRect = sourceRect
        self.popoverDelegate = popoverDelegate
        self.controllers = controllers
        self.viewModel = viewModel
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        super.init()
    }

    func start(animated: Bool) {
        let controller = AnnotationViewController(viewModel: self.viewModel, attributedStringConverter: self.controllers.htmlAttributedStringConverter)
        controller.coordinatorDelegate = self
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.modalPresentationStyle = .popover
            controller.popoverPresentationController?.sourceView = self.navigationController.view
            controller.popoverPresentationController?.sourceRect = self.sourceRect
            controller.popoverPresentationController?.permittedArrowDirections = [.left, .right]
            controller.popoverPresentationController?.delegate = self.popoverDelegate
        }
        self.mainController = controller

        self.navigationController.present(controller, animated: animated, completion: nil)
    }
}

extension AnnotationPopoverCoordinator: AnnotationPopoverAnnotationCoordinatorDelegate {
    func showEdit(annotation: Annotation, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction) {
        let state = AnnotationEditState(annotation: annotation)
        let handler = AnnotationEditActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationEditViewController(viewModel: viewModel, includeColorPicker: false, saveAction: saveAction, deleteAction: deleteAction)
        controller.coordinatorDelegate = self
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .currentContext
        self.mainController?.present(navigationController, animated: true, completion: nil)
    }

    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: picked)
        controller.preferredContentSize = AnnotationPopoverLayout.tagPickerPreferredSize

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .currentContext
        navigationController.preferredContentSize = controller.preferredContentSize
        self.mainController?.present(navigationController, animated: true, completion: nil)
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

#endif
