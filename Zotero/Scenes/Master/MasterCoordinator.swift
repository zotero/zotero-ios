//
//  MasterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 08.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class MasterCoordinator {
    private let controllers: Controllers
    private unowned let mainController: MainViewController

    private(set) var topCoordinator: MasterTopCoordinator!

    init(mainController: MainViewController, controllers: Controllers) {
        self.mainController = mainController
        self.controllers = controllers
    }

    func start() {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let masterController = UINavigationController()
        let masterCoordinator = MasterTopCoordinator(navigationController: masterController, mainCoordinatorDelegate: self.mainController, controllers: self.controllers)
        masterCoordinator.start(animated: false)
        self.topCoordinator = masterCoordinator

        let state = TagPickerState(libraryId: Defaults.shared.selectedLibrary, selectedTags: [])
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let tagController = TagFilterViewController(viewModel: viewModel)

        let containerController = MasterContainerViewController(topController: masterController, bottomController: tagController)
        self.mainController.viewControllers = [containerController]
    }
}
