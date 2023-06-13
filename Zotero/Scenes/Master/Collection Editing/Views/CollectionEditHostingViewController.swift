//
//  CollectionEditHostingViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 09.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

/// Container created for receiving Conflict updates from `ConflictViewControllerReceiver`.
class CollectionEditHostingViewController<Content>: UIHostingController<Content> where Content: View {
    private unowned let viewModel: ViewModel<CollectionEditActionHandler>

    weak var coordinatorDelegate: CollectionEditingCoordinatorDelegate?

    init(viewModel: ViewModel<CollectionEditActionHandler>, rootView: Content) {
        self.viewModel = viewModel
        super.init(rootView: rootView)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension CollectionEditHostingViewController: ConflictViewControllerReceiver {
    func shows(object: SyncObject, libraryId: LibraryIdentifier) -> String? {
        guard object == .collection && libraryId == self.viewModel.state.library.identifier else { return nil }
        return self.viewModel.state.key
    }

    func canDeleteObject(completion: @escaping (Bool) -> Void) {
        self.coordinatorDelegate?.showDeletedAlert(completion: completion)
    }
}
