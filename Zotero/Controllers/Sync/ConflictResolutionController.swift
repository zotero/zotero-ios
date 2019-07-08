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

protocol ConflictReceiver {
    func resolve(conflict: Conflict, completed: @escaping (SyncController.Action?) -> Void)
}

protocol ConflictPresenter: UIViewController {
    func present(controller: UIAlertController)
}

extension ConflictPresenter {
    func present(controller: UIAlertController) {
        self.present(controller, animated: true, completion: nil)
    }
}

class ConflictResolutionController: ConflictReceiver {
    private let presenter: ConflictPresenter

    private var completionBlock: ((SyncController.Action?) -> Void)?

    init(presenter: ConflictPresenter) {
        self.presenter = presenter
    }

    func resolve(conflict: Conflict, completed: @escaping (SyncController.Action?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?._resolve(conflict: conflict, completed: completed)
        }
    }

    private func _resolve(conflict: Conflict, completed: @escaping (SyncController.Action?) -> Void) {
        self.completionBlock = completed
        let alertData = self.createAlert(for: conflict)

        let alert = UIAlertController(title: alertData.title, message: alertData.message, preferredStyle: .alert)
        alertData.actions.forEach { action in
            alert.addAction(action)
        }
        self.presenter.present(controller: alert)
    }

    private func createAlert(for conflict: Conflict) -> (title: String, message: String, actions: [UIAlertAction]) {
        switch conflict {
        case .groupRemoved(let groupId, let groupName):
            let actions = [UIAlertAction(title: "Remove", style: .destructive, handler: { [weak self] _ in
                               self?.finish(with: .deleteGroup(groupId))
                           }),
                           UIAlertAction(title: "Keep", style: .default, handler: { [weak self] _ in
                               self?.finish(with: .markGroupAsLocalOnly(groupId))
                           })]
            return ("Warning", "Group '\(groupName)' is no longer accessible. What would you like to do?", actions)

        case .groupWriteDenied(let groupId, let groupName):
            let actions = [UIAlertAction(title: "Revert to original", style: .cancel, handler: { [weak self] _ in
                               self?.finish(with: .revertLibraryToOriginal(.group(groupId)))
                           }),
                           UIAlertAction(title: "Keep changes", style: .default, handler: { [weak self] _ in
                               self?.finish(with: .markChangesAsResolved(.group(groupId)))
                           })]
            return ("Warning", "You can't write to group '\(groupName)' anymore. What would you like to do?", actions)
        }
    }

    private func finish(with action: SyncController.Action?) {
        self.completionBlock?(action)
        self.completionBlock = nil
    }
}
