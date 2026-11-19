//
//  ItemsFilterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol DownloadsFilterDelegate: AnyObject {
    func downloadsFilterDidChange(enabled: Bool)
}

final class ItemsFilterCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    weak var navigationController: UINavigationController?

    private let filters: [ItemsFilter]
    private unowned let mainCoordinatorDelegate: MainCoordinatorDelegate
    private weak var filtersDelegate: DownloadsFilterDelegate?

    init(
        filters: [ItemsFilter],
        filtersDelegate: DownloadsFilterDelegate,
        navigationController: NavigationViewController,
        mainCoordinatorDelegate: MainCoordinatorDelegate
    ) {
        self.filters = filters
        self.navigationController = navigationController
        self.mainCoordinatorDelegate = mainCoordinatorDelegate
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

        let downloadsFilterEnabled = filters.contains(where: { $0.isDownloadedFilesFilter })
        let controller = ItemsFilterViewController(
            downloadsFilterEnabled: downloadsFilterEnabled,
            tagFilterController: tagController,
            mainCoordinatorDelegate: mainCoordinatorDelegate
        )
        controller.delegate = filtersDelegate
        navigationController?.setViewControllers([controller], animated: animated)
    }
}
