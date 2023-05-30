//
//  CreatorEditCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 27.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift
import SwiftUI

protocol CreatorEditCoordinatorDelegate: AnyObject {
    func showCreatorTypePicker(itemType: String, selected: String, picked: @escaping (String) -> Void)
}

final class CreatorEditCoordinator: Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    let creator: ItemDetailState.Creator
    let itemType: String
    let saved: CreatorEditSaveAction
    let deleted: CreatorEditDeleteAction?
    private unowned let controllers: Controllers
    unowned let navigationController: UINavigationController
    private let disposeBag: DisposeBag

    init(creator: ItemDetailState.Creator, itemType: String, saved: @escaping CreatorEditSaveAction, deleted: CreatorEditDeleteAction?,
         navigationController: NavigationViewController, controllers: Controllers) {
        self.creator = creator
        self.itemType = itemType
        self.saved = saved
        self.deleted = deleted
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        navigationController.dismissHandler = {
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    deinit {
        DDLogInfo("CreatorEditCoordinator: deinitialized")
    }

    func start(animated: Bool) {
        let state = CreatorEditState(itemType: self.itemType, creator: self.creator)
        let handler = CreatorEditActionHandler(schemaController: self.controllers.schemaController)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = CreatorEditViewController(viewModel: viewModel, saved: self.saved, deleted: self.deleted)
        controller.coordinatorDelegate = self

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet
        self.navigationController.setViewControllers([controller], animated: animated)
    }
}

extension CreatorEditCoordinator: CreatorEditCoordinatorDelegate {
    func showCreatorTypePicker(itemType: String, selected: String, picked: @escaping (String) -> Void) {
        let viewModel = CreatorTypePickerViewModelCreator.create(itemType: itemType, selected: selected,
                                                                 schemaController: self.controllers.schemaController)
        let view = SinglePickerView(requiresSaveButton: false, requiresCancelButton: false, saveAction: picked) { [weak navigationController] completion in
            navigationController?.popViewController(animated: true)
            completion?()
        }
        .environmentObject(viewModel)

        let controller = UIHostingController(rootView: view)
        self.navigationController.pushViewController(controller, animated: true)
    }
}
