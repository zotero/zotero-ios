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
    case lookup
}

protocol ScannerToLookupCoordinatorDelegate: AnyObject {
    func showLookup(with codes: [String])
}

final class LookupCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
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
        guard let userControllers = self.controllers.userControllers else { return }
        let controller = self.startingView == .lookup ? self.lookupController(initial: nil, userControllers: userControllers) : self.scannerController
        self.navigationController.setViewControllers([controller], animated: animated)
    }

    private func lookupController(initial: String?, userControllers: UserControllers) -> UIViewController {
        let collectionKeys = Defaults.shared.selectedCollectionId.key.flatMap({ Set([$0]) }) ?? []
        let state = LookupState(initialText: initial, collectionKeys: collectionKeys, libraryId: Defaults.shared.selectedLibrary)
        let handler = LookupActionHandler(dbStorage: userControllers.dbStorage, translatorsController: self.controllers.translatorsAndStylesController,
                                          schemaController: self.controllers.schemaController, dateParser: self.controllers.dateParser, remoteFileDownloader: userControllers.remoteFileDownloader)
        let viewModel = ViewModel(initialState: state, handler: handler)

        return LookupViewController(viewModel: viewModel, remoteDownloadObserver: userControllers.remoteFileDownloader.observable, schemaController: self.controllers.schemaController)
    }

    private var scannerController: UIViewController {
        let state = ScannerState()
        let handler = ScannerActionHandler()
        let controller = ScannerViewController(viewModel: ViewModel(initialState: state, handler: handler))
        controller.coordinatorDelegate = self
        return controller
    }
}

extension LookupCoordinator: ScannerToLookupCoordinatorDelegate {
    func showLookup(with codes: [String]) {
        guard let userControllers = self.controllers.userControllers else { return }
        let controller = self.lookupController(initial: codes.joined(separator: ", "), userControllers: userControllers)
        self.navigationController.pushViewController(controller, animated: true)
    }
}
