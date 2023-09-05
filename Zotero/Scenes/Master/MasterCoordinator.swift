//
//  MasterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 08.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

final class MasterCoordinator {
    private let controllers: Controllers
    private unowned let mainController: MainViewController

    private(set) var topCoordinator: MasterTopCoordinator!

    init(mainController: MainViewController, controllers: Controllers) {
        self.mainController = mainController
        self.controllers = controllers
    }

    deinit {
        DDLogInfo("MasterCoordinator: deinitialized")
    }

    func start() {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            self.startPad()

        default:
            self.startPhone()
        }
    }

    private func startPad() {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        
        let state = TagFilterState(selectedTags: [], showAutomatic: Defaults.shared.tagPickerShowAutomaticTags, displayAll: Defaults.shared.tagPickerDisplayAllTags)
        let handler = TagFilterActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let tagController = TagFilterViewController(viewModel: viewModel, dragDropController: self.controllers.dragDropController)
        tagController.view.backgroundColor = .systemGreen

        let containerController = MasterContainerViewController(bottomController: tagController)
        let masterController = containerController
        let masterCoordinator = MasterTopCoordinator(navigationController: masterController, mainCoordinatorDelegate: self.mainController, controllers: self.controllers)
        masterCoordinator.start(animated: false)
        self.topCoordinator = masterCoordinator
        self.mainController.viewControllers = [containerController]
    }

    // TODO: Merge startPad() and startPhone() methods to one adaptive workflow
    private func startPhone() {
        let masterController = UINavigationController()
        let masterCoordinator = MasterTopCoordinator(navigationController: masterController, mainCoordinatorDelegate: self.mainController, controllers: self.controllers)
        masterCoordinator.start(animated: false)
        self.topCoordinator = masterCoordinator

        self.mainController.viewControllers = [masterController]
    }
}
