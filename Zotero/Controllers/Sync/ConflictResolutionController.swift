//
//  ConflictResolutionController.swift
//  Zotero
//
//  Created by Michal Rentka on 01/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum Conflict {
    case groupRemoved(Int, String)
    case groupWriteDenied(Int, String)
}

enum ConflictResolution {
    case deleteGroup(Int)
    case markGroupAsLocalOnly(Int)
    case revertLibraryToOriginal(LibraryIdentifier)
    case markChangesAsResolved(LibraryIdentifier)
}

protocol ConflictReceiver {
    func resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void)
}

protocol ConflictPresenter: UIViewController {
    func present(controller: UIAlertController)
}

enum DebugPermissionResponse {
    case allowed, cancelSync, skipAction
}

protocol DebugPermissionReceiver {
    func askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void)
}

extension ConflictPresenter {
    func present(controller: UIAlertController) {
        self.present(controller, animated: true, completion: nil)
    }
}

class ConflictResolutionController: ConflictReceiver, DebugPermissionReceiver {
    private let presenter: ConflictPresenter

    init(presenter: ConflictPresenter) {
        self.presenter = presenter
    }

    func askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?._askForPermission(message: message, completed: completed)
        }
    }

    private func _askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void) {
        let alert = UIAlertController(title: "Confirm action", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Allow", style: .default, handler: { _ in
            completed(.allowed)
        }))
        alert.addAction(UIAlertAction(title: "Skip", style: .default, handler: { _ in
            completed(.skipAction)
        }))
        alert.addAction(UIAlertAction(title: "Cancel sync", style: .destructive, handler: { _ in
            completed(.cancelSync)
        }))
        self.presenter.present(controller: alert)
    }

    func resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?._resolve(conflict: conflict, completed: completed)
        }
    }

    private func _resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) {
        let (title, message, actions) = self.createAlert(for: conflict, completed: completed)

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach { action in
            alert.addAction(action)
        }
        self.presenter.present(controller: alert)
    }

    private func createAlert(for conflict: Conflict,
                             completed: @escaping (ConflictResolution?) -> Void) -> (title: String, message: String, actions: [UIAlertAction]) {
        switch conflict {
        case .groupRemoved(let groupId, let groupName):
            let actions = [UIAlertAction(title: "Remove", style: .destructive, handler: { _ in
                               completed(.deleteGroup(groupId))
                           }),
                           UIAlertAction(title: "Keep", style: .default, handler: { _ in
                               completed(.markGroupAsLocalOnly(groupId))
                           })]
            return ("Warning",
                    "Group '\(groupName)' is no longer accessible. What would you like to do?",
                    actions)

        case .groupWriteDenied(let groupId, let groupName):
            let actions = [UIAlertAction(title: "Revert to original", style: .cancel, handler: { _ in
                               completed(.revertLibraryToOriginal(.group(groupId)))
                           }),
                           UIAlertAction(title: "Keep changes", style: .default, handler: { _ in
                               completed(.markChangesAsResolved(.group(groupId)))
                           })]
            return ("Warning",
                    "You can't write to group '\(groupName)' anymore. What would you like to do?",
                    actions)
        }
    }
}
