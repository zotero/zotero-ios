//
//  ItemsFilterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol FiltersDelegate: AnyObject {
    var currentLibrary: Library { get }

    func downloadsFilterDidChange(enabled: Bool)
    func tagSelectionDidChange(selected: Set<String>)
    func tagOptionsDidChange()
}

final class ItemsFilterCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    weak var navigationController: UINavigationController?

    private let filters: [ItemsFilter]
    private unowned let mainCoordinatorDelegate: MainCoordinatorDelegate
    private unowned let controllers: Controllers
    private weak var filtersDelegate: BaseItemsViewController?

    init(
        filters: [ItemsFilter],
        filtersDelegate: BaseItemsViewController,
        navigationController: NavigationViewController,
        mainCoordinatorDelegate: MainCoordinatorDelegate,
        controllers: Controllers
    ) {
        self.filters = filters
        self.navigationController = navigationController
        self.mainCoordinatorDelegate = mainCoordinatorDelegate
        self.controllers = controllers
        self.filtersDelegate = filtersDelegate
        childCoordinators = []

        super.init()

        navigationController.dismissHandler = { [weak self] in
            guard let self = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        guard let viewModel = mainCoordinatorDelegate.sharedTagFilterViewModel else { return }
        let tagController = TagFilterViewController(viewModel: viewModel, context: .filterScreen)
        tagController.view.translatesAutoresizingMaskIntoConstraints = false
        tagController.delegate = filtersDelegate
        filtersDelegate?.tagFilterDelegate = tagController

        let downloadsFilterEnabled = filters.contains(where: { $0.isDownloadedFilesFilter })
        let controller = ItemsFilterViewController(downloadsFilterEnabled: downloadsFilterEnabled, tagFilterController: tagController)
        controller.delegate = filtersDelegate
        navigationController?.setViewControllers([controller], animated: animated)
    }
}
