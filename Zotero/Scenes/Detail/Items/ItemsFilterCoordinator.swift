//
//  ItemsFilterCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol ItemsFilterCoordinatorDelegate: AnyObject {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
}

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
    private unowned let controllers: Controllers
    private weak var filtersDelegate: BaseItemsViewController?
    private weak var sharedTagFilterViewModel: ViewModel<TagFilterActionHandler>?

    init(
        filters: [ItemsFilter],
        filtersDelegate: BaseItemsViewController,
        navigationController: NavigationViewController,
        controllers: Controllers,
        sharedTagFilterViewModel: ViewModel<TagFilterActionHandler>?
    ) {
        self.filters = filters
        self.navigationController = navigationController
        self.controllers = controllers
        self.filtersDelegate = filtersDelegate
        childCoordinators = []
        self.sharedTagFilterViewModel = sharedTagFilterViewModel

        super.init()

        navigationController.dismissHandler = { [weak self] in
            guard let self = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        let tagController: TagFilterViewController
        if let sharedTagFilterViewModel {
            tagController = TagFilterViewController(viewModel: sharedTagFilterViewModel)
        } else {
            guard let dbStorage = controllers.userControllers?.dbStorage else { return }
            let tags = filters.compactMap({ $0.tags }).first
            let state = TagFilterState(selectedTags: tags ?? [], showAutomatic: Defaults.shared.tagPickerShowAutomaticTags, displayAll: Defaults.shared.tagPickerDisplayAllTags)
            let handler = TagFilterActionHandler(dbStorage: dbStorage)
            tagController = TagFilterViewController(viewModel: ViewModel(initialState: state, handler: handler))
        }
        tagController.view.translatesAutoresizingMaskIntoConstraints = false
        tagController.delegate = filtersDelegate
        filtersDelegate?.tagFilterDelegate = tagController

        let downloadsFilterEnabled = filters.contains(where: { $0.isDownloadedFilesFilter })
        let controller = ItemsFilterViewController(downloadsFilterEnabled: downloadsFilterEnabled, tagFilterController: tagController)
        controller.delegate = filtersDelegate
        controller.coordinatorDelegate = self
        navigationController?.setViewControllers([controller], animated: animated)
    }
}

extension ItemsFilterCoordinator: ItemsFilterCoordinatorDelegate {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = controllers.userControllers?.dbStorage else { return }
        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: picked)
        navigationController?.pushViewController(controller, animated: true)
    }
}
