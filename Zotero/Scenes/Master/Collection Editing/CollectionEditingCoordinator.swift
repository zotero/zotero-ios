//
//  CollectionEditingCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 12/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

protocol CollectionEditingCoordinatorDelegate: class {
    func showCollectionPicker(viewModel: ViewModel<CollectionEditActionHandler>)
    func showDeletedAlertAndClose()
    func dismiss()
}

final class CollectionEditingCoordinator: Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    private let library: Library
    private let data: CollectionStateEditingData
    private unowned let controllers: Controllers
    unowned let navigationController: UINavigationController

    init(data: CollectionStateEditingData, library: Library, navigationController: UINavigationController, controllers: Controllers) {
        self.data = data
        self.library = library
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
    }

    func start(animated: Bool) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let controller = self.createEditViewController(dbStorage: dbStorage)
        self.navigationController.setViewControllers([controller], animated: false)
    }

    private func createEditViewController(dbStorage: DbStorage) -> UIViewController {
        let state = CollectionEditState(library: self.library, key: data.key, name: data.name, parent: data.parent)
        let handler = CollectionEditActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        var view = CollectionEditView()
        view.coordinatorDelegate = self
        let controller = CollectionEditHostingViewController(viewModel: viewModel, rootView: view.environmentObject(viewModel))
        controller.coordinatorDelegate = self
        return controller
    }
}

extension CollectionEditingCoordinator: CollectionEditingCoordinatorDelegate {
    func showDeletedAlertAndClose() {
        let presentingController = self.navigationController.presentingViewController

        self.navigationController.dismiss(animated: true) {
            let controller = UIAlertController(title: "Deleted", message: "This collection has been deleted.", preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
            presentingController?.present(controller, animated: true, completion: nil)
        }
    }

    func showCollectionPicker(viewModel: ViewModel<CollectionEditActionHandler>) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let library = viewModel.state.library
        let selected = viewModel.state.parent?.key ?? library.name
        let excludedKeys: Set<String> = viewModel.state.key.flatMap({ [$0] }) ?? []

        let controller = self.createCollectionPickerViewController(library: library,
                                                                   selected: selected,
                                                                   excludedKeys: excludedKeys,
                                                                   dbStorage: dbStorage,
                                                                   collectionEditViewModel: viewModel)
        self.navigationController.pushViewController(controller, animated: true)
    }

    private func createCollectionPickerViewController(library: Library, selected: String,
                                                      excludedKeys: Set<String>, dbStorage: DbStorage,
                                                      collectionEditViewModel: ViewModel<CollectionEditActionHandler>) -> UIViewController {
        let state = CollectionPickerState(library: library, excludedKeys: excludedKeys, selected: [selected])
        let handler = CollectionPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)

        // SWIFTUI BUG: - We need to call loadData here, because when we do so in `onAppear` in SwiftUI `View` we'll crash when data change
        // instantly in that function. If we delay it, the user will see unwanted animation of data on screen. If we call it here, data
        // is available immediately.
        viewModel.process(action: .loadData)

        let view = CollectionPickerView(saveAction: { [weak collectionEditViewModel] parent in
            collectionEditViewModel?.process(action: .setParent(parent))
        })
        return UIHostingController(rootView: view.environmentObject(viewModel))
    }

    func dismiss() {
        self.navigationController.dismiss(animated: true, completion: { [weak self] in
            guard let `self` = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        })
    }
}
