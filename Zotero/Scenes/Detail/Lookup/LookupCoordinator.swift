//
//  LookupCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 16.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

enum LookupStartingView {
    case scanner
    case manual
}

protocol LookupCoordinatorDelegate: AnyObject {
    func lookupController(multiLookupEnabled: Bool, hasDarkBackground: Bool) -> LookupViewController?
}

final class LookupCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    private let startingView: LookupStartingView
    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(startWith: LookupStartingView, navigationController: NavigationViewController, controllers: Controllers) {
        self.startingView = startWith
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        super.init()

        navigationController.dismissHandler = { [weak self] in
            guard let `self` = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        let controller = self.startingView == .manual ? self.manualController : self.scannerController
        self.navigationController.setViewControllers([controller], animated: animated)
    }

    private func lookupController(multiLookupEnabled: Bool, hasDarkBackground: Bool, userControllers: UserControllers) -> LookupViewController {
        let collectionKeys = Defaults.shared.selectedCollectionId.key.flatMap({ Set([$0]) }) ?? []
        let state = LookupState(multiLookupEnabled: multiLookupEnabled, hasDarkBackground: hasDarkBackground, collectionKeys: collectionKeys, libraryId: Defaults.shared.selectedLibrary)
        let handler = LookupActionHandler(dbStorage: userControllers.dbStorage, fileStorage: self.controllers.fileStorage, translatorsController: self.controllers.translatorsAndStylesController,
                                          schemaController: self.controllers.schemaController, dateParser: self.controllers.dateParser, remoteFileDownloader: userControllers.remoteFileDownloader)
        let viewModel = ViewModel(initialState: state, handler: handler)

        return LookupViewController(viewModel: viewModel, remoteDownloadObserver: userControllers.remoteFileDownloader.observable, remoteFileDownloader: userControllers.remoteFileDownloader,
                                    schemaController: self.controllers.schemaController)
    }

    private var scannerController: UIViewController {
        let state = ScannerState()
        let handler = ScannerActionHandler()
        let controller = ScannerViewController(viewModel: ViewModel(initialState: state, handler: handler))
        controller.coordinatorDelegate = self
        return controller
    }

    private var manualController: UIViewController {
        let state = ManualLookupState()
        let handler = ManualLookupActionHandler()
        let controller = ManualLookupViewController(viewModel: ViewModel(initialState: state, handler: handler))
        controller.coordinatorDelegate = self
        return controller
    }
}

extension LookupCoordinator: LookupCoordinatorDelegate {
    func lookupController(multiLookupEnabled: Bool, hasDarkBackground: Bool) -> LookupViewController? {
        guard let userControllers = self.controllers.userControllers else { return nil }
        return self.lookupController(multiLookupEnabled: multiLookupEnabled, hasDarkBackground: hasDarkBackground, userControllers: userControllers)
    }
}
