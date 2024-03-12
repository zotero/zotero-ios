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
    func show(url: URL)
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
}

final class NoteEditorCoordinator: NSObject, Coordinator {
    typealias SaveResult = Result<(note: Note, isCreated: Bool), Error>
    typealias SaveCallback = (_ key: String?, _ result: SaveResult) -> Void

    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private var transitionDelegate: EmptyTransitioningDelegate?
    weak var navigationController: UINavigationController?

    private let kind: NoteEditorKind
    private let initialText: String
    private let initialTags: [Tag]
    private let parentTitleData: NoteEditorState.TitleData?
    private let title: String?
    private let library: Library
    private let saveCallback: NoteEditorSaveCallback
    private unowned let controllers: Controllers

    init(
        library: Library,
        kind: NoteEditorKind,
        text: String,
        tags: [Tag],
        parentTitleData: NoteEditorState.TitleData?,
        title: String?,
        saveCallback: @escaping NoteEditorSaveCallback,
        navigationController: NavigationViewController,
        controllers: Controllers
    ) {
        self.kind = kind
        initialText = text
        initialTags = tags
        self.parentTitleData = parentTitleData
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
        guard let dbStorage = controllers.userControllers?.dbStorage, let fileDownloader = controllers.userControllers?.fileDownloader else { return }
        let state = NoteEditorState(kind: kind, library: library, parentTitleData: parentTitleData, text: initialText, tags: initialTags, title: title)
        let handler = NoteEditorActionHandler(
            dbStorage: dbStorage,
            fileStorage: controllers.fileStorage,
            schemaController: controllers.schemaController,
            attachmentDownloader: fileDownloader,
            saveCallback: saveCallback
        )
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = NoteEditorViewController(viewModel: viewModel, htmlAttributedStringConverter: controllers.htmlAttributedStringConverter)
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
        guard let detailCoordinator = parentCoordinator as? DetailCoordinator else { return }
        detailCoordinator.show(url: url)
    }
}
