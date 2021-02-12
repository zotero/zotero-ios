//
//  ConflictQueueController.swift
//  Zotero
//
//  Created by Michal Rentka on 11.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

typealias ConflictQueueAction = (ConflictViewControllerReceiver, @escaping () -> Void) -> Void

fileprivate class ReceiverContainer {
    weak var receiver: ConflictViewControllerReceiver?

    init(receiver: ConflictViewControllerReceiver) {
        self.receiver = receiver
    }
}

class ConflictQueueController {
    private weak var mainController: UISplitViewController?

    private var receiverQueue: [ReceiverContainer]

    private var activeReceivers: [ReceiverContainer] {
        guard let mainController = self.mainController else { return [] }
        return self.receivers(from: mainController.viewControllers)
    }

    init(mainController: UISplitViewController) {
        self.mainController = mainController
        self.receiverQueue = []
    }

    // MARK: - Resolution

    func resolveRemoteDeletion(collections: [String], items: [String], libraryId: LibraryIdentifier, completion: @escaping ([String], [String], [String], [String]) -> Void) {
        var toDeleteCollections: [String] = collections
        var toRestoreCollections: [String] = []
        var toDeleteItems: [String] = items
        var toRestoreItems: [String] = []

        self.callOnActiveReceivers { receiver, completion in
            if let key = receiver.shows(object: .collection, libraryId: libraryId), toDeleteCollections.contains(key) {
                // If receiver shows a collection, ask whether it can be deleted
                receiver.canDeleteObject { delete in
                    // If deletion was not allowed, move the key to restore array
                    if !delete {
                        toRestoreCollections.append(key)
                        if let idx = toDeleteCollections.firstIndex(of: key) {
                            toDeleteCollections.remove(at: idx)
                        }
                    }
                    completion()
                }
            } else if let key = receiver.shows(object: .item, libraryId: libraryId), toDeleteItems.contains(key) {
                // If receiver shows an item, ask whether it can be deleted
                receiver.canDeleteObject { delete in
                    // If deletion was not allowed, move the key to restore array
                    if !delete {
                        toRestoreItems.append(key)
                        if let idx = toDeleteItems.firstIndex(of: key) {
                            toDeleteItems.remove(at: idx)
                        }
                    }
                    completion()
                }
            } else {
                completion()
            }
        } completed: {
            completion(toDeleteCollections, toRestoreCollections, toDeleteItems, toRestoreItems)
        }
    }

    // MARK: - Helpers

    private func callOnActiveReceivers(action: @escaping ConflictQueueAction, completed: @escaping () -> Void) {
        guard self.receiverQueue.isEmpty else {
            completed()
            return
        }

        self.receiverQueue = self.activeReceivers

        guard !self.receiverQueue.isEmpty else {
            completed()
            return
        }

        self.callOnQueue(action: action, completion: completed)
    }

    private func callOnQueue(action: @escaping ConflictQueueAction, completion: @escaping () -> Void) {
        var possibleReceiver: ConflictViewControllerReceiver?
        while !self.receiverQueue.isEmpty && possibleReceiver == nil {
            possibleReceiver = self.receiverQueue.removeFirst().receiver
        }

        guard let receiver = possibleReceiver else {
            completion()
            return
        }

        action(receiver, { [weak self] in
            guard let `self` = self else { return }
            if self.receiverQueue.isEmpty {
                completion()
            } else {
                self.callOnQueue(action: action, completion: completion)
            }
        })
    }

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
