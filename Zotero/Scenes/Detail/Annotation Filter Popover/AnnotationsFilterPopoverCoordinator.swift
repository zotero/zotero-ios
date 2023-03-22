//
//  AnnotationsFilterPopoverCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 02.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol AnnotationsFilterPopoverToAnnotationsFilterCoordinatorDelegate: AnyObject {
    func showTagPicker(with tags: [Tag], selected: Set<String>, completed: @escaping (Set<String>) -> Void)
}

final class AnnotationsFilterPopoverCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]

    private let initialFilter: AnnotationsFilter?
    private let availableColors: [String]
    private let availableTags: [Tag]

    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers
    private let completionHandler: (AnnotationsFilter?) -> Void

    init(initialFilter: AnnotationsFilter?, availableColors: [String], availableTags: [Tag], navigationController: NavigationViewController, controllers: Controllers,
         completionHandler: @escaping (AnnotationsFilter?) -> Void) {
        self.initialFilter = initialFilter
        self.availableTags = availableTags
        self.availableColors = availableColors
        self.completionHandler = completionHandler
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []

        super.init()

        navigationController.delegate = self
        navigationController.dismissHandler = { [weak self] in
            guard let `self` = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        let state = AnnotationsFilterState(filter: self.initialFilter, availableColors: self.availableColors, availableTags: self.availableTags)
        let handler = AnnotationsFilterActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationsFilterViewController(viewModel: viewModel, completion: self.completionHandler)
        controller.coordinatorDelegate = self
        self.navigationController.setViewControllers([controller], animated: animated)
    }
}

extension AnnotationsFilterPopoverCoordinator: AnnotationsFilterPopoverToAnnotationsFilterCoordinatorDelegate {
    func showTagPicker(with tags: [Tag], selected: Set<String>, completed: @escaping (Set<String>) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let state = TagPickerState(libraryId: .custom(.myLibrary), selectedTags: selected, tags: tags)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let controller = TagPickerViewController(viewModel: ViewModel(initialState: state, handler: handler), saveAction: { picked in
            var tagNames: Set<String> = []
            for tag in picked {
                tagNames.insert(tag.name)
            }
            completed(tagNames)
        })
        controller.preferredContentSize = CGSize(width: 300, height: 500)
        self.navigationController.pushViewController(controller, animated: true)
    }
}

extension AnnotationsFilterPopoverCoordinator: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard viewController.preferredContentSize.width > 0 && viewController.preferredContentSize.height > 0 else { return }
        navigationController.preferredContentSize = viewController.preferredContentSize
    }
}
