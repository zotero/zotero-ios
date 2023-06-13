//
//  ConflictReceiverAlertController.swift
//  Zotero
//
//  Created by Michal Rentka on 11.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

/// Container to weakly store receivers in an array.
private class ReceiverContainer {
    weak var receiver: ConflictViewControllerReceiver?

    init(receiver: ConflictViewControllerReceiver) {
        self.receiver = receiver
    }
}

/// Controller used to present alerts on loaded `ConflictViewControllerReceiver` controllers.
class ConflictReceiverAlertController {
    private weak var mainController: UISplitViewController?

    private var receiverQueue: [ReceiverContainer]

    private var activeReceivers: [ReceiverContainer] {
        guard let mainController = self.mainController else { return [] }
        return self.receivers(from: mainController.viewControllers)
    }

    init(viewController: UISplitViewController) {
        self.mainController = viewController
        self.receiverQueue = []
    }

    // MARK: - Resolution

    /// Performs handler actions on loaded conflict receiver view controllers.
    /// - parameter handler: Conflict handler
    func start(with handler: ConflictReceiverAlertHandler) {
        self.start(receiverAction: handler.receiverAction, completed: handler.completion)
    }

    // MARK: - Helpers

    /// Finds loaded receivers and calls given action on each one.
    /// - parameter action: Action to perform on each loaded receiver.
    /// - parameter completed: Completion block.
    private func start(receiverAction action: @escaping ConflictReceiverAlertAction, completed: @escaping () -> Void) {
        guard self.receiverQueue.isEmpty else {
            completed()
            return
        }

        self.receiverQueue = self.activeReceivers

        guard !self.receiverQueue.isEmpty else {
            completed()
            return
        }

        self.call(nextAction: action, completion: completed)
    }

    /// Calls action on next loaded receiver. Calls completion block if there are no more receivers.
    /// - parameter action: Action to call on receiver.
    /// - parameter completion: Completion block.
    private func call(nextAction action: @escaping ConflictReceiverAlertAction, completion: @escaping () -> Void) {
        var possibleReceiver: ConflictViewControllerReceiver?
        while !self.receiverQueue.isEmpty && possibleReceiver == nil {
            possibleReceiver = self.receiverQueue.removeFirst().receiver
        }

        guard let receiver = possibleReceiver else {
            completion()
            return
        }

        action(receiver, { [weak self] in
            guard let self = self else { return }
            if self.receiverQueue.isEmpty {
                completion()
            } else {
                self.call(nextAction: action, completion: completion)
            }
        })
    }

    /// Goes through all loaded view controllers, their children or presented controllers and creates a list of loaded receivers.
    /// - parameter viewControllers: View controllers from which the list is created.
    private func receivers(from viewControllers: [UIViewController]) -> [ReceiverContainer] {
        var receivers: [ReceiverContainer] = []
        for controller in viewControllers {
            // Call action on all presented controllers
            if let presented = controller.presentedViewController {
                receivers += self.receivers(from: [presented])
            }

            if let receiver = controller as? ConflictViewControllerReceiver {
                receivers.append(ReceiverContainer(receiver: receiver))
            }

            if let navigationController = controller as? UINavigationController {
                receivers += self.receivers(from: navigationController.viewControllers)
            }
        }
        return receivers
    }
}
