//
//  MasterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 08.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

protocol MasterContainerCoordinatorDelegate: AnyObject {
    func showDefaultCollection()
    func bottomController() -> DraggableViewController?
}

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
        let masterController = MasterContainerViewController(coordinatorDelegate: self)
        let masterCoordinator = MasterTopCoordinator(navigationController: masterController, mainCoordinatorDelegate: self.mainController, controllers: self.controllers)
        masterCoordinator.start(animated: false)
        self.topCoordinator = masterCoordinator
        self.mainController.viewControllers = [masterController]
    }
}

extension MasterCoordinator: MasterContainerCoordinatorDelegate {
    func showDefaultCollection() {
        topCoordinator?.showDefaultCollection()
    }
    
    func bottomController() -> DraggableViewController? {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return nil }
        guard let dbStorage = controllers.userControllers?.dbStorage else { return nil }
        let state = TagFilterState(selectedTags: [], showAutomatic: Defaults.shared.tagPickerShowAutomaticTags, displayAll: Defaults.shared.tagPickerDisplayAllTags)
        let handler = TagFilterActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        return TagFilterViewController(viewModel: viewModel, dragDropController: controllers.dragDropController)
    }
}
