//
//  NoteEditorCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SafariServices

import CocoaLumberjackSwift

typealias NoteEditorSaveResult = NoteEditorCoordinator.SaveResult
typealias NoteEditorSaveCallback = NoteEditorCoordinator.SaveCallback

protocol NoteEditorCoordinatorDelegate: AnyObject {
    func showWeb(url: URL)
    func show(url: URL)
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
}

final class NoteEditorCoordinator: NSObject, Coordinator {
    typealias SaveResult = Result<(String, String, [Tag]), Error>
    typealias SaveCallback = (SaveResult) -> Void

    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private var transitionDelegate: EmptyTransitioningDelegate?
    weak var navigationController: UINavigationController?

    private let kind: NoteEditorKind
    private let initialText: String
    private let initialTags: [Tag]
    private let title: NoteEditorState.TitleData?
    private let library: Library
    private let saveCallback: NoteEditorSaveCallback
    private unowned let controllers: Controllers

    init(
        library: Library,
        kind: NoteEditorKind,
        text: String,
        tags: [Tag],
        title: NoteEditorState.TitleData?,
        saveCallback: @escaping NoteEditorSaveCallback,
        navigationController: NavigationViewController,
        controllers: Controllers
    ) {
        self.kind = kind
        initialText = text
        initialTags = tags
        self.title = title
        self.library = library
        self.saveCallback = saveCallback
        self.navigationController = navigationController
        self.controllers = controllers
        childCoordinators = []

        super.init()

        navigationController.dismissHandler = { [weak self] in
            guard let self else { return }
            parentCoordinator?.childDidFinish(self)
        }
    }

    deinit {
        DDLogInfo("NoteEditorCoordinator: deinitialized")
    }

    func start(animated: Bool) {
        guard let dbStorage = controllers.userControllers?.dbStorage else { return }

        let state = NoteEditorState(kind: kind, library: library, title: title, text: initialText, tags: initialTags)
        let handler = NoteEditorActionHandler(dbStorage: dbStorage, schemaController: controllers.schemaController, saveCallback: saveCallback)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = NoteEditorViewController(viewModel: viewModel)
        controller.coordinatorDelegate = self
        navigationController?.setViewControllers([controller], animated: animated)
    }
}

extension NoteEditorCoordinator: NoteEditorCoordinatorDelegate {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = controllers.userControllers?.dbStorage, let navigationController else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: picked)

        navigationController.pushViewController(controller, animated: true)
    }

    func show(url: URL) {
        if let scheme = url.scheme, scheme != "http" && scheme != "https" {
            UIApplication.shared.open(url)
        } else {
            showWeb(url: url)
        }
    }

    func showWeb(url: URL) {
        guard let navigationController else { return }

        let controller = SFSafariViewController(url: url.withHttpSchemeIfMissing)
        controller.modalPresentationStyle = .fullScreen
        // Changes transition to normal modal transition instead of push from right.
        transitionDelegate = EmptyTransitioningDelegate()
        controller.transitioningDelegate = self.transitionDelegate
        transitionDelegate = nil
        navigationController.present(controller, animated: true, completion: nil)
    }
}
