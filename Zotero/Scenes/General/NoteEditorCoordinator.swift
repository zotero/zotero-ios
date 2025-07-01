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

protocol NoteEditorCoordinatorDelegate: AnyObject {
    func show(url: URL)
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
    func show(error: Error, isClosing: Bool)
    func showItem(withPreview preview: AnnotationPreview, completion: @escaping (Bool) -> Void)
    func showItem(withCitation citation: CitationMetadata, completion: @escaping (Bool) -> Void)
    func showItemDetail(withCitation citation: CitationMetadata, completion: @escaping (Bool) -> Void)
}

final class NoteEditorCoordinator: NSObject, Coordinator {
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
    private let sessionIdentifier: String
    private unowned let controllers: Controllers

    var viewModel: ViewModel<NoteEditorActionHandler>? {
        (navigationController?.viewControllers.first as? NoteEditorViewController)?.viewModel
    }

    init(
        library: Library,
        kind: NoteEditorKind,
        text: String,
        tags: [Tag],
        parentTitleData: NoteEditorState.TitleData?,
        title: String?,
        navigationController: NavigationViewController,
        sessionIdentifier: String,
        controllers: Controllers
    ) {
        self.kind = kind
        initialText = text
        initialTags = tags
        self.parentTitleData = parentTitleData
        self.title = title
        self.library = library
        self.navigationController = navigationController
        self.sessionIdentifier = sessionIdentifier
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
        guard let dbStorage = controllers.userControllers?.dbStorage,
                let fileDownloader = controllers.userControllers?.fileDownloader,
                let openItemsController = controllers.userControllers?.openItemsController
        else { return }

        let state = NoteEditorState(
            kind: kind,
            library: library,
            parentTitleData: parentTitleData,
            text: initialText,
            tags: initialTags,
            openItemsCount: openItemsController.getItems(for: sessionIdentifier).count,
            title: title
        )
        let handler = NoteEditorActionHandler(dbStorage: dbStorage, fileStorage: controllers.fileStorage, schemaController: controllers.schemaController, attachmentDownloader: fileDownloader)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = NoteEditorViewController(
            viewModel: viewModel,
            htmlAttributedStringConverter: controllers.htmlAttributedStringConverter,
            dbStorage: dbStorage,
            fileStorage: controllers.fileStorage,
            uriConverter: controllers.uriConverter,
            openItemsController: openItemsController
        )
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

    func show(error: any Error, isClosing: Bool) {
        let controller = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
        if !isClosing {
            controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel))
        } else {
            controller.addAction(UIAlertAction(title: L10n.stay, style: .cancel))
            controller.addAction(UIAlertAction(title: L10n.closeWithoutSaving, style: .destructive, handler: { [weak self] _ in
                self?.navigationController?.dismiss(animated: true)
            }))
        }
        navigationController?.present(controller, animated: true)
    }

    func showItem(withPreview preview: AnnotationPreview, completion: @escaping (Bool) -> Void) {
        showItem(key: preview.parentKey, libraryId: preview.libraryId, page: preview.pageIndex, rects: preview.rects, completion: completion)
    }

    func showItem(withCitation citation: CitationMetadata, completion: @escaping (Bool) -> Void) {
        showItem(key: citation.attachmentKey, libraryId: citation.libraryId, page: citation.locator, rects: nil, completion: completion)
    }

    func showItemDetail(withCitation citation: CitationMetadata, completion: @escaping (Bool) -> Void) {
        guard let coordinator = (parentCoordinator as? DetailCoordinator) else {
            completion(false)
            return
        }
        coordinator.showItemDetail(for: .preview(key: citation.parentKey), libraryId: citation.libraryId, scrolledToKey: nil, animated: false)
        navigationController?.dismiss(animated: true) {
            completion(true)
        }
    }

    private func showItem(key: String, libraryId: LibraryIdentifier, page: Int, rects: [CGRect]?, completion: @escaping (Bool) -> Void) {
        guard let openItemsController = controllers.userControllers?.openItemsController else {
            completion(false)
            return
        }
        openItemsController.loadPresentation(
            for: key,
            libraryId: libraryId,
            page: page,
            preselectedAnnotationKey: nil,
            previewRects: rects
        ) { [weak self] presentation in
            guard let presentation, let self, let coordinator = parentCoordinator as? DetailCoordinator else {
                completion(false)
                return
            }
            coordinator.showItem(with: presentation)
            completion(true)
        }
    }
}

extension NoteEditorCoordinator: OpenItemsPresenter {
    func showItem(with presentation: ItemPresentation?) {
        (parentCoordinator as? OpenItemsPresenter)?.showItem(with: presentation)
    }
}
