//
//  AnnotationEditCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 07.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

final class AnnotationEditCoordinator: Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    weak var navigationController: UINavigationController?

    private let data: AnnotationEditState.Data
    private let saveAction: AnnotationEditSaveAction
    private let deleteAction: AnnotationEditDeleteAction
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(
        data: AnnotationEditState.Data,
        saveAction: @escaping AnnotationEditSaveAction,
        deleteAction: @escaping AnnotationEditDeleteAction,
        navigationController: NavigationViewController,
        controllers: Controllers
    ) {
        self.data = data
        self.saveAction = saveAction
        self.deleteAction = deleteAction
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
        let state = AnnotationEditState(data: data)
        let handler = AnnotationEditActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationEditViewController(viewModel: viewModel, includeColorPicker: true, saveAction: self.saveAction, deleteAction: self.deleteAction)
        controller.coordinatorDelegate = self
        self.navigationController?.setViewControllers([controller], animated: false)
    }
}

extension AnnotationEditCoordinator: AnnotationEditCoordinatorDelegate {
    func showPageLabelEditor(label: String, updateSubsequentPages: Bool, saveAction: @escaping AnnotationPageLabelSaveAction) {
        let state = AnnotationPageLabelState(label: label, updateSubsequentPages: updateSubsequentPages)
        let handler = AnnotationPageLabelActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationPageLabelViewController(viewModel: viewModel, saveAction: saveAction)
        self.navigationController?.pushViewController(controller, animated: true)
    }
}
