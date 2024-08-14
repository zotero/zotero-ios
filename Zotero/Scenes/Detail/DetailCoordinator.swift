//
//  DetailCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 12/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import AVFoundation
import AVKit
import MobileCoreServices
import UIKit
import SafariServices
import SwiftUI

import Alamofire
import CocoaLumberjackSwift
import RealmSwift
import RxSwift
import SwiftyGif

protocol DetailCoordinatorAttachmentProvider {
    func attachment(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Attachment, UIView, CGRect?)?
}

protocol DetailMissingStyleErrorDelegate: AnyObject {
    func showMissingStyleError(using presenter: UINavigationController?)
}

protocol DetailCitationCoordinatorDelegate: DetailMissingStyleErrorDelegate {
    func showCitationPreviewError(using presenter: UINavigationController, errorMessage: String)
}

protocol DetailCopyBibliographyCoordinatorDelegate: DetailMissingStyleErrorDelegate { }

protocol DetailItemsCoordinatorDelegate: AnyObject {
    var displayTitle: String { get }
    func showCollectionsPicker(in library: Library, completed: @escaping (Set<String>) -> Void)
    func showItemDetail(for type: ItemDetailState.DetailType, libraryId: LibraryIdentifier, scrolledToKey childKey: String?, animated: Bool)
    func showAttachmentError(_ error: Error)
    func showAddActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem)
    func showSortActions(sortType: ItemsSortType, button: UIBarButtonItem, changed: @escaping (ItemsSortType) -> Void)
    func show(url: URL)
    func show(doi: String)
    func showFilters(filters: [ItemsFilter], filtersDelegate: BaseItemsViewController, button: UIBarButtonItem)
    func showDeletionQuestion(count: Int, confirmAction: @escaping () -> Void, cancelAction: @escaping () -> Void)
    func showRemoveFromCollectionQuestion(count: Int, confirmAction: @escaping () -> Void)
    func showCitation(using presenter: UIViewController?, for itemIds: Set<String>, libraryId: LibraryIdentifier, delegate: DetailCitationCoordinatorDelegate?)
    func copyBibliography(using presenter: UIViewController, for itemIds: Set<String>, libraryId: LibraryIdentifier, delegate: DetailCopyBibliographyCoordinatorDelegate?)
    func showCiteExport(for itemIds: Set<String>, libraryId: LibraryIdentifier)
    func showAttachment(key: String, parentKey: String?, libraryId: LibraryIdentifier)
    func show(error: ItemsError)
    func showLookup()
}

protocol DetailItemDetailCoordinatorDelegate: AnyObject {
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
    func showNote(library: Library, kind: NoteEditorKind, text: String, tags: [Tag], parentTitleData: NoteEditorState.TitleData?, title: String?, saveCallback: ((Note) -> Void)?)
}

protocol ItemsTagFilterDelegate: AnyObject {
    var delegate: FiltersDelegate? { get set }

    func clearSelection()
    func itemsDidChange(filters: [ItemsFilter], collectionId: CollectionIdentifier, libraryId: LibraryIdentifier)
}

class EmptyTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {}

final class DetailCoordinator: Coordinator {
    weak var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private var transitionDelegate: EmptyTransitioningDelegate?
    weak var itemsTagFilterDelegate: ItemsTagFilterDelegate?
    weak var navigationController: UINavigationController?
    private var tmpAudioDelegate: AVPlayerDelegate?

    let collection: Collection
    let libraryId: LibraryIdentifier
    let searchItemKeys: [String]?
    private unowned let controllers: Controllers
    private let disposeBag: DisposeBag

    init(
        libraryId: LibraryIdentifier,
        collection: Collection,
        searchItemKeys: [String]?,
        navigationController: UINavigationController,
        itemsTagFilterDelegate: ItemsTagFilterDelegate?,
        controllers: Controllers
    ) {
        self.libraryId = libraryId
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
        guard let userControllers = controllers.userControllers else { return }
        DDLogInfo("DetailCoordinator: show items for \(collection.id); \(libraryId)")

        let controller: UIViewController
        switch collection.identifier {
        case .custom(let type) where type == .trash:
            controller = createTrashViewController(libraryId: libraryId, itemsTagFilterDelegate: itemsTagFilterDelegate, controllers: controllers)

        case .collection, .search, .custom:
            controller = createItemsViewController(
                collection: collection,
                libraryId: libraryId,
                searchItemKeys: searchItemKeys,
                itemsTagFilterDelegate: itemsTagFilterDelegate,
                controllers: controllers
            )
        }

        navigationController?.setViewControllers([controller], animated: animated)

        func createTrashViewController(libraryId: LibraryIdentifier, itemsTagFilterDelegate: ItemsTagFilterDelegate?, controllers: Controllers) -> TrashViewController {
            itemsTagFilterDelegate?.clearSelection()

            let searchTerm = searchItemKeys?.joined(separator: " ")
            let sortType = Defaults.shared.itemsSortType
            let downloadBatchData = ItemsState.DownloadBatchData(batchData: userControllers.fileDownloader.batchData)
            let state = TrashState(libraryId: libraryId, sortType: sortType, searchTerm: searchTerm, filters: [], downloadBatchData: downloadBatchData)
            let handler = TrashActionHandler(
                dbStorage: userControllers.dbStorage,
                schemaController: controllers.schemaController,
                fileStorage: controllers.fileStorage,
                fileDownloader: userControllers.fileDownloader,
                urlDetector: controllers.urlDetector,
                htmlAttributedStringConverter: controllers.htmlAttributedStringConverter,
                fileCleanupController: userControllers.fileCleanupController
            )
            let controller = TrashViewController(viewModel: ViewModel(initialState: state, handler: handler), controllers: controllers, coordinatorDelegate: self)
            controller.tagFilterDelegate = itemsTagFilterDelegate
            itemsTagFilterDelegate?.delegate = controller
            return controller
        }

        func createItemsViewController(
            collection: Collection,
            libraryId: LibraryIdentifier,
            searchItemKeys: [String]?,
            itemsTagFilterDelegate: ItemsTagFilterDelegate?,
            controllers: Controllers
        ) -> ItemsViewController {
            itemsTagFilterDelegate?.clearSelection()

            let searchTerm = searchItemKeys?.joined(separator: " ")
            let downloadBatchData = ItemsState.DownloadBatchData(batchData: userControllers.fileDownloader.batchData)
            let remoteDownloadBatchData = ItemsState.DownloadBatchData(batchData: userControllers.remoteFileDownloader.batchData)
            let identifierLookupBatchData = ItemsState.IdentifierLookupBatchData(batchData: userControllers.identifierLookupController.batchData)
            let sortType = Defaults.shared.itemsSortType
            let state = ItemsState(
                collection: collection,
                libraryId: libraryId,
                sortType: sortType,
                searchTerm: searchTerm,
                filters: [],
                downloadBatchData: downloadBatchData,
                remoteDownloadBatchData: remoteDownloadBatchData,
                identifierLookupBatchData: identifierLookupBatchData,
                error: nil
            )
            let handler = ItemsActionHandler(
                dbStorage: userControllers.dbStorage,
                fileStorage: controllers.fileStorage,
                schemaController: controllers.schemaController,
                urlDetector: controllers.urlDetector,
                fileDownloader: userControllers.fileDownloader,
                fileCleanupController: userControllers.fileCleanupController,
                syncScheduler: userControllers.syncScheduler,
                htmlAttributedStringConverter: controllers.htmlAttributedStringConverter
            )
            let controller = ItemsViewController(viewModel: ViewModel(initialState: state, handler: handler), controllers: controllers, coordinatorDelegate: self)
            controller.tagFilterDelegate = itemsTagFilterDelegate
            itemsTagFilterDelegate?.delegate = controller
            return controller
        }
    }

    func showAttachment(key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        guard let (attachment, sourceView, sourceRect) = self.navigationController?.viewControllers.reversed()
            .compactMap({ ($0 as? DetailCoordinatorAttachmentProvider)?.attachment(for: key, parentKey: parentKey, libraryId: libraryId) })
            .first
        else { return }
        self.show(attachment: attachment, parentKey: parentKey, libraryId: libraryId, sourceView: sourceView, sourceRect: sourceRect)
    }

    private func show(attachment: Attachment, parentKey: String?, libraryId: LibraryIdentifier, sourceView: UIView, sourceRect: CGRect?) {
        switch attachment.type {
        case .url(let url):
            show(url: url)

        case .file(let filename, let contentType, _, _, _):
            let file = Files.attachmentFile(in: libraryId, key: attachment.key, filename: filename, contentType: contentType)
            let url = file.createUrl()
            let rect = sourceRect ?? CGRect(x: (sourceView.frame.width / 3.0), y: (sourceView.frame.height * 2.0 / 3.0), width: (sourceView.frame.width / 3), height: (sourceView.frame.height / 3))

            switch contentType {
            case "application/pdf":
                DDLogInfo("DetailCoordinator: show PDF \(attachment.key)")
                showPdf(at: url, key: attachment.key, parentKey: parentKey, libraryId: libraryId)

            case "text/html", "application/epub+zip":
                DDLogInfo("DetailCoordinator: show HTML / EPUB \(attachment.key)")
                showHtmlEpubReader(for: url, key: attachment.key, parentKey: parentKey, libraryId: libraryId)

            case "text/plain":
                let text = try? String(contentsOf: url, encoding: .utf8)
                if let text = text {
                    DDLogInfo("DetailCoordinator: show plain text \(attachment.key)")
                    show(text: text, title: filename)
                } else {
                    DDLogInfo("DetailCoordinator: share plain text \(attachment.key)")
                    share(item: url, sourceView: .view(sourceView, rect))
                }

            case _ where contentType.contains("image"):
                let image = (contentType == "image/gif") ? (try? Data(contentsOf: url)).flatMap({ try? UIImage(gifData: $0) }) : UIImage(contentsOfFile: url.path)
                if let image = image {
                    DDLogInfo("DetailCoordinator: show image \(attachment.key)")
                    show(image: image, title: filename)
                } else {
                    DDLogInfo("DetailCoordinator: share image \(attachment.key)")
                    share(item: url, sourceView: .view(sourceView, rect))
                }

            default:
                if AVURLAsset(url: url).isPlayable {
                    DDLogInfo("DetailCoordinator: show video \(attachment.key)")
                    showVideo(for: url)
                } else {
                    DDLogInfo("DetailCoordinator: share attachment \(attachment.key)")
                    share(item: file.createUrl(), sourceView: .view(sourceView, rect))
                }
            }
        }
    }

    private func show(text: String, title: String) {
        let controller = TextPreviewViewController(text: text, title: title)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    private func show(image: UIImage, title: String) {
        let controller = ImagePreviewViewController(image: image, title: title)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    private func showVideo(for url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let error {
            DDLogError("DetailCoordinator: can't set audio session - \(error)")
        }

        let delegate = AVPlayerDelegate { [weak self] in
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            self?.tmpAudioDelegate = nil
        }
        tmpAudioDelegate = delegate

        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.delegate = delegate
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.player = player
        navigationController?.present(controller, animated: true) {
            player.play()
        }
    }

    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        self.showTagPicker(libraryId: libraryId, selected: selected, userInterfaceStyle: nil, navigationController: self.navigationController, picked: picked)
    }

    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, userInterfaceStyle: UIUserInterfaceStyle?, navigationController: UINavigationController?, picked: @escaping ([Tag]) -> Void) {
        guard let navigationController, let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        DDLogInfo("DetailCoordinator: show tag picker for \(libraryId)")

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

    func createPDFController(
        key: String,
        parentKey: String?,
        libraryId: LibraryIdentifier,
        url: URL,
        page: Int? = nil,
        preselectedAnnotationKey: String? = nil,
        previewRects: [CGRect]? = nil
    ) -> NavigationViewController {
        let navigationController = NavigationViewController()
        navigationController.modalPresentationStyle = .fullScreen

        let coordinator = PDFCoordinator(
            key: key,
            parentKey: parentKey,
            libraryId: libraryId,
            url: url,
            page: page,
            preselectedAnnotationKey: preselectedAnnotationKey,
            previewRects: previewRects,
            navigationController: navigationController,
            controllers: controllers
        )
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        return navigationController
    }

    func createHtmlEpubController(key: String, parentKey: String?, libraryId: LibraryIdentifier, url: URL) -> NavigationViewController {
        let navigationController = NavigationViewController()
        navigationController.modalPresentationStyle = .fullScreen
        let coordinator = HtmlEpubCoordinator(key: key, parentKey: parentKey, libraryId: libraryId, url: url, navigationController: navigationController, controllers: controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)
        return navigationController
    }

    private func showPdf(at url: URL, key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        let controller = createPDFController(key: key, parentKey: parentKey, libraryId: libraryId, url: url)
        navigationController?.present(controller, animated: true, completion: nil)
    }

    private func showHtmlEpubReader(for url: URL, key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        let controller = createHtmlEpubController(key: key, parentKey: parentKey, libraryId: libraryId, url: url)
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    private func showWebView(for url: URL) {
        guard let currentNavigationController = self.navigationController else { return }
        let controller = WebViewController(url: url)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        currentNavigationController.present(navigationController, animated: true, completion: nil)
    }

    func show(doi: String) {
        guard let url = URL(string: "https://doi.org/\(doi)") else { return }
        DDLogInfo("DetailCoordinator: show DOI \(doi)")
        self.showWeb(url: url)
    }

    func show(url: URL) {
        DDLogInfo("DetailCoordinator: show url \(url.absoluteString)")

        if !Defaults.shared.openLinksInExternalBrowser || !controllers.urlDetector.isUrl(string: url.absoluteString) {
            showWeb(url: url)
            return
        }

        var fixedUrl = url
        if url.scheme == nil {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            fixedUrl = components?.url ?? url
        }
        UIApplication.shared.open(fixedUrl)
    }

    private func showWeb(url: URL) {
        let controller = SFSafariViewController(url: url.withHttpSchemeIfMissing)
        controller.modalPresentationStyle = .fullScreen
        // Changes transition to normal modal transition instead of push from right.
        self.transitionDelegate = EmptyTransitioningDelegate()
        controller.transitioningDelegate = self.transitionDelegate
        self.transitionDelegate = nil
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    private func showSettings(using presenter: UINavigationController, initialScreen: SettingsCoordinator.InitialScreen? = nil) {
        let navigationController = NavigationViewController()
        let containerController = ContainerViewController(rootViewController: navigationController)
        let coordinator = SettingsCoordinator(navigationController: navigationController, controllers: controllers, initialScreen: initialScreen)
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)
        presenter.present(containerController, animated: true)
    }
}

extension DetailCoordinator: DetailItemsCoordinatorDelegate {
    var displayTitle: String {
            collection.name
        }

    func showAddActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem) {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.popoverPresentationController?.barButtonItem = button

        if viewModel.state.library.metadataAndFilesEditable {
            controller.addAction(UIAlertAction(title: L10n.Items.lookup, style: .default, handler: { [weak self] _ in
                self?.showLookup(startWith: .manual(restoreLookupState: false))
            }))

            controller.addAction(UIAlertAction(title: L10n.Items.barcode, style: .default, handler: { [weak self] _ in
                self?.showLookup(startWith: .scanner)
            }))
        }

        controller.addAction(UIAlertAction(title: L10n.Items.new, style: .default, handler: { [weak self, weak viewModel] _ in
            guard let self, let viewModel else { return }
            let collectionsSource: ItemDetailState.DetailType.CollectionsSource?
            switch viewModel.state.collection.identifier {
            case .collection(let key):
                collectionsSource = .collectionKeys([key])

            case .search, .custom:
                collectionsSource = nil
            }
            showTypePicker(selected: "") { [weak self] type in
                self?.showItemDetail(for: .creation(type: type, child: nil, collectionsSource: collectionsSource), libraryId: viewModel.state.library.identifier, scrolledToKey: nil, animated: true)
            }
        }))

        controller.addAction(UIAlertAction(title: L10n.Items.newNote, style: .default, handler: { [weak self, weak viewModel] _ in
            guard let self, let viewModel else { return }
            showNote(library: viewModel.state.library, kind: .standaloneCreation(collection: viewModel.state.collection), saveCallback: nil)
        }))

        if viewModel.state.library.metadataAndFilesEditable {
            controller.addAction(UIAlertAction(title: L10n.Items.newFile, style: .default, handler: { [weak self, weak viewModel] _ in
                self?.showAttachmentPicker(save: { urls in
                    viewModel?.process(action: .addAttachments(urls))
                })
            }))
        }

        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))

        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    func showSortActions(sortType: ItemsSortType, button: UIBarButtonItem, changed: @escaping (ItemsSortType) -> Void) {
        DDLogInfo("DetailCoordinator: show item sort popup")

        let sortNavigationController = UINavigationController()
        sortNavigationController.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        sortNavigationController.popoverPresentationController?.barButtonItem = button
        let view = ItemSortingView(
            sortType: sortType,
            changed: changed,
            showPicker: { [weak sortNavigationController] view in
                guard let sortNavigationController else { return }
                showPicker(view: view, navigationController: sortNavigationController)
            },
            closePicker: { [weak sortNavigationController] in
                sortNavigationController?.popViewController(animated: true)
            }
        )
        let controller = createItemSortingController(for: view, navigationController: sortNavigationController)
        sortNavigationController.setViewControllers([controller], animated: false)
        navigationController?.present(sortNavigationController, animated: true, completion: nil)

        func createItemSortingController(for view: ItemSortingView, navigationController: UINavigationController) -> UIHostingController<ItemSortingView> {
            let controller = DisappearActionHostingController(rootView: view)
            var size: CGSize?
            controller.willAppear = { [weak controller, weak navigationController] in
                guard let controller else { return }
                let _size = size ?? controller.view.systemLayoutSizeFitting(CGSize(width: 400.0, height: .greatestFiniteMagnitude))
                size = _size
                controller.preferredContentSize = _size
                navigationController?.preferredContentSize = _size
            }

            if UIDevice.current.userInterfaceIdiom == .phone {
                controller.didLoad = { [weak self] viewController in
                    guard let self else { return }
                    let doneButton = UIBarButtonItem(title: L10n.done, style: .done, target: nil, action: nil)
                    doneButton.rx.tap
                        .subscribe({ [weak self] _ in
                            self?.navigationController?.dismiss(animated: true)
                        })
                        .disposed(by: disposeBag)
                    viewController.navigationItem.rightBarButtonItem = doneButton
                }
            }
            return controller
        }

        func showPicker(view: ItemSortTypePickerView, navigationController: UINavigationController) {
            let controller = UIHostingController(rootView: view)
            controller.preferredContentSize = CGSize(width: 400, height: 600)
            navigationController.preferredContentSize = controller.preferredContentSize
            navigationController.pushViewController(controller, animated: true)
        }
    }

    private func sortButtonTitles(for sortType: ItemsSortType) -> (field: String, order: String) {
        let sortOrderTitle = sortType.ascending ? L10n.Items.ascending : L10n.Items.descending
        return ("\(L10n.Items.sortBy): \(sortType.field.title)", "\(L10n.Items.sortOrder): \(sortOrderTitle)")
    }

    func createNoteController(
        library: Library,
        kind: NoteEditorKind,
        text: String,
        tags: [Tag],
        parentTitleData: NoteEditorState.TitleData?,
        title: String?
    ) -> NavigationViewController {
        return createNoteController(library: library, kind: kind, text: text, tags: tags, parentTitleData: parentTitleData, title: title).0
    }

    private func createNoteController(
        library: Library,
        kind: NoteEditorKind,
        text: String,
        tags: [Tag],
        parentTitleData: NoteEditorState.TitleData?,
        title: String?
    ) -> (NavigationViewController, ViewModel<NoteEditorActionHandler>) {
        let navigationController = NavigationViewController()
        navigationController.modalPresentationStyle = .fullScreen
        navigationController.isModalInPresentation = true

        let coordinator = NoteEditorCoordinator(
            library: library,
            kind: kind,
            text: text,
            tags: tags,
            parentTitleData: parentTitleData,
            title: title,
            navigationController: navigationController,
            controllers: controllers
        )
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)
        // Forced unwrapping of `viewModel` must happen after `coordinator.start(animated:)`!
        return (navigationController, coordinator.viewModel!)
    }

    func showItemDetail(for type: ItemDetailState.DetailType, libraryId: LibraryIdentifier, scrolledToKey childKey: String?, animated: Bool) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage,
              let fileDownloader = self.controllers.userControllers?.fileDownloader,
              let fileCleanupController = self.controllers.userControllers?.fileCleanupController
        else { return }

        switch type {
        case .preview(let key):
            DDLogInfo("DetailCoordinator: show item detail \(key)")

        case .duplication(let itemKey, let collectionKey):
            DDLogInfo("DetailCoordinator: show item duplication for \(itemKey); \(String(describing: collectionKey))")

        case .creation:
            DDLogInfo("DetailCoordinator: show item creation")
        }

        let state = ItemDetailState(type: type, libraryId: libraryId, preScrolledChildKey: childKey, userId: Defaults.shared.userId)
        let handler = ItemDetailActionHandler(
            apiClient: self.controllers.apiClient,
            fileStorage: self.controllers.fileStorage,
            dbStorage: dbStorage,
            schemaController: self.controllers.schemaController,
            dateParser: self.controllers.dateParser,
            urlDetector: self.controllers.urlDetector,
            fileDownloader: fileDownloader,
            fileCleanupController: fileCleanupController,
            htmlAttributedStringConverter: controllers.htmlAttributedStringConverter
        )
        let viewModel = ViewModel(initialState: state, handler: handler)

        let controller = ItemDetailViewController(viewModel: viewModel, controllers: self.controllers)
        controller.coordinatorDelegate = self
        self.navigationController?.pushViewController(controller, animated: animated)
    }

    func showCollectionsPicker(in library: Library, completed: @escaping (Set<String>) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        DDLogInfo("DetailCoordinator: show collection picker")

        let state = CollectionsPickerState(library: library, excludedKeys: [], selected: [])
        let handler = CollectionsPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = CollectionsPickerViewController(mode: .multiple(selected: completed), viewModel: viewModel)

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet
        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    func showFilters(filters: [ItemsFilter], filtersDelegate: BaseItemsViewController, button: UIBarButtonItem) {
        DDLogInfo("DetailCoordinator: show item filters")

        let navigationController = NavigationViewController()
        navigationController.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        navigationController.popoverPresentationController?.barButtonItem = button

        let coordinator = ItemsFilterCoordinator(filters: filters, filtersDelegate: filtersDelegate, navigationController: navigationController, controllers: controllers)
        coordinator.parentCoordinator = self
        childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    func showDeletionQuestion(count: Int, confirmAction: @escaping () -> Void, cancelAction: @escaping () -> Void) {
        let question = L10n.Items.deleteQuestion(count)
        self.ask(question: question, title: L10n.delete, isDestructive: true, confirm: confirmAction, cancel: cancelAction)
    }

    func showRemoveFromCollectionQuestion(count: Int, confirmAction: @escaping () -> Void) {
        let question = L10n.Items.removeFromCollectionQuestion(count)
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
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    func showCitation(using presenter: UIViewController?, for itemIds: Set<String>, libraryId: LibraryIdentifier, delegate: DetailCitationCoordinatorDelegate?) {
        guard let resolvedPresenter = presenter ?? navigationController else { return }
        guard let citationController = controllers.userControllers?.citationController else { return }

        DDLogInfo("DetailCoordinator: show citation popup for \(itemIds)")

        let state = SingleCitationState(
            itemIds: itemIds,
            libraryId: libraryId,
            styleId: Defaults.shared.quickCopyStyleId,
            localeId: Defaults.shared.quickCopyLocaleId,
            exportAsHtml: Defaults.shared.quickCopyAsHtml
        )
        let handler = SingleCitationActionHandler(citationController: citationController)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let controller = SingleCitationViewController(viewModel: viewModel)
        controller.coordinatorDelegate = delegate ?? self
        let navigationController = UINavigationController(rootViewController: controller)
        let containerController = ContainerViewController(rootViewController: navigationController)
        resolvedPresenter.present(containerController, animated: true, completion: nil)
    }

    func copyBibliography(using presenter: UIViewController, for itemIds: Set<String>, libraryId: LibraryIdentifier, delegate: DetailCopyBibliographyCoordinatorDelegate?) {
        guard let citationController = controllers.userControllers?.citationController else { return }

        DDLogInfo("DetailCoordinator: copy bibliography for \(itemIds)")

        let state = CopyBibliographyState(
            itemIds: itemIds,
            libraryId: libraryId,
            styleId: Defaults.shared.quickCopyStyleId,
            localeId: Defaults.shared.quickCopyLocaleId,
            exportAsHtml: Defaults.shared.quickCopyAsHtml
        )
        let handler = CopyBibliographyActionHandler(citationController: citationController)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = CopyBibliographyViewController(viewModel: viewModel)
        controller.coordinatorDelegate = delegate ?? self

        controller.modalPresentationStyle = .overCurrentContext
        controller.modalTransitionStyle = .crossDissolve
        presenter.present(controller, animated: true)
    }

    func showCiteExport(for itemIds: Set<String>, libraryId: LibraryIdentifier) {
        DDLogInfo("DetailCoordinator: show citation/bibliography export for \(itemIds)")

        let navigationController = NavigationViewController()
        let containerController = ContainerViewController(rootViewController: navigationController)
        let coordinator = CitationBibliographyExportCoordinator(itemIds: itemIds, libraryId: libraryId, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)
        self.navigationController?.present(containerController, animated: true, completion: nil)
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
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    private func showLookup(startWith: LookupStartingView) {
        let navigationController = NavigationViewController()
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet

        let coordinator = LookupCoordinator(startWith: startWith, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }
    
    func showLookup() {
        showLookup(startWith: .manual(restoreLookupState: true))
    }
}

extension DetailCoordinator: DetailItemDetailCoordinatorDelegate {
    func showAttachmentPicker(save: @escaping ([URL]) -> Void) {
        guard let navigationController else { return }
        let controller = DocumentPickerViewController(forOpeningContentTypes: [.pdf, .png, .jpeg], asCopy: true)
        controller.popoverPresentationController?.sourceView = navigationController.visibleViewController?.view
        controller.observable
                  .observe(on: MainScheduler.instance)
                  .subscribe(onNext: { urls in
                      save(urls)
                  })
                  .disposed(by: self.disposeBag)
        navigationController.present(controller, animated: true, completion: nil)
    }

    func showAttachmentError(_ error: Error) {
        let (message, actions) = attachmentMessageAndActions(for: error)
        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        for action in actions {
            controller.addAction(action)
        }
        navigationController?.present(controller, animated: true, completion: nil)

        func attachmentMessageAndActions(for error: Error) -> (String, [UIAlertAction]) {
            let cancelAction: [UIAlertAction] = [UIAlertAction(title: L10n.ok, style: .cancel)]
            if let error = error as? AttachmentDownloader.Error {
                switch error {
                case .incompatibleAttachment:
                    return (L10n.Errors.Attachments.incompatibleAttachment, cancelAction)

                case .zipDidntContainRequestedFile:
                    return (L10n.Errors.Attachments.cantOpenAttachment, cancelAction)

                case .cantUnzipSnapshot:
                    return (L10n.Errors.Attachments.cantUnzipSnapshot, cancelAction)

                case .cancelled:
                    break
                }
            }

            if let afError = error as? AFError, let result = afErrorMessageAndActions(from: afError, url: nil, cancelAction: cancelAction) {
                return result
            }

            if let responseError = error as? AFResponseError, let result = afErrorMessageAndActions(from: responseError.error, url: responseError.url, cancelAction: cancelAction) {
                return result
            }

            return (L10n.Errors.Attachments.cantOpenAttachment, cancelAction)
        }

        func afErrorMessageAndActions(from error: AFError, url: URL?, cancelAction: [UIAlertAction]) -> (String, [UIAlertAction])? {
            switch error {
            case .responseValidationFailed(let reason):
                switch reason {
                case .unacceptableStatusCode(let code):
                    let webDavEnabled = controllers.userControllers?.webDavController.sessionStorage.isEnabled ?? false
                    switch code {
                    case 401:
                        if webDavEnabled {
                            let action = UIAlertAction(title: L10n.goToSettings, style: .default) { [weak self] _ in
                                guard let self, let navigationController else { return }
                                showSettings(using: navigationController, initialScreen: .sync)
                            }
                            return(L10n.Errors.Attachments.unauthorizedWebdav, [action] + cancelAction)
                        }

                    case 403:
                        if webDavEnabled {
                            let message = L10n.Errors.Attachments.forbiddenWebdav(url?.lastPathComponent ?? L10n.Errors.Attachments.genericFilename)
                            return(message, cancelAction)
                        }

                    case 404:
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
                        return (message, cancelAction + [action])

                    default:
                        break
                    }

                default:
                    break
                }

            default:
                break
            }
            return nil
        }
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
        DDLogInfo("DetailCoordinator: show item detail creator editor for \(creator.type)")

        let navigationController = NavigationViewController()
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet

        let coordinator = CreatorEditCoordinator(creator: creator, itemType: itemType, saved: saved, deleted: deleted, navigationController: navigationController, controllers: self.controllers)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        self.navigationController?.present(navigationController, animated: true, completion: nil)
    }

    func showTypePicker(selected: String, picked: @escaping (String) -> Void) {
        DDLogInfo("DetailCoordinator: show item type picker")
        let viewModel = ItemTypePickerViewModelCreator.create(selected: selected, schemaController: self.controllers.schemaController)
        self.presentPicker(viewModel: viewModel, requiresSaveButton: false, saveAction: picked)
    }

    private func presentPicker(viewModel: ViewModel<SinglePickerActionHandler>, requiresSaveButton: Bool, saveAction: @escaping (String) -> Void) {
        let view = SinglePickerView(requiresSaveButton: requiresSaveButton, requiresCancelButton: true, saveAction: saveAction) { [weak self] completion in
            self?.navigationController?.dismiss(animated: true, completion: {
                completion?()
            })
        }
        .environmentObject(viewModel)

        let controller = UINavigationController(rootViewController: UIHostingController(rootView: view))
        controller.isModalInPresentation = true
        controller.modalPresentationStyle = .formSheet
        self.navigationController?.present(controller, animated: true, completion: nil)
    }

    func showDeletedAlertForItem(completion: @escaping (Bool) -> Void) {
        let popAction: () -> Void = { [weak self] in
            guard let navigationController = self?.navigationController else { return }
            if navigationController.presentedViewController != nil {
                navigationController.dismiss(animated: true, completion: {
                    navigationController.popViewController(animated: true)
                })
            } else {
                navigationController.popViewController(animated: true)
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
        self.navigationController?.present(controller, animated: true, completion: nil)
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
                self?.navigationController?.popViewController(animated: true)
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
        self.navigationController?.present(controller, animated: true, completion: nil)
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
        self.navigationController?.present(controller, animated: true, completion: nil)
    }
}

extension DetailCoordinator: DetailNoteEditorCoordinatorDelegate {
    func showNote(
        library: Library,
        kind: NoteEditorKind,
        text: String = "",
        tags: [Tag] = [],
        parentTitleData: NoteEditorState.TitleData? = nil,
        title: String? = nil,
        saveCallback: ((Note) -> Void)?
    ) {
        guard let navigationController else { return }
        switch kind {
        case .itemCreation, .standaloneCreation:
            DDLogInfo("DetailCoordinator: show note creation")

        case .edit(let key), .readOnly(let key):
            DDLogInfo("DetailCoordinator: show note \(key)")
        }
        let (controller, viewModel) = createNoteController(library: library, kind: kind, text: text, tags: tags, parentTitleData: parentTitleData, title: title)
        navigationController.present(controller, animated: true)

        if let saveCallback {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { state in
                    guard state.changes.contains(.saved), case .edit(let key) = state.kind else { return }
                    saveCallback(Note(key: key, text: state.text, tags: state.tags))
                })
                .disposed(by: disposeBag)
        }
    }
}

extension DetailCoordinator: DetailMissingStyleErrorDelegate {
    func showMissingStyleError(using presenter: UINavigationController?) {
        guard let resolvedPresenter = presenter ?? navigationController else { return }
        let controller = UIAlertController(title: L10n.error, message: L10n.Errors.Citation.missingStyle, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        controller.addAction(UIAlertAction(title: L10n.Errors.Citation.openSettings, style: .default, handler: { [weak self] _ in
            self?.showSettings(using: resolvedPresenter, initialScreen: .export)
        }))

        if resolvedPresenter.presentedViewController == nil {
            resolvedPresenter.present(controller, animated: true)
        } else {
            resolvedPresenter.dismiss(animated: true) {
                resolvedPresenter.present(controller, animated: true)
            }
        }
    }
}

extension DetailCoordinator: DetailCitationCoordinatorDelegate {
    func showCitationPreviewError(using presenter: UINavigationController, errorMessage: String) {
        let controller = UIAlertController(title: L10n.error, message: errorMessage, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        presenter.present(controller, animated: true, completion: nil)
    }
}

extension DetailCoordinator: DetailCopyBibliographyCoordinatorDelegate { }

// swiftlint:disable private_over_fileprivate
fileprivate class AVPlayerDelegate: NSObject, AVPlayerViewControllerDelegate {
    private var dismissBlock: () -> Void

    init(dismissBlock: @escaping () -> Void) {
        self.dismissBlock = dismissBlock
        super.init()
    }

    func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
        dismissBlock()
    }
}
// swiftlint:enable private_over_fileprivate
