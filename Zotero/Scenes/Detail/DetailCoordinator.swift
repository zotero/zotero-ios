//
//  DetailCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 12/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import AVKit
import MobileCoreServices
import UIKit
import SafariServices
import SwiftUI

import CocoaLumberjackSwift
import RxSwift
import SwiftyGif

protocol DetailCoordinatorAttachmentProvider {
    func attachment(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Attachment, Library, UIView, CGRect?)?
}

protocol DetailItemsCoordinatorDelegate: AnyObject {
    func showCollectionsPicker(in library: Library, completed: @escaping (Set<String>) -> Void)
    func showItemDetail(for type: ItemDetailState.DetailType, library: Library, scrolledToKey childKey: String?, animated: Bool)
    func showAttachmentError(_ error: Error)
    func showNote(with text: String, tags: [Tag], title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, readOnly: Bool, save: @escaping (String, [Tag]) -> Void)
    func showAddActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem)
    func showSortActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem)
    func show(url: URL)
    func show(doi: String)
    func showFilters(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem)
    func showDeletionQuestion(count: Int, confirmAction: @escaping () -> Void, cancelAction: @escaping () -> Void)
    func showRemoveFromCollectionQuestion(count: Int, confirmAction: @escaping () -> Void)
    func showCitation(for itemIds: Set<String>, libraryId: LibraryIdentifier)
    func showCiteExport(for itemIds: Set<String>, libraryId: LibraryIdentifier)
    func showMissingStyleError()
    func showAttachment(key: String, parentKey: String?, libraryId: LibraryIdentifier)
    func show(error: ItemsError)
}

protocol DetailItemDetailCoordinatorDelegate: AnyObject {
    func showNote(with text: String, tags: [Tag], title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, readOnly: Bool, save: @escaping (String, [Tag]) -> Void)
    func showAttachmentPicker(save: @escaping ([URL]) -> Void)
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
    func showTypePicker(selected: String, picked: @escaping (String) -> Void)
    func show(url: URL)
    func show(doi: String)
    func showCreatorCreation(for itemType: String, saved: @escaping CreatorEditSaveAction)
    func showCreatorEditor(for creator: ItemDetailState.Creator, itemType: String, saved: @escaping CreatorEditSaveAction, deleted: @escaping CreatorEditDeleteAction)
    func showAttachmentError(_ error: Error)
    func showDeletedAlertForItem(completion: @escaping (Bool) -> Void)
    func show(error: ItemDetailError, viewModel: ViewModel<ItemDetailActionHandler>)
    func showDataReloaded(completion: @escaping () -> Void)
    func showAttachment(key: String, parentKey: String?, libraryId: LibraryIdentifier)
}

protocol DetailNoteEditorCoordinatorDelegate: AnyObject {
    func showWeb(url: URL)
    func show(url: URL)
    func pushTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
}

protocol DetailItemActionSheetCoordinatorDelegate: AnyObject {
    func showNoteCreation(title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, save: @escaping (String, [Tag]) -> Void)
    func showAttachmentPicker(save: @escaping ([URL]) -> Void)
    func showItemCreation(library: Library, collectionKey: String?)
}

protocol DetailCitationCoordinatorDelegate: AnyObject {
    func showLocatorPicker(for values: [SinglePickerModel], selected: String, picked: @escaping (String) -> Void)
    func showCitationPreview(errorMessage: String)
    func showMissingStyleError()
}

protocol ItemsTagFilterDelegate: AnyObject {
    var selectedTags: Set<String> { get }
    var delegate: TagFilterDelegate? { get set }
}

class EmptyTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {}

final class DetailCoordinator: Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private var transitionDelegate: EmptyTransitioningDelegate?
    weak var itemsTagFilterDelegate: ItemsTagFilterDelegate?

    let collection: Collection
    let library: Library
    let searchItemKeys: [String]?
    private unowned let controllers: Controllers
    unowned let navigationController: UINavigationController
    private let disposeBag: DisposeBag

    private weak var citationNavigationController: UINavigationController?

    init(library: Library, collection: Collection, searchItemKeys: [String]?, navigationController: UINavigationController, itemsTagFilterDelegate: ItemsTagFilterDelegate?, controllers: Controllers) {
        self.library = library
        self.collection = collection
        self.searchItemKeys = searchItemKeys
        self.navigationController = navigationController
        self.itemsTagFilterDelegate = itemsTagFilterDelegate
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()
    }

    deinit {
        DDLogInfo("DetailCoordinator: deinitialized")
    }

    func start(animated: Bool) {
        guard let userControllers = self.controllers.userControllers else { return }
        let controller = self.createItemsViewController(collection: self.collection, library: self.library, dbStorage: userControllers.dbStorage, fileDownloader: userControllers.fileDownloader,
                                                        syncScheduler: userControllers.syncScheduler, citationController: userControllers.citationController, fileCleanupController: userControllers.fileCleanupController, itemsTagFilterDelegate: self.itemsTagFilterDelegate)
        self.navigationController.setViewControllers([controller], animated: animated)
    }

    private func createItemsViewController(collection: Collection, library: Library, dbStorage: DbStorage, fileDownloader: AttachmentDownloader, syncScheduler: SynchronizationScheduler,
                                           citationController: CitationController, fileCleanupController: AttachmentFileCleanupController, itemsTagFilterDelegate: ItemsTagFilterDelegate?) -> ItemsViewController {
        let searchTerm = self.searchItemKeys?.joined(separator: " ")
        var filters: [ItemsState.Filter] = []
        if let tags = itemsTagFilterDelegate?.selectedTags, !tags.isEmpty {
            filters.append(.tags(tags))
        }
        let state = ItemsState(collection: collection, library: library, sortType: .default, searchTerm: searchTerm, filters: filters, error: nil)
        let handler = ItemsActionHandler(dbStorage: dbStorage,
                                         fileStorage: self.controllers.fileStorage,
                                         schemaController: self.controllers.schemaController,
                                         urlDetector: self.controllers.urlDetector,
                                         fileDownloader: fileDownloader,
                                         citationController: citationController,
                                         fileCleanupController: fileCleanupController,
                                         syncScheduler: syncScheduler)
        let controller = ItemsViewController(viewModel: ViewModel(initialState: state, handler: handler), controllers: self.controllers, coordinatorDelegate: self)
        itemsTagFilterDelegate?.delegate = controller
        return controller
    }

    func showAttachment(key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        guard let (attachment, library, sourceView, sourceRect) = self.navigationController.viewControllers.reversed()
                                                                      .compactMap({ ($0 as? DetailCoordinatorAttachmentProvider)?.attachment(for: key, parentKey: parentKey, libraryId: libraryId) })
                                                                      .first else { return }
        self.show(attachment: attachment, library: library, sourceView: sourceView, sourceRect: sourceRect)
    }

    private func show(attachment: Attachment, library: Library, sourceView: UIView, sourceRect: CGRect?) {
        switch attachment.type {
        case .url(let url):
            self.show(url: url)

        case .file(let filename, let contentType, _, _):
            let file = Files.attachmentFile(in: library.identifier, key: attachment.key, filename: filename, contentType: contentType)
            let url = file.createUrl()
            let rect = sourceRect ?? CGRect(x: (sourceView.frame.width / 3.0), y: (sourceView.frame.height * 2.0 / 3.0), width: (sourceView.frame.width / 3), height: (sourceView.frame.height / 3))

            switch contentType {
            case "application/pdf":
                self.showPdf(at: url, key: attachment.key, library: library)
            case "text/html":
                self.showWebView(for: url)
            case "text/plain":
                let text = try? String(contentsOf: url, encoding: .utf8)
                if let text = text {
                    self.show(text: text, title: filename)
                } else {
                    self.share(item: url, sourceView: .view(sourceView, rect))
                }
            case _ where contentType.contains("image"):
                let image = (contentType == "image/gif") ? (try? Data(contentsOf: url)).flatMap({ try? UIImage(gifData: $0) }) :
                                                             UIImage(contentsOfFile: url.path)
                if let image = image {
                    self.show(image: image, title: filename)
                } else {
                  self.share(item: url, sourceView: .view(sourceView, rect))
                }
            default:
                if AVURLAsset(url: url).isPlayable {
                    self.showVideo(for: url)
                } else {
                    self.share(item: file.createUrl(), sourceView: .view(sourceView, rect))
                }
            }
        }
    }

    private func show(text: String, title: String) {
        let controller = TextPreviewViewController(text: text, title: title)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.navigationController.present(navigationController, animated: true, completion: nil)
    }

    private func show(image: UIImage, title: String) {
        let controller = ImagePreviewViewController(image: image, title: title)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.navigationController.present(navigationController, animated: true, completion: nil)
    }

    private func showVideo(for url: URL) {
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        self.navigationController.present(controller, animated: true) {
            player.play()
        }
    }

    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        self.showTagPicker(libraryId: libraryId, selected: selected, userInterfaceStyle: nil, navigationController: self.navigationController, picked: picked)
    }

    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, userInterfaceStyle: UIUserInterfaceStyle?, navigationController: UINavigationController, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let tagController = TagPickerViewController(viewModel: viewModel, saveAction: picked)

        let controller = UINavigationController(rootViewController: tagController)
        if let userInterfaceStyle = userInterfaceStyle {
            controller.overrideUserInterfaceStyle = userInterfaceStyle
        }
        controller.isModalInPresentation = true
        controller.modalPresentationStyle = .formSheet
        navigationController.present(controller, animated: true, completion: nil)
    }

    private func showPdf(at url: URL, key: String, library: Library) {
        #if PDFENABLED
        let navigationController = NavigationViewController()
        navigationController.modalPresentationStyle = .fullScreen

        let coordinator = PDFCoordinator(key: key, library: library, url: url, page: nil, preselectedAnnotationKey: nil, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(navigationController, animated: true, completion: nil)
        #endif
    }

    private func showWebView(for url: URL) {
        let controller = WebViewController(url: url)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.navigationController.present(navigationController, animated: true, completion: nil)
    }

    func show(doi: String) {
        guard let url = URL(string: "https://doi.org/\(doi)") else { return }
        self.showWeb(url: url)
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

extension DetailCoordinator: DetailItemsCoordinatorDelegate {
    func showAddActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem) {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.popoverPresentationController?.barButtonItem = button

        controller.addAction(UIAlertAction(title: L10n.Items.lookup, style: .default, handler: { [weak self] _ in
            self?.showLookup(startWith: .manual)
        }))

        controller.addAction(UIAlertAction(title: L10n.Items.barcode, style: .default, handler: { [weak self] _ in
            self?.showLookup(startWith: .scanner)
        }))

        controller.addAction(UIAlertAction(title: L10n.Items.new, style: .default, handler: { [weak self, weak viewModel] _ in
            guard let `self` = self, let viewModel = viewModel else { return }
            let collectionKey: String?
            switch viewModel.state.collection.identifier {
            case .collection(let key):
                collectionKey = key
            case .search, .custom:
                collectionKey = nil
            }
            self.showItemCreation(library: viewModel.state.library, collectionKey: collectionKey)
        }))

        controller.addAction(UIAlertAction(title: L10n.Items.newNote, style: .default, handler: { [weak self, weak viewModel] _ in
            guard let `self` = self, let viewModel = viewModel else { return }
            let key = KeyGenerator.newKey
            self.showNoteCreation(title: nil, libraryId: viewModel.state.library.identifier, save: { [weak viewModel] text, tags in
                viewModel?.process(action: .saveNote(key, text, tags))
            })
        }))

        controller.addAction(UIAlertAction(title: L10n.Items.newFile, style: .default, handler: { [weak self, weak viewModel] _ in
            self?.showAttachmentPicker(save: { urls in
                viewModel?.process(action: .addAttachments(urls))
            })
        }))

        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))

        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showSortActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem) {
        let navigationController = UINavigationController()
        navigationController.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        navigationController.popoverPresentationController?.barButtonItem = button

        let sortByBinding = viewModel.binding(keyPath: \.sortType.field, action: { .setSortField($0) })

        let view = ItemSortingView(viewModel: viewModel, showPickerAction: { [weak self, weak navigationController] in
            guard let `self` = self, let navigationController = navigationController else { return }
            self.showSortTypePicker(sortBy: sortByBinding, in: navigationController)
        })

        let controller = DisappearActionHostingController(rootView: view)

        var size: CGSize?
        controller.willAppear = { [weak controller, weak navigationController] in
            guard let `controller` = controller else { return }
            let _size = size ?? controller.view.systemLayoutSizeFitting(CGSize(width: 400.0, height: .greatestFiniteMagnitude))
            size = _size
            controller.preferredContentSize = _size
            navigationController?.preferredContentSize = _size
        }

        if UIDevice.current.userInterfaceIdiom == .phone {
            controller.didLoad = { [weak self] viewController in
                guard let `self` = self else { return }
                let doneButton = UIBarButtonItem(title: L10n.done, style: .done, target: nil, action: nil)
                doneButton.rx.tap.subscribe({ [weak self] _ in
                    self?.navigationController.dismiss(animated: true)
                }).disposed(by: self.disposeBag)
                viewController.navigationItem.rightBarButtonItem = doneButton
            }
        }

        navigationController.setViewControllers([controller], animated: false)

        self.navigationController.present(navigationController, animated: true, completion: nil)
    }

    func showSortTypePicker(sortBy: Binding<ItemsSortType.Field>, in navigationController: UINavigationController) {
        let view = ItemSortTypePickerView(sortBy: sortBy,
                                          closeAction: { [weak navigationController] in
                                              navigationController?.popViewController(animated: true)
                                          })
        let controller = UIHostingController(rootView: view)
        controller.preferredContentSize = CGSize(width: 400, height: 600)
        navigationController.preferredContentSize = controller.preferredContentSize
        navigationController.pushViewController(controller, animated: true)
    }

    private func sortButtonTitles(for sortType: ItemsSortType) -> (field: String, order: String) {
        let sortOrderTitle = sortType.ascending ? L10n.Items.ascending : L10n.Items.descending
        return ("\(L10n.Items.sortBy): \(sortType.field.title)",
                "\(L10n.Items.sortOrder): \(sortOrderTitle)")
    }

    func showNote(with text: String, tags: [Tag], title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, readOnly: Bool, save: @escaping (String, [Tag]) -> Void) {
        let navigationController = NavigationViewController()
        navigationController.modalPresentationStyle = .fullScreen
        navigationController.isModalInPresentation = true

        let coordinator = NoteEditorCoordinator(text: text, tags: tags, title: title, libraryId: libraryId, readOnly: readOnly, save: save, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(navigationController, animated: true, completion: nil)
    }

    func showItemDetail(for type: ItemDetailState.DetailType, library: Library, scrolledToKey childKey: String?, animated: Bool) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage,
              let fileDownloader = self.controllers.userControllers?.fileDownloader,
              let fileCleanupController = self.controllers.userControllers?.fileCleanupController else { return }

        let state = ItemDetailState(type: type, library: library, preScrolledChildKey: childKey, userId: Defaults.shared.userId)
        let handler = ItemDetailActionHandler(apiClient: self.controllers.apiClient,
                                              fileStorage: self.controllers.fileStorage,
                                              dbStorage: dbStorage,
                                              schemaController: self.controllers.schemaController,
                                              dateParser: self.controllers.dateParser,
                                              urlDetector: self.controllers.urlDetector,
                                              fileDownloader: fileDownloader,
                                              fileCleanupController: fileCleanupController)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let controller = ItemDetailViewController(viewModel: viewModel, controllers: self.controllers)
        controller.coordinatorDelegate = self
        self.navigationController.pushViewController(controller, animated: animated)
    }

    func showCollectionsPicker(in library: Library, completed: @escaping (Set<String>) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = CollectionsPickerState(library: library, excludedKeys: [], selected: [])
        let handler = CollectionsPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = CollectionsPickerViewController(mode: .multiple(selected: completed), viewModel: viewModel)

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet
        self.navigationController.present(navigationController, animated: true, completion: nil)
    }

    func showFilters(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem) {
        let navigationController = NavigationViewController()
        navigationController.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        navigationController.popoverPresentationController?.barButtonItem = button

        let coordinator = ItemsFilterCoordinator(viewModel: viewModel, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(navigationController, animated: true, completion: nil)
    }

    func showDeletionQuestion(count: Int, confirmAction: @escaping () -> Void, cancelAction: @escaping () -> Void) {
        let question = count == 1 ? L10n.Items.deleteQuestion : L10n.Items.deleteMultipleQuestion
        self.ask(question: question, title: L10n.delete, isDestructive: true, confirm: confirmAction, cancel: cancelAction)
    }

    func showRemoveFromCollectionQuestion(count: Int, confirmAction: @escaping () -> Void) {
        let question = count == 1 ? L10n.Items.removeFromCollectionQuestion : L10n.Items.removeFromCollectionMultipleQuestion
        self.ask(question: question, title: L10n.Items.removeFromCollectionTitle, isDestructive: false, confirm: confirmAction)
    }

    private func ask(question: String, title: String, isDestructive: Bool, confirm: @escaping () -> Void, cancel: (() -> Void)? = nil) {
        let controller = UIAlertController(title: title, message: question, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: (isDestructive ? .destructive : .default), handler: { _ in
            confirm()
        }))
        controller.addAction(UIAlertAction(title: L10n.no, style: .cancel, handler: { _ in
            cancel?()
        }))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showCitation(for itemIds: Set<String>, libraryId: LibraryIdentifier) {
        guard let citationController = self.controllers.userControllers?.citationController else { return }

        let state = SingleCitationState(itemIds: itemIds, libraryId: libraryId, styleId: Defaults.shared.quickCopyStyleId,
                                        localeId: Defaults.shared.quickCopyLocaleId, exportAsHtml: Defaults.shared.quickCopyAsHtml)
        let handler = SingleCitationActionHandler(citationController: citationController)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let controller = SingleCitationViewController(viewModel: viewModel)
        controller.coordinatorDelegate = self
        let navigationController = UINavigationController(rootViewController: controller)
        self.citationNavigationController = navigationController
        let containerController = ContainerViewController(rootViewController: navigationController)
        self.navigationController.present(containerController, animated: true, completion: nil)
    }

    func showMissingStyleError() {
        let controller = UIAlertController(title: L10n.error, message: L10n.Errors.Citation.missingStyle, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        controller.addAction(UIAlertAction(title: L10n.Errors.Citation.openSettings, style: .default, handler: { [weak self] _ in
            self?.openExportSettings()
        }))

        if self.navigationController.presentedViewController == nil {
            self.navigationController.present(controller, animated: true, completion: nil)
        } else {
            self.navigationController.dismiss(animated: true) {
                self.navigationController.present(controller, animated: true, completion: nil)
            }
        }
    }

    private func openExportSettings() {
        let navigationController = NavigationViewController()
        let containerController = ContainerViewController(rootViewController: navigationController)
        let coordinator = SettingsCoordinator(startsWithExport: true, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(containerController, animated: true, completion: nil)
    }

    func showCiteExport(for itemIds: Set<String>, libraryId: LibraryIdentifier) {
        let navigationController = NavigationViewController()
        let containerController = ContainerViewController(rootViewController: navigationController)
        let coordinator = CitationBibliographyExportCoordinator(itemIds: itemIds, libraryId: libraryId, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(containerController, animated: true, completion: nil)
    }

    func show(error: ItemsError) {
        let message: String
        switch error {
        case .dataLoading:
            message = L10n.Errors.Items.loading
        case .deletion:
            message = L10n.Errors.Items.deletion
        case .deletionFromCollection:
            message = L10n.Errors.Items.deletionFromCollection
        case .collectionAssignment:
            message = L10n.Errors.Items.addToCollection
        case .itemMove:
            message = L10n.Errors.Items.moveItem
        case .noteSaving:
            message = L10n.Errors.Items.saveNote
        case .attachmentAdding(let type):
            switch type {
            case .couldNotSave:
                message = L10n.Errors.Items.addAttachment
            case .someFailed(let failed):
                message = L10n.Errors.Items.addSomeAttachments(failed.joined(separator: ","))
            }
        case .duplicationLoading:
            message = L10n.Errors.Items.loadDuplication
        }

        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    private func showLookup(startWith: LookupStartingView) {
        let navigationController = NavigationViewController()
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet

        let coordinator = LookupCoordinator(startWith: startWith, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(navigationController, animated: true, completion: nil)
    }
}

extension DetailCoordinator: DetailItemActionSheetCoordinatorDelegate {
    func showNoteCreation(title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, save: @escaping (String, [Tag]) -> Void) {
        self.showNote(with: "", tags: [], title: title, libraryId: libraryId, readOnly: false, save: save)
    }

    func showAttachmentPicker(save: @escaping ([URL]) -> Void) {
        let controller = DocumentPickerViewController(forOpeningContentTypes: [.pdf, .png, .jpeg], asCopy: true)
        controller.popoverPresentationController?.sourceView = self.navigationController.visibleViewController?.view
        controller.observable
                  .observe(on: MainScheduler.instance)
                  .subscribe(onNext: { urls in
                      save(urls)
                  })
                  .disposed(by: self.disposeBag)
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showItemCreation(library: Library, collectionKey: String?) {
        self.showTypePicker(selected: "") { [weak self] type in
            self?.showItemDetail(for: .creation(type: type, child: nil, collectionKey: collectionKey), library: library, scrolledToKey: nil, animated: true)
        }
    }
}

extension DetailCoordinator: DetailItemDetailCoordinatorDelegate {
    func showAttachmentError(_ error: Error) {
        let (message, additionalActions) = self.attachmentMessageAndActions(for: error)
        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        for action in additionalActions {
            controller.addAction(action)
        }
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    private func attachmentMessageAndActions(for error: Error) -> (String, [UIAlertAction]) {
        if let error = error as? AttachmentDownloader.Error {
            switch error {
            case .incompatibleAttachment:
                return (L10n.Errors.Attachments.incompatibleAttachment, [])
            case .zipDidntContainRequestedFile:
                return (L10n.Errors.Attachments.cantOpenAttachment, [])
            case .cantUnzipSnapshot:
                return (L10n.Errors.Attachments.cantUnzipSnapshot, [])
            }
        }

        if let responseError = error as? AFResponseError {
            switch responseError.error {
            case .responseValidationFailed(let reason):
                switch reason {
                case .unacceptableStatusCode(let code) where code == 404:
                    let webDavEnabled = self.controllers.userControllers?.webDavController.sessionStorage.isEnabled ?? false

                    let messageStart: String
                    if webDavEnabled {
                        messageStart = L10n.Errors.Attachments.missingWebdav
                    } else {
                        messageStart = L10n.Errors.Attachments.missingZotero
                    }

                    let message = "\(messageStart) \(L10n.Errors.Attachments.missingAdditional)"
                    let action = UIAlertAction(title: L10n.moreInformation, style: .default) { [weak self] _ in
                        self?.showWeb(url: URL(string: "https://www.zotero.org/support/kb/files_not_syncing")!)
                    }
                    return (message, [action])

                default: break
                }

            default: break
            }
        }

        return (L10n.Errors.Attachments.cantOpenAttachment, [])
    }

    func showCreatorCreation(for itemType: String, saved: @escaping CreatorEditSaveAction) {
        guard let schema = self.controllers.schemaController.creators(for: itemType)?.first(where: { $0.primary }),
              let localized = self.controllers.schemaController.localized(creator: schema.creatorType) else { return }
        let creator = ItemDetailState.Creator(type: schema.creatorType, primary: schema.primary, localizedType: localized, namePresentation: Defaults.shared.creatorNamePresentation)
        self._showCreatorEditor(for: creator, itemType: itemType, saved: saved, deleted: nil)
    }

    func showCreatorEditor(for creator: ItemDetailState.Creator, itemType: String, saved: @escaping CreatorEditSaveAction, deleted: @escaping CreatorEditDeleteAction) {
        self._showCreatorEditor(for: creator, itemType: itemType, saved: saved, deleted: deleted)
    }

    private func _showCreatorEditor(for creator: ItemDetailState.Creator, itemType: String, saved: @escaping CreatorEditSaveAction, deleted: CreatorEditDeleteAction?) {
        let navigationController = NavigationViewController()
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet

        let coordinator = CreatorEditCoordinator(creator: creator, itemType: itemType, saved: saved, deleted: deleted, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController.present(navigationController, animated: true, completion: nil)
    }

    func showTypePicker(selected: String, picked: @escaping (String) -> Void) {
        let viewModel = ItemTypePickerViewModelCreator.create(selected: selected, schemaController: self.controllers.schemaController)
        self.presentPicker(viewModel: viewModel, requiresSaveButton: false, saveAction: picked)
    }

    private func presentPicker(viewModel: ViewModel<SinglePickerActionHandler>, requiresSaveButton: Bool, saveAction: @escaping (String) -> Void) {
        let view = SinglePickerView(requiresSaveButton: requiresSaveButton, requiresCancelButton: true, saveAction: saveAction) { [weak self] completion in
            self?.navigationController.dismiss(animated: true, completion: {
                completion?()
            })
        }
        .environmentObject(viewModel)

        let controller = UINavigationController(rootViewController: UIHostingController(rootView: view))
        controller.isModalInPresentation = true
        controller.modalPresentationStyle = .formSheet
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func showDeletedAlertForItem(completion: @escaping (Bool) -> Void) {
        let popAction: () -> Void = {
            if self.navigationController.presentedViewController != nil {
                self.navigationController.dismiss(animated: true, completion: {
                    self.navigationController.popViewController(animated: true)
                })
            } else {
                self.navigationController.popViewController(animated: true)
            }
        }

        let controller = UIAlertController(title: L10n.ItemDetail.deletedTitle, message: L10n.ItemDetail.deletedMessage, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: .default, handler: { _ in
            completion(false)
        }))
        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { _ in
            completion(true)
            popAction()
        }))
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    func show(error: ItemDetailError, viewModel: ViewModel<ItemDetailActionHandler>) {
        let title: String
        let message: String
        var actions: [UIAlertAction] = []
        
        switch error {
        case .droppedFields(let fields):
            title = L10n.Errors.ItemDetail.droppedFieldsTitle
            message = self.droppedFieldsMessage(for: fields)
            actions.append(UIAlertAction(title: L10n.ok, style: .default, handler: { [weak viewModel] _ in
                viewModel?.process(action: .acceptPrompt)
            }))
            actions.append(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { [weak viewModel] _ in
                viewModel?.process(action: .cancelPrompt)
            }))

        case .cantCreateData:
            title = L10n.error
            message = L10n.Errors.ItemDetail.cantLoadData
            actions.append(UIAlertAction(title: L10n.ok, style: .cancel, handler: { [weak self] _ in
                self?.navigationController.popViewController(animated: true)
            }))

        case .cantAddAttachments(let error):
            switch error {
            case .someFailedCreation(let names), .couldNotMoveFromSource(let names):
                title = L10n.error
                message = L10n.Errors.ItemDetail.cantCreateAttachmentsWithNames(names.joined(separator: ", "))

            case .allFailedCreation:
                title = L10n.error
                message = L10n.Errors.ItemDetail.cantCreateAttachments
            }

        case .cantSaveNote:
            title = L10n.error
            message = L10n.Errors.ItemDetail.cantSaveNote

        case .cantStoreChanges:
            title = L10n.error
            message = L10n.Errors.ItemDetail.cantSaveChanges

        case .cantTrashItem:
            title = L10n.error
            message = L10n.Errors.ItemDetail.cantTrashItem

        case .typeNotSupported(let type):
            title = L10n.error
            message = L10n.Errors.ItemDetail.unsupportedType(type)

        case .cantSaveTags:
            title = L10n.error
            message = L10n.Errors.ItemDetail.cantSaveTags

        case .cantRemoveItem, .cantRemoveParent:
            title = L10n.error
            message = L10n.Errors.unknown
        }

        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach({ controller.addAction($0) })
        self.navigationController.present(controller, animated: true, completion: nil)
    }

    /// Message for `ItemDetailError.droppedFields` error.
    /// - parameter names: Names of fields with values that will disappear if type will change.
    /// - returns: Error message.
    private func droppedFieldsMessage(for names: [String]) -> String {
        let formattedNames = names.map({ "- \($0)\n" }).joined()
        return L10n.Errors.ItemDetail.droppedFieldsMessage(formattedNames)
    }

    func showDataReloaded(completion: @escaping () -> Void) {
        let controller = UIAlertController(title: L10n.warning, message: L10n.ItemDetail.dataReloaded, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: { _ in
            completion()
        }))
        self.navigationController.present(controller, animated: true, completion: nil)
    }
}

extension DetailCoordinator: DetailNoteEditorCoordinatorDelegate {
    func pushTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: picked)

        let navigationController = (self.navigationController.presentedViewController as? UINavigationController) ?? self.navigationController
        navigationController.pushViewController(controller, animated: true)
    }
}

extension DetailCoordinator: DetailCitationCoordinatorDelegate {
    func showLocatorPicker(for values: [SinglePickerModel], selected: String, picked: @escaping (String) -> Void) {
        let state = SinglePickerState(objects: values, selectedRow: selected)
        let viewModel = ViewModel(initialState: state, handler: SinglePickerActionHandler())

        let view = SinglePickerView(requiresSaveButton: false, requiresCancelButton: false, saveAction: picked) { completed in
            completed?()
            self.citationNavigationController?.popViewController(animated: true)
        }
        let controller = UIHostingController(rootView: view.environmentObject(viewModel))
        controller.preferredContentSize = CGSize(width: SingleCitationViewController.width, height: CGFloat(values.count * 44))
        self.citationNavigationController?.preferredContentSize = controller.preferredContentSize
        self.citationNavigationController?.pushViewController(controller, animated: true)
    }

    func showCitationPreview(errorMessage: String) {
        let controller = UIAlertController(title: L10n.error, message: errorMessage, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        self.citationNavigationController?.present(controller, animated: true, completion: nil)
    }
}
