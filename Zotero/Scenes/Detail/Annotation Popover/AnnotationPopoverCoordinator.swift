//
//  AnnotationPopoverCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 20.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol AnnotationPopoverAnnotationCoordinatorDelegate: class {
    func showEdit()
}

class AnnotationPopoverCoordinator: NSObject, Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    unowned let navigationController: UINavigationController
    private unowned let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    init(navigationController: UINavigationController, viewModel: ViewModel<PDFReaderActionHandler>) {
        self.navigationController = navigationController
        self.viewModel = viewModel
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        super.init()

        navigationController.delegate = self
    }

    func start(animated: Bool) {
        let controller = AnnotationViewController(viewModel: self.viewModel)
        controller.coordinatorDelegate = self
        self.navigationController.setViewControllers([controller], animated: animated)
    }
}

extension AnnotationPopoverCoordinator: AnnotationPopoverAnnotationCoordinatorDelegate {
    func showEdit() {
        let controller = UIViewController()
        controller.view.backgroundColor = .red
        self.navigationController.pushViewController(controller, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.navigationController.popViewController(animated: true)
        }
    }
}

extension AnnotationPopoverCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        let navbarHidden = viewController is AnnotationViewController
        navigationController.setNavigationBarHidden(true, animated: animated)
        navigationController.preferredContentSize = viewController.preferredContentSize
    }
}
