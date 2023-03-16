//
//  CollectionEditingCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 12/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

protocol CollectionEditingCoordinatorDelegate: AnyObject {
    func showCollectionPicker(viewModel: ViewModel<CollectionEditActionHandler>)
    func showDeletedAlert(completion: @escaping (Bool) -> Void)
    func dismiss()
}

final class CollectionEditingCoordinator: Coordinator {
    weak var parentCoordinator: Coordinator?
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
    func showDeletedAlert(completion: @escaping (Bool) -> Void) {
        let controller = UIAlertController(title: "Deleted", message: "This collection has been deleted. Do you want to revert it?", preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: .default, handler: { _ in
            completion(false)
        }))
        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { _ in
            completion(true)
            self.navigationController.dismiss(animated: true, completion: nil)
        }))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showCollectionPicker(viewModel: ViewModel<CollectionEditActionHandler>) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let library = viewModel.state.library
        let selected = viewModel.state.parent?.identifier.key ?? library.name
        let excludedKeys: Set<String> = viewModel.state.key.flatMap({ [$0] }) ?? []

        let controller = self.createCollectionPickerViewController(library: library,
                                                                   selected: selected,
                                                                   excludedKeys: excludedKeys,
                                                                   dbStorage: dbStorage,
                                                                   collectionEditViewModel: viewModel)
        self.navigationController.pushViewController(controller, animated: true)
    }

    private func createCollectionPickerViewController(library: Library, selected: String, excludedKeys: Set<String>, dbStorage: DbStorage,
                                                      collectionEditViewModel: ViewModel<CollectionEditActionHandler>) -> UIViewController {
        let completion: (Collection) -> Void = { [weak collectionEditViewModel] collection in
            collectionEditViewModel?.process(action: .setParent(collection))
        }
        let state = CollectionsPickerState(library: library, excludedKeys: excludedKeys, selected: [selected])
        let handler = CollectionsPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        return CollectionsPickerViewController(mode: .single(title: L10n.Collections.pickerTitle, selected: completion), viewModel: viewModel)
    }

    func dismiss() {
        self.navigationController.dismiss(animated: true, completion: { [weak self] in
            guard let `self` = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        })
    }
}
