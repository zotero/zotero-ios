//
//  HtmlEpubCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 28.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

protocol HtmlEpubReaderCoordinatorDelegate: AnyObject {
    func show(error: HtmlEpubReaderState.Error)
}

final class HtmlEpubCoordinator: Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    weak var navigationController: UINavigationController?

    private let key: String
    private let library: Library
    private let url: URL
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(key: String, library: Library, url: URL, navigationController: NavigationViewController, controllers: Controllers) {
        self.key = key
        self.library = library
        self.url = url
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        navigationController.dismissHandler = {
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    deinit {
        DDLogInfo("HtmlEpubCoordinator: deinitialized")
    }

    func start(animated: Bool) {
        let username = Defaults.shared.username
        guard let dbStorage = self.controllers.userControllers?.dbStorage,
              let userId = self.controllers.sessionController.sessionData?.userId,
              !username.isEmpty,
              let parentNavigationController = self.parentCoordinator?.navigationController
        else { return }

        let settings = Defaults.shared.pdfSettings
        let handler = HtmlEpubReaderActionHandler(dbStorage: dbStorage, schemaController: controllers.schemaController)
        let state = HtmlEpubReaderState(url: url, key: key, library: library, userId: userId, username: username)
        let controller = HtmlEpubReaderViewController(
            viewModel: ViewModel(initialState: state, handler: handler),
            compactSize: UIDevice.current.isCompactWidth(size: parentNavigationController.view.frame.size)
        )
        controller.coordinatorDelegate = self

        self.navigationController?.setViewControllers([controller], animated: false)
    }
}

extension HtmlEpubCoordinator: HtmlEpubReaderCoordinatorDelegate {
    func show(error: HtmlEpubReaderState.Error) {
        let title: String
        let message: String

        switch error {
        case .cantAddAnnotations:
            title = L10n.error
            message = L10n.Errors.Pdf.cantAddAnnotations

        case .cantDeleteAnnotation:
            title = L10n.error
            message = L10n.Errors.Pdf.cantDeleteAnnotations

        case .cantUpdateAnnotation:
            title = L10n.error
            message = L10n.Errors.Pdf.cantUpdateAnnotation

        case .unknown:
            title = L10n.error
            message = L10n.Errors.unknown
        }

        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .default))
        self.navigationController?.present(controller, animated: true)
    }
}
