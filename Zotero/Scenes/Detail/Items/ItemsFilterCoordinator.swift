//
//  ItemsFilterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol ItemsFilterCoordinatorDelegate: AnyObject {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
}

final class ItemsFilterCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    private unowned let viewModel: ViewModel<ItemsActionHandler>
    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers

    init(viewModel: ViewModel<ItemsActionHandler>, navigationController: NavigationViewController, controllers: Controllers) {
        self.viewModel = viewModel
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []

        super.init()

        navigationController.dismissHandler = { [weak self] in
            guard let `self` = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let controller = ItemsFilterViewController(viewModel: self.viewModel, dbStorage: dbStorage)
        controller.coordinatorDelegate = self
        self.navigationController.setViewControllers([controller], animated: animated)
    }
}

extension ItemsFilterCoordinator: ItemsFilterCoordinatorDelegate {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: picked)
        self.navigationController.pushViewController(controller, animated: true)
    }
}
