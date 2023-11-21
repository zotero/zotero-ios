//
//  LookupCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 16.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

enum LookupStartingView {
    case scanner
    case manual(restoreLookupState: Bool)
}

protocol LookupCoordinatorDelegate: AnyObject {
    func lookupController(restoreLookupState: Bool, hasDarkBackground: Bool) -> LookupViewController?
}

final class LookupCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    weak var navigationController: UINavigationController?

    private let startingView: LookupStartingView
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(startWith: LookupStartingView, navigationController: NavigationViewController, controllers: Controllers) {
        self.startingView = startWith
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        super.init()

        navigationController.dismissHandler = {
            self.controllers.userControllers?.identifierLookupController.presenter = nil
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        let controller: UIViewController
        switch self.startingView {
        case .manual(let restoreLookupState):
            DDLogInfo("LookupCoordinator: show manual lookup \(restoreLookupState ? " with restored lookup state" : "")")
            controller = self.manualController(restoreLookupState: restoreLookupState)

        case .scanner:
            DDLogInfo("LookupCoordinator: show scanner lookup")
            controller = self.scannerController
        }
        self.navigationController?.setViewControllers([controller], animated: animated)
    }

    private func lookupController(restoreLookupState: Bool, hasDarkBackground: Bool, userControllers: UserControllers) -> LookupViewController {
        let collectionKeys = Defaults.shared.selectedCollectionId.key.flatMap({ Set([$0]) }) ?? []
        let state = LookupState(restoreLookupState: restoreLookupState, hasDarkBackground: hasDarkBackground, collectionKeys: collectionKeys, libraryId: Defaults.shared.selectedLibrary)
        let handler = LookupActionHandler(identifierLookupController: userControllers.identifierLookupController)
        let viewModel = ViewModel(initialState: state, handler: handler)

        return LookupViewController(
            viewModel: viewModel,
            remoteDownloadObserver: userControllers.remoteFileDownloader.observable,
            remoteFileDownloader: userControllers.remoteFileDownloader,
            schemaController: self.controllers.schemaController
        )
    }

    private var scannerController: UIViewController {
        let state = ScannerState()
        let handler = ScannerActionHandler()
        let controller = ScannerViewController(viewModel: ViewModel(initialState: state, handler: handler))
        controller.coordinatorDelegate = self
        controllers.userControllers?.identifierLookupController.presenter = controller
        return controller
    }

    private func manualController(restoreLookupState: Bool) -> UIViewController {
        let state = ManualLookupState(restoreLookupState: restoreLookupState)
        let handler = ManualLookupActionHandler()
        let controller = ManualLookupViewController(viewModel: ViewModel(initialState: state, handler: handler))
        controller.coordinatorDelegate = self
        controllers.userControllers?.identifierLookupController.presenter = controller
        return controller
    }
}

extension LookupCoordinator: LookupCoordinatorDelegate {
    func lookupController(restoreLookupState: Bool, hasDarkBackground: Bool) -> LookupViewController? {
        guard let userControllers = self.controllers.userControllers else { return nil }
        return self.lookupController(restoreLookupState: restoreLookupState, hasDarkBackground: hasDarkBackground, userControllers: userControllers)
    }
}
