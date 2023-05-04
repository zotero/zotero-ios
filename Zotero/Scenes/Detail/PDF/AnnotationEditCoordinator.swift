//
//  AnnotationEditCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 07.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import CocoaLumberjackSwift
import RxSwift

final class AnnotationEditCoordinator: Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    private let annotation: Annotation
    private let userId: Int
    private let library: Library
    private let saveAction: AnnotationEditSaveAction
    private let deleteAction: AnnotationEditDeleteAction
    private let shareAction: AnnotationEditShareAction
    private unowned let controllers: Controllers
    unowned let navigationController: UINavigationController
    private let disposeBag: DisposeBag

    init(annotation: Annotation, userId: Int, library: Library, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction, shareAction: @escaping AnnotationEditShareAction,
         navigationController: NavigationViewController, controllers: Controllers) {
        self.annotation = annotation
        self.userId = userId
        self.library = library
        self.saveAction = saveAction
        self.deleteAction = deleteAction
        self.shareAction = shareAction
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        navigationController.dismissHandler = {
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    deinit {
        DDLogInfo("AnnotationEditCoordinator: deinitialized")
    }

    func start(animated: Bool) {
        let state = AnnotationEditState(annotation: self.annotation, userId: self.userId, library: self.library)
        let handler = AnnotationEditActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationEditViewController(viewModel: viewModel, includeColorPicker: true, saveAction: self.saveAction, deleteAction: self.deleteAction, shareAction: self.shareAction)
        controller.coordinatorDelegate = self
        self.navigationController.setViewControllers([controller], animated: false)
    }
}

extension AnnotationEditCoordinator: AnnotationEditCoordinatorDelegate {
    func showPageLabelEditor(label: String, updateSubsequentPages: Bool, saveAction: @escaping AnnotationPageLabelSaveAction) {
        let state = AnnotationPageLabelState(label: label, updateSubsequentPages: updateSubsequentPages)
        let handler = AnnotationPageLabelActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationPageLabelViewController(viewModel: viewModel, saveAction: saveAction)
        self.navigationController.pushViewController(controller, animated: true)
    }
}

#endif
