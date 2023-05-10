//
//  ConflictAlertQueueController.swift
//  Zotero
//
//  Created by Michal Rentka on 17.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

/// Controller used to present multiple alerts one after another.
class ConflictAlertQueueController {
    private weak var mainController: UIViewController?

    /// Number of alerts that need to be shown
    private var count: Int = 0
    private var currentIndex: Int = 0

    init(viewController: UIViewController) {
        self.mainController = viewController
    }

    func start(with handler: ConflictAlertQueueHandler) {
        self.count = handler.count
        self.currentIndex = 0
        self.present(nextAlert: handler.alertAction, completion: handler.completion)
    }

    private func present(nextAlert action: @escaping ConflictAlertQueueAction, completion: @escaping () -> Void) {
        guard let viewController = self.mainController?.topController, self.currentIndex < self.count else {
            completion()
            return
        }

        let controller = action(self.currentIndex, {
            self.present(nextAlert: action, completion: completion)
        })
        viewController.present(controller, animated: true, completion: nil)

        self.currentIndex += 1
    }
}
