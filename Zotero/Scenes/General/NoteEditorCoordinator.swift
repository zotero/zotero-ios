//
//  NoteEditorCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SafariServices

protocol NoteEditorCoordinatorDelegate: AnyObject {
    func showWeb(url: URL)
    func show(url: URL)
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
}

final class NoteEditorCoordinator: NSObject, Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private var transitionDelegate: EmptyTransitioningDelegate?

    private let initialText: String
    private let initialTags: [Tag]
    private let title: NoteEditorState.TitleData?
    private let libraryId: LibraryIdentifier
    private let readOnly: Bool
    private let saveAction: (String, [Tag]) -> Void
    unowned let navigationController: UINavigationController
    private unowned let controllers: Controllers

    init(text: String, tags: [Tag], title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, readOnly: Bool, save: @escaping (String, [Tag]) -> Void, navigationController: NavigationViewController, controllers: Controllers) {
        self.initialText = text
        self.initialTags = tags
        self.title = title
        self.libraryId = libraryId
        self.readOnly = readOnly
        self.saveAction = save
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []

        super.init()

        navigationController.dismissHandler = { [weak self] in
            guard let self = self else { return }
            self.parentCoordinator?.childDidFinish(self)
        }
    }

    func start(animated: Bool) {
        let state = NoteEditorState(title: self.title, text: self.initialText, tags: self.initialTags, libraryId: self.libraryId, readOnly: self.readOnly)
        let handler = NoteEditorActionHandler(saveAction: self.saveAction)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = NoteEditorViewController(viewModel: viewModel)
        controller.coordinatorDelegate = self
        self.navigationController.setViewControllers([controller], animated: animated)
    }
}

extension NoteEditorCoordinator: NoteEditorCoordinatorDelegate {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: picked)

        self.navigationController.pushViewController(controller, animated: true)
    }

    func show(url: URL) {
        if let scheme = url.scheme, scheme != "http" && scheme != "https" {
            UIApplication.shared.open(url)
        } else {
            self.showWeb(url: url)
        }
    }

    func showWeb(url: URL) {
        let controller = SFSafariViewController(url: url.withHttpSchemeIfMissing)
        controller.modalPresentationStyle = .fullScreen
        // Changes transition to normal modal transition instead of push from right.
        self.transitionDelegate = EmptyTransitioningDelegate()
        controller.transitioningDelegate = self.transitionDelegate
        self.transitionDelegate = nil
        self.navigationController.present(controller, animated: true, completion: nil)
    }
}
