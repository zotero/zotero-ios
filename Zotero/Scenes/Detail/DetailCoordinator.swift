//
//  DetailCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 12/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class DetailCoordinator: Coordinator {
    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    private let collection: Collection
    private let library: Library
    private unowned let controllers: Controllers
    unowned let navigationController: UINavigationController

    init(library: Library, collection: Collection, navigationController: UINavigationController, controllers: Controllers) {
        self.library = library
        self.collection = collection
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
    }

    func start(animated: Bool) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let controller = self.createItemsViewController(collection: self.collection, library: self.library, dbStorage: dbStorage)
        self.navigationController.setViewControllers([controller], animated: animated)
    }

    private func createItemsViewController(collection: Collection, library: Library, dbStorage: DbStorage) -> ItemsViewController {
        let type = self.fetchType(from: collection)
        let state = ItemsState(type: type, library: library, results: nil, sortType: .default, error: nil)
        let handler = ItemsActionHandler(dbStorage: dbStorage,
                                         fileStorage: self.controllers.fileStorage,
                                         schemaController: self.controllers.schemaController)
        return ItemsViewController(viewModel: ViewModel(initialState: state, handler: handler), controllers: self.controllers)
    }

    private func fetchType(from collection: Collection) -> ItemFetchType {
        switch collection.type {
        case .collection:
            return .collection(collection.key, collection.name)
        case .search:
            return .search(collection.key, collection.name)
        case .custom(let customType):
            switch customType {
            case .all:
                return .all
            case .publications:
                return .publications
            case .trash:
                return .trash
            }
        }
    }
}
