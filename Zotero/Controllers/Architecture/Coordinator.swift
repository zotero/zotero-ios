//
//  Coordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 10/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol Coordinator: class {
    var parentCoordinator: Coordinator? { get }
    var childCoordinators: [Coordinator] { get set }
    var navigationController: UINavigationController { get }

    func start(animated: Bool)
    func childDidFinish(_ child: Coordinator)
}

extension Coordinator {
    func childDidFinish(_ child: Coordinator) {
        if let index = self.childCoordinators.firstIndex(where: { $0 === child }) {
            self.childCoordinators.remove(at: index)
        }

        // Take navigation controller delegate back from child if needed
        if self.navigationController.delegate === child,
           let delegate = self as? UINavigationControllerDelegate {
            self.navigationController.delegate = delegate
        }
    }
}
