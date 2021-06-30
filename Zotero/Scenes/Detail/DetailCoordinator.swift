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

#if PDFENABLED

import PSPDFKit
import PSPDFKitUI

#endif

protocol DetailCoordinatorAttachmentProvider {
    func attachment(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Attachment, Library, UIView, CGRect?)?
}

protocol DetailItemsCoordinatorDelegate: AnyObject {
    func showCollectionPicker(in library: Library, completed: @escaping (Set<String>) -> Void)
    func showItemDetail(for type: ItemDetailState.DetailType, library: Library)
    func showAttachmentError(_ error: Error, retryAction: @escaping () -> Void)
    func showNote(with text: String, tags: [Tag], title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, readOnly: Bool, save: @escaping (String, [Tag]) -> Void)
    func showAddActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem)
    func showSortActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem)
    func showWeb(url: URL)
    func show(doi: String)
    func showFilters(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem)
    func showDeletionQuestion(count: Int, confirmAction: @escaping () -> Void)
    func showRemoveFromCollectionQuestion(count: Int, confirmAction: @escaping () -> Void)
    func showCitation(for item: RItem)
    func showCiteExport(for items: Set<String>)
}

protocol DetailItemDetailCoordinatorDelegate: AnyObject {
    func showNote(with text: String, tags: [Tag], title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, readOnly: Bool, save: @escaping (String, [Tag]) -> Void)
    func showAttachmentPicker(save: @escaping ([URL]) -> Void)
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
    func showTypePicker(selected: String, picked: @escaping (String) -> Void)
    func showWeb(url: URL)
    func show(doi: String)
    func showCreatorCreation(for itemType: String, saved: @escaping CreatorEditSaveAction)
    func showCreatorEditor(for creator: ItemDetailState.Creator, itemType: String, saved: @escaping CreatorEditSaveAction, deleted: @escaping CreatorEditDeleteAction)
    func showAttachmentError(_ error: Error, retryAction: @escaping () -> Void)
    func showDeletedAlertForItem(completion: @escaping (Bool) -> Void)
    func show(error: ItemDetailError, viewModel: ViewModel<ItemDetailActionHandler>)
    func showDataReloaded(completion: @escaping () -> Void)
    func showTrashAttachmentQuestion(trashAction: @escaping () -> Void)
}

protocol DetailCreatorEditCoordinatorDelegate: AnyObject {
    func showCreatorTypePicker(itemType: String, selected: String, picked: @escaping (String) -> Void)
}

protocol DetailNoteEditorCoordinatorDelegate: AnyObject {
    func showWeb(url: URL)
    func pushTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
}

#if PDFENABLED

protocol DetailPdfCoordinatorDelegate: AnyObject {
    func showColorPicker(selected: String?, sender: UIButton, save: @escaping (String) -> Void)
    func showSearch(pdfController: PDFViewController, sender: UIBarButtonItem, result: @escaping (SearchResult) -> Void)
    func showAnnotationPopover(viewModel: ViewModel<PDFReaderActionHandler>, sourceRect: CGRect, popoverDelegate: UIPopoverPresentationControllerDelegate)
    func show(error: PdfDocumentExporter.Error)
    func share(url: URL, barButton: UIBarButtonItem)
    func share(text: String, rect: CGRect, view: UIView)
    func lookup(text: String, rect: CGRect, view: UIView)
    func showDeletedAlertForPdf(completion: @escaping (Bool) -> Void)
    func pdfDidDeinitialize()
    func showSettings(state: PDFSettingsState, sender: UIBarButtonItem, completion: @escaping (PDFReaderAction) -> Void)
}

protocol DetailAnnotationsCoordinatorDelegate: AnyObject {
    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void)
    func showCellOptions(for annotation: Annotation, sender: UIButton, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction)
}

#endif

protocol DetailItemActionSheetCoordinatorDelegate: AnyObject {
    func showSortTypePicker(sortBy: Binding<ItemsSortType.Field>)
    func showNoteCreation(title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, save: @escaping (String, [Tag]) -> Void)
    func showAttachmentPicker(save: @escaping ([URL]) -> Void)
    func showItemCreation(library: Library, collectionKey: String?)
}

protocol DetailCitationCoordinatorDelegate: AnyObject {
    func showLocatorPicker(for values: [SinglePickerModel], selected: String, picked: @escaping (String) -> Void)
}

protocol DetailCitationBibliographyExportCoordinatorDelegate: AnyObject {
    func cancel()
}

fileprivate class EmptyTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {}

final class DetailCoordinator: Coordinator {
    enum ActivityViewControllerSource {
        case view(UIView, CGRect?)
        case barButton(UIBarButtonItem)
    }

    var parentCoordinator: Coordinator?
    var childCoordinators: [Coordinator]
    private var transitionDelegate: EmptyTransitioningDelegate?
    #if PDFENABLED
    private var pdfSearchController: PDFSearchViewController?
    #endif

    let collection: Collection
    let library: Library
    private unowned let controllers: Controllers
    unowned let navigationController: UINavigationController
    private let disposeBag: DisposeBag

    private weak var citationNavigationController: UINavigationController?

    init(library: Library, collection: Collection, navigationController: UINavigationController, controllers: Controllers) {
        self.library = library
        self.collection = collection
        self.navigationController = navigationController
        self.controllers = controllers
        self.childCoordinators = []
        self.disposeBag = DisposeBag()

        if let attachmentDownloader = controllers.userControllers?.fileDownloader {
            attachmentDownloader.observable
                                .subscribe(onNext: { [weak self] update in
                                    switch update.kind {
                                    case .ready:
                                        self?.showAttachment(key: update.key, parentKey: update.parentKey, libraryId: update.libraryId)
                                    default: break
                                    }
                                })
                                .disposed(by: self.disposeBag)
        }
    }

    func start(animated: Bool) {
        guard let userControllers = self.controllers.userControllers else { return }
        let controller = self.createItemsViewController(collection: self.collection, library: self.library,
                                                        dbStorage: userControllers.dbStorage, fileDownloader: userControllers.fileDownloader)
        self.navigationController.setViewControllers([controller], animated: animated)
    }

    private func createItemsViewController(collection: Collection, library: Library, dbStorage: DbStorage,
                                           fileDownloader: AttachmentDownloader) -> ItemsViewController {
        let type = self.fetchType(from: collection)
        let state = ItemsState(type: type, library: library, sortType: .default, error: nil)
        let handler = ItemsActionHandler(dbStorage: dbStorage,
                                         fileStorage: self.controllers.fileStorage,
                                         schemaController: self.controllers.schemaController,
                                         urlDetector: self.controllers.urlDetector,
                                         fileDownloader: fileDownloader,
                                         citationController: self.controllers.citationController)
        return ItemsViewController(viewModel: ViewModel(initialState: state, handler: handler), controllers: self.controllers, coordinatorDelegate: self)
    }

    private func fetchType(from collection: Collection) -> ItemFetchType {
        switch collection.identifier {
        case .collection(let key):
            return .collection(key, collection.name)
        case .search(let key):
            return .search(key, collection.name)
        case .custom(let type):
            switch type {
            case .all:
                return .all
            case .publications:
                return .publications
            case .trash:
                return .trash
            }
        }
    }

    private func showAttachment(key: String, parentKey: String?, libraryId: LibraryIdentifier) {
        guard let (attachment, library, sourceView, sourceRect) = self.navigationController.viewControllers.reversed()
                                                                      .compactMap({ ($0 as? DetailCoordinatorAttachmentProvider)?.attachment(for: key, parentKey: parentKey, libraryId: libraryId) })
                                                                      .first else { return }
        self.show(attachment: attachment, library: library, sourceView: sourceView, sourceRect: sourceRect)
    }

    private func show(attachment: Attachment, library: Library, sourceView: UIView, sourceRect: CGRect?) {
        switch attachment.type {
        case .url(let url):
            self.showWeb(url: url)

        case .file(let filename, let contentType, _, _):
            let file = Files.attachmentFile(in: library.identifier, key: attachment.key, filename: filename, contentType: contentType)
            let url = file.createUrl()

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
                    self.share(item: url, source: .view(sourceView, sourceRect))
                }
            case _ where contentType.contains("image"):
                let image = (contentType == "image/gif") ? (try? Data(contentsOf: url)).flatMap({ try? UIImage(gifData: $0) }) :
                                                             UIImage(contentsOfFile: url.path)
                if let image = image {
                    self.show(image: image, title: filename)
                } else {
                  self.share(item: url, source: .view(sourceView, sourceRect))
                }
            default:
                if AVURLAsset(url: url).isPlayable {
                    self.showVideo(for: url)
                } else {
                    self.share(item: file.createUrl(), source: .view(sourceView, sourceRect))
                }
            }
        }
    }

    private func show(text: String, title: String) {
        let controller = TextPreviewViewController(text: text, title: title)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }

    private func show(image: UIImage, title: String) {
        let controller = ImagePreviewViewController(image: image, title: title)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }

    private func showVideo(for url: URL) {
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        self.topViewController.present(controller, animated: true) {
            player.play()
        }
    }

    func showTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let tagController = TagPickerViewController(viewModel: viewModel, saveAction: picked)

        let controller = UINavigationController(rootViewController: tagController)
        controller.isModalInPresentation = true
        controller.modalPresentationStyle = .formSheet
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    private func showPdf(at url: URL, key: String, library: Library) {
        #if PDFENABLED
        let username = Defaults.shared.username
        guard let dbStorage = self.controllers.userControllers?.dbStorage,
              let userId = self.controllers.sessionController.sessionData?.userId,
              !username.isEmpty else { return }

        let handler = PDFReaderActionHandler(dbStorage: dbStorage, annotationPreviewController: self.controllers.annotationPreviewController,
                                             htmlAttributedStringConverter: self.controllers.htmlAttributedStringConverter, schemaController: self.controllers.schemaController,
                                             fileStorage: self.controllers.fileStorage)
        let state = PDFReaderState(url: url, key: key, library: library, settings: Defaults.shared.pdfSettings, userId: userId, username: username,
                                   interfaceStyle: self.topViewController.view.traitCollection.userInterfaceStyle)
        let controller = PDFReaderViewController(viewModel: ViewModel(initialState: state, handler: handler),
                                                 compactSize: UIDevice.current.isCompactWidth(size: self.navigationController.view.frame.size))
        controller.coordinatorDelegate = self
        handler.boundingBoxConverter = controller
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.topViewController.present(navigationController, animated: true, completion: nil)
        #endif
    }

    private func showWebView(for url: URL) {
        let controller = WebViewController(url: url)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }

    private func share(item: Any, source: ActivityViewControllerSource) {
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet

        switch source {
        case .barButton(let item):
            controller.popoverPresentationController?.barButtonItem = item
        case .view(let sourceView, let sourceRect):
            controller.popoverPresentationController?.sourceView = sourceView
            controller.popoverPresentationController?.sourceRect = sourceRect ?? CGRect(x: (sourceView.frame.width / 3.0),
                                                                                        y: (sourceView.frame.height * 2.0 / 3.0),
                                                                                        width: (sourceView.frame.width / 3),
                                                                                        height: (sourceView.frame.height / 3))
        }

        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func show(doi: String) {
        guard let url = URL(string: "https://doi.org/\(doi)") else { return }
        self.showWeb(url: url)
    }

    func showWeb(url: URL) {
        let controller = SFSafariViewController(url: url.withHttpSchemeIfMissing)
        controller.modalPresentationStyle = .fullScreen
        // Changes transition to normal modal transition instead of push from right.
        self.transitionDelegate = EmptyTransitioningDelegate()
        controller.transitioningDelegate = self.transitionDelegate
        self.transitionDelegate = nil
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    fileprivate var topViewController: UIViewController {
        var controller: UIViewController = self.navigationController
        while let presentedController = controller.presentedViewController {
            controller = presentedController
        }
        return controller
    }
}

extension DetailCoordinator: DetailItemsCoordinatorDelegate {
    func showAddActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem) {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.popoverPresentationController?.barButtonItem = button

        controller.addAction(UIAlertAction(title: L10n.Items.new, style: .default, handler: { [weak self, weak viewModel] _ in
            guard let `self` = self, let viewModel = viewModel else { return }
            self.showItemCreation(library: viewModel.state.library, collectionKey: viewModel.state.type.collectionKey)
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

        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func showSortActions(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem) {
        let (fieldTitle, orderTitle) = self.sortButtonTitles(for: viewModel.state.sortType)
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.popoverPresentationController?.barButtonItem = button

        controller.addAction(UIAlertAction(title: fieldTitle, style: .default, handler: { [weak self, weak viewModel] _ in
            guard let `self` = self, let viewModel = viewModel else { return }
            let binding = viewModel.binding(keyPath: \.sortType.field, action: { .setSortField($0) })
            self.showSortTypePicker(sortBy: binding)
        }))

        controller.addAction(UIAlertAction(title: orderTitle, style: .default, handler: { [weak viewModel] _ in
            viewModel?.process(action: .toggleSortOrder)
        }))

        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))

        self.topViewController.present(controller, animated: true, completion: nil)
    }

    private func sortButtonTitles(for sortType: ItemsSortType) -> (field: String, order: String) {
        let sortOrderTitle = sortType.ascending ? L10n.Items.ascending : L10n.Items.descending
        return ("\(L10n.Items.sortBy): \(sortType.field.title)",
                "\(L10n.Items.sortOrder): \(sortOrderTitle)")
    }

    func showNote(with text: String, tags: [Tag], title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, readOnly: Bool, save: @escaping (String, [Tag]) -> Void) {
        let state = NoteEditorState(title: title, text: text, tags: tags, libraryId: libraryId, readOnly: readOnly)
        let handler = NoteEditorActionHandler(saveAction: save)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = NoteEditorViewController(viewModel: viewModel)
        controller.coordinatorDelegate = self

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        navigationController.isModalInPresentation = true
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }

    func showItemDetail(for type: ItemDetailState.DetailType, library: Library) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage,
              let fileDownloader = self.controllers.userControllers?.fileDownloader,
              let fileCleanupController = self.controllers.userControllers?.fileCleanupController else { return }

        let hidesBackButton: Bool
        switch type {
        case .preview:
            hidesBackButton = false
        case .creation, .duplication:
            hidesBackButton = true
        }

        let state = ItemDetailState(type: type, library: library, userId: Defaults.shared.userId)
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
        controller.navigationItem.setHidesBackButton(hidesBackButton, animated: false)
        self.navigationController.pushViewController(controller, animated: true)
    }

    func showCollectionPicker(in library: Library, completed: @escaping (Set<String>) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let state = CollectionPickerState(library: library, excludedKeys: [], selected: [])
        let handler = CollectionPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)

        // SWIFTUI BUG: - We need to call loadData here, because when we do so in `onAppear` in SwiftUI `View` we'll crash when data change
        // instantly in that function. If we delay it, the user will see unwanted animation of data on screen. If we call it here, data
        // is available immediately.
        viewModel.process(action: .loadData)

        let view = CollectionsPickerView(completionAction: completed,
                                         closeAction: { [weak self] in
                                            self?.topViewController.dismiss(animated: true, completion: nil)
                                         })
                                         .environmentObject(viewModel)

        let navigationController = UINavigationController(rootViewController: UIHostingController(rootView: view))
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }

    func showFilters(viewModel: ViewModel<ItemsActionHandler>, button: UIBarButtonItem) {
        let controller = ItemsFilterViewController(viewModel: viewModel)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        navigationController.popoverPresentationController?.barButtonItem = button
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }

    func showDeletionQuestion(count: Int, confirmAction: @escaping () -> Void) {
        let question = count == 1 ? L10n.Items.deleteQuestion : L10n.Items.deleteMultipleQuestion
        self.ask(question: question, title: L10n.delete, isDestructive: true, confirm: confirmAction)
    }

    func showRemoveFromCollectionQuestion(count: Int, confirmAction: @escaping () -> Void) {
        let question = count == 1 ? L10n.Items.removeFromCollectionQuestion : L10n.Items.removeFromCollectionMultipleQuestion
        self.ask(question: question, title: L10n.Items.removeFromCollectionTitle, isDestructive: false, confirm: confirmAction)
    }

    private func ask(question: String, title: String, isDestructive: Bool, confirm: @escaping () -> Void) {
        let controller = UIAlertController(title: title, message: question, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: (isDestructive ? .destructive : .default), handler: { _ in
            confirm()
        }))
        controller.addAction(UIAlertAction(title: L10n.no, style: .cancel, handler: nil))
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func showCitation(for item: RItem) {
        let state = SingleCitationState(item: item, styleId: Defaults.shared.quickCopyStyleId, localeId: Defaults.shared.quickCopyLocaleId)
        let handler = SingleCitationActionHandler(citationController: self.controllers.citationController)
        let viewModel = ViewModel(initialState: state, handler: handler)

        let controller = SingleCitationViewController(viewModel: viewModel)
        controller.coordinatorDelegate = self
        let navigationController = UINavigationController(rootViewController: controller)
        self.citationNavigationController = navigationController
        let containerController = ContainerViewController(rootViewController: navigationController)
        containerController.isModalInPresentation = true
        containerController.modalPresentationStyle = .formSheet
        self.navigationController.present(containerController, animated: true, completion: nil)
    }

    func showCiteExport(for items: Set<String>) {
        do {
            let styleId = Defaults.shared.quickCopyStyleId
            let rStyle = try self.controllers.bundledDataStorage.createCoordinator().perform(request: ReadStyleDbRequest(identifier: styleId))
            guard let style = Style(rStyle: rStyle) else { return }

            let state = CitationBibliographyExportState(selectedStyle: style, selectedLocaleId: Defaults.shared.quickCopyLocaleId)
            let handler = CitationBibliographyExportActionHandler(citationController: self.controllers.citationController)
            let viewModel = ViewModel(initialState: state, handler: handler)

            var view = CitationBibliographyExportView()
            view.coordinatorDelegate = self

            let controller = UIHostingController(rootView: view.environmentObject(viewModel))
            let navigationController = UINavigationController(rootViewController: controller)
            self.topViewController.present(navigationController, animated: true, completion: nil)
        } catch let error {
            DDLogError("DetailCoordinator: can't open citeexport - \(error)")
        }
    }
}

extension DetailCoordinator: DetailItemActionSheetCoordinatorDelegate {
    func showSortTypePicker(sortBy: Binding<ItemsSortType.Field>) {
        let view = ItemSortTypePickerView(sortBy: sortBy,
                                          closeAction: { [weak self] in
                                              self?.topViewController.dismiss(animated: true, completion: nil)
                                          })
        let navigationController = UINavigationController(rootViewController: UIHostingController(rootView: view))
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }

    func showNoteCreation(title: NoteEditorState.TitleData?, libraryId: LibraryIdentifier, save: @escaping (String, [Tag]) -> Void) {
        self.showNote(with: "", tags: [], title: title, libraryId: libraryId, readOnly: false, save: save)
    }

    func showAttachmentPicker(save: @escaping ([URL]) -> Void) {
        let documentTypes = [String(kUTTypePDF), String(kUTTypePNG), String(kUTTypeJPEG)]
        let controller = DocumentPickerViewController(documentTypes: documentTypes, in: .import)
        controller.popoverPresentationController?.sourceView = self.navigationController.visibleViewController?.view
        controller.observable
                  .observe(on: MainScheduler.instance)
                  .subscribe(onNext: { urls in
                      save(urls)
                  })
                  .disposed(by: self.disposeBag)
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func showItemCreation(library: Library, collectionKey: String?) {
        self.showTypePicker(selected: "") { [weak self] type in
            self?.showItemDetail(for: .creation(type: type, child: nil, collectionKey: collectionKey), library: library)
        }
    }
}

extension DetailCoordinator: DetailItemDetailCoordinatorDelegate {
    func showAttachmentError(_ error: Error, retryAction: @escaping () -> Void) {
        let message: String
        if let error = error as? ItemDetailError, error == .cantUnzipSnapshot {
            message = L10n.Errors.Attachments.cantUnzipSnapshot
        } else {
            message = L10n.Errors.Attachments.cantOpenAttachment
        }

        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        controller.addAction(UIAlertAction(title: L10n.retry, style: .default, handler: { _ in
            retryAction()
        }))
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func showCreatorCreation(for itemType: String, saved: @escaping CreatorEditSaveAction) {
        guard let schema = self.controllers.schemaController.creators(for: itemType)?.first(where: { $0.primary }),
              let localized = self.controllers.schemaController.localized(creator: schema.creatorType) else { return }
        let creator = ItemDetailState.Creator(type: schema.creatorType, primary: schema.primary, localizedType: localized)
        self._showCreatorEditor(for: creator, itemType: itemType, saved: saved, deleted: nil)
    }

    func showCreatorEditor(for creator: ItemDetailState.Creator, itemType: String, saved: @escaping CreatorEditSaveAction, deleted: @escaping CreatorEditDeleteAction) {
        self._showCreatorEditor(for: creator, itemType: itemType, saved: saved, deleted: deleted)
    }

    private func _showCreatorEditor(for creator: ItemDetailState.Creator, itemType: String, saved: @escaping CreatorEditSaveAction, deleted: CreatorEditDeleteAction?) {
        let state = CreatorEditState(itemType: itemType, creator: creator)
        let handler = CreatorEditActionHandler(schemaController: self.controllers.schemaController)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = CreatorEditViewController(viewModel: viewModel, saved: saved, deleted: deleted)
        controller.coordinatorDelegate = self

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.isModalInPresentation = true
        navigationController.modalPresentationStyle = .formSheet
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }

    func showTypePicker(selected: String, picked: @escaping (String) -> Void) {
        let viewModel = ItemTypePickerViewModelCreator.create(selected: selected, schemaController: self.controllers.schemaController)
        self.presentPicker(viewModel: viewModel, requiresSaveButton: false, saveAction: picked)
    }

    private func presentPicker(viewModel: ViewModel<SinglePickerActionHandler>, requiresSaveButton: Bool, saveAction: @escaping (String) -> Void) {
        let view = SinglePickerView(requiresSaveButton: requiresSaveButton, requiresCancelButton: true, saveAction: saveAction) { [weak self] completion in
            self?.topViewController.dismiss(animated: true, completion: {
                completion?()
            })
        }
        .environmentObject(viewModel)

        let controller = UINavigationController(rootViewController: UIHostingController(rootView: view))
        controller.isModalInPresentation = true
        controller.modalPresentationStyle = .formSheet
        self.topViewController.present(controller, animated: true, completion: nil)
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
        self.topViewController.present(controller, animated: true, completion: nil)
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

        default:
            // TODO: - handle other errors
            return
        }

        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach({ controller.addAction($0) })
        self.topViewController.present(controller, animated: true, completion: nil)
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
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func showTrashAttachmentQuestion(trashAction: @escaping () -> Void) {
        let controller = UIAlertController(title: L10n.ItemDetail.trashAttachment, message: L10n.ItemDetail.trashAttachmentQuestion, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.no, style: .default, handler: nil))
        controller.addAction(UIAlertAction(title: L10n.yes, style: .destructive, handler: { _ in
            trashAction()
        }))
        self.topViewController.present(controller, animated: true, completion: nil)
    }
}

extension DetailCoordinator: DetailCreatorEditCoordinatorDelegate {
    func showCreatorTypePicker(itemType: String, selected: String, picked: @escaping (String) -> Void) {
        let navigationController = self.topViewController as? UINavigationController

        let viewModel = CreatorTypePickerViewModelCreator.create(itemType: itemType, selected: selected,
                                                                 schemaController: self.controllers.schemaController)
        let view = SinglePickerView(requiresSaveButton: false, requiresCancelButton: false, saveAction: picked) { [weak navigationController] completion in
            navigationController?.popViewController(animated: true)
            completion?()
        }
        .environmentObject(viewModel)

        let controller = UIHostingController(rootView: view)
        navigationController?.pushViewController(controller, animated: true)
    }
}

extension DetailCoordinator: DetailNoteEditorCoordinatorDelegate {
    func pushTagPicker(libraryId: LibraryIdentifier, selected: Set<String>, picked: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage, let navigationController = self.topViewController as? UINavigationController else { return }

        let state = TagPickerState(libraryId: libraryId, selectedTags: selected)
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: picked)

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
}

extension DetailCoordinator: DetailCitationBibliographyExportCoordinatorDelegate {
    func cancel() {
        self.topViewController.presentingViewController?.dismiss(animated: true, completion: nil)
    }
}

#if PDFENABLED

extension DetailCoordinator: DetailPdfCoordinatorDelegate {
    func showColorPicker(selected: String?, sender: UIButton, save: @escaping (String) -> Void) {
        let view = ColorPickerView(selected: selected, selectionAction: { [weak self] color in
            save(color)
            self?.topViewController.dismiss(animated: true, completion: nil)
        })
        let controller = UIHostingController(rootView: view)
        controller.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        controller.popoverPresentationController?.sourceView = sender
        controller.preferredContentSize = CGSize(width: 322, height: 74)
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func showAnnotationPopover(viewModel: ViewModel<PDFReaderActionHandler>, sourceRect: CGRect, popoverDelegate: UIPopoverPresentationControllerDelegate) {
        if let coordinator = self.childCoordinators.last, coordinator is AnnotationPopoverCoordinator {
            return
        }

        let navigationController = UINavigationController()

        let coordinator = AnnotationPopoverCoordinator(navigationController: navigationController, controllers: self.controllers, viewModel: viewModel)
        coordinator.parentCoordinator = self
        self.childCoordinators.append(coordinator)
        coordinator.start(animated: false)

        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.sourceView = self.topViewController.view
            navigationController.popoverPresentationController?.sourceRect = sourceRect
            navigationController.popoverPresentationController?.permittedArrowDirections = [.left, .right]
            navigationController.popoverPresentationController?.delegate = popoverDelegate
        }
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }

    func showSearch(pdfController: PDFViewController, sender: UIBarButtonItem, result: @escaping (SearchResult) -> Void) {
        if let existing = self.pdfSearchController {
            existing.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
            existing.popoverPresentationController?.barButtonItem = sender
            self.topViewController.present(existing, animated: true, completion: nil)
            return
        }

        let viewController = PDFSearchViewController(controller: pdfController, searchSelected: result)
        viewController.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        viewController.popoverPresentationController?.barButtonItem = sender
        self.topViewController.present(viewController, animated: true, completion: nil)

        self.pdfSearchController = viewController
    }

    func share(url: URL, barButton: UIBarButtonItem) {
        self.share(item: url, source: .barButton(barButton))
    }

    func share(text: String, rect: CGRect, view: UIView) {
        self.share(item: text, source: .view(view, rect))
    }

    func lookup(text: String, rect: CGRect, view: UIView) {
        let controller = UIReferenceLibraryViewController(term: text)
        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.sourceView = view
        controller.popoverPresentationController?.sourceRect = rect
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func show(error: PdfDocumentExporter.Error) {
        let message: String
        switch error {
        case .filenameMissing:
            message = "Could not find attachment item."
        case .fileError:
            // TODO: - show storage error or unknown error
            message = "Could not create PDF file."
        case .pdfError:
            message = "Could not export PDF file."
        }

        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func showDeletedAlertForPdf(completion: @escaping (Bool) -> Void) {
        let controller = UIAlertController(title: L10n.Pdf.deletedTitle, message: L10n.Pdf.deletedMessage, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.yes, style: .default, handler: { _ in
            completion(false)
        }))
        controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { _ in
            completion(true)
            self.topViewController.dismiss(animated: true, completion: nil)
        }))
        self.topViewController.present(controller, animated: true, completion: nil)
    }

    func pdfDidDeinitialize() {
        self.pdfSearchController = nil
    }

    private func showAppearanceModePicker(for current: PDFReaderState.AppearanceMode, completed: @escaping (PDFReaderState.AppearanceMode) -> Void) {
        let models = [SinglePickerModel(id: "\(PDFReaderState.AppearanceMode.automatic.rawValue)", name: L10n.Pdf.Appearance.auto),
                      SinglePickerModel(id: "\(PDFReaderState.AppearanceMode.light.rawValue)", name: L10n.Pdf.Appearance.lightMode),
                      SinglePickerModel(id: "\(PDFReaderState.AppearanceMode.dark.rawValue)", name: L10n.Pdf.Appearance.darkMode)]
        let state = SinglePickerState(objects: models, selectedRow: "\(current.rawValue)")
        let viewModel = ViewModel(initialState: state, handler: SinglePickerActionHandler())
        self.presentPicker(viewModel: viewModel, requiresSaveButton: false, saveAction: { picked in
            guard let mode = UInt(picked).flatMap({ PDFReaderState.AppearanceMode(rawValue: $0) }) else { return }
            completed(mode)
        })
    }

    func showSettings(state: PDFSettingsState, sender: UIBarButtonItem, completion: @escaping (PDFReaderAction) -> Void) {
        let directionString = state.direction == .horizontal ? L10n.Pdf.ScrollDirection.horizontal : L10n.Pdf.ScrollDirection.vertical
        let transitionString = state.transition == .scrollContinuous ? L10n.Pdf.PageTransition.continuous : L10n.Pdf.PageTransition.jump
        let appearanceString: String
        switch state.appearanceMode {
        case .automatic:
            appearanceString = L10n.Pdf.Appearance.auto
        case .dark:
            appearanceString = L10n.Pdf.Appearance.darkMode
        case .light:
            appearanceString = L10n.Pdf.Appearance.lightMode
        }

        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.popoverPresentationController?.barButtonItem = sender
        controller.addAction(UIAlertAction(title: L10n.Pdf.Appearance.title(appearanceString), style: .default, handler: { [weak self] _ in
            self?.showAppearanceModePicker(for: state.appearanceMode, completed: { appearanceMode in
                completion(.changeAppearanceMode(appearanceMode))
            })
        }))
        controller.addAction(UIAlertAction(title: L10n.Pdf.PageTransition.title(transitionString), style: .default, handler: { _ in
            completion(.changeTransition(state.transition == .scrollContinuous ? .scrollPerSpread : .scrollContinuous))
        }))
        controller.addAction(UIAlertAction(title: L10n.Pdf.ScrollDirection.title(directionString), style: .default, handler: { _ in
            completion(.changeDirection(state.direction == .vertical ? .horizontal : .vertical))
        }))
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        self.topViewController.present(controller, animated: true, completion: nil)
    }
}

extension DetailCoordinator: DetailAnnotationsCoordinatorDelegate {
    func showCellOptions(for annotation: Annotation, sender: UIButton, saveAction: @escaping AnnotationEditSaveAction, deleteAction: @escaping AnnotationEditDeleteAction) {
        let state = AnnotationEditState(annotation: annotation)
        let handler = AnnotationEditActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationEditViewController(viewModel: viewModel, includeColorPicker: true, saveAction: saveAction, deleteAction: deleteAction)
        controller.coordinatorDelegate = self

        let navigationController = UINavigationController(rootViewController: controller)
        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .popover
            navigationController.popoverPresentationController?.sourceView = sender
            navigationController.popoverPresentationController?.permittedArrowDirections = .left
        }
        self.topViewController.present(navigationController, animated: true, completion: nil)
    }
}

extension DetailCoordinator: AnnotationEditCoordinatorDelegate {
    func showPageLabelEditor(label: String, updateSubsequentPages: Bool, saveAction: @escaping AnnotationPageLabelSaveAction) {
        let state = AnnotationPageLabelState(label: label, updateSubsequentPages: updateSubsequentPages)
        let handler = AnnotationPageLabelActionHandler()
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = AnnotationPageLabelViewController(viewModel: viewModel, saveAction: saveAction)
        (self.topViewController as? UINavigationController)?.pushViewController(controller, animated: true)
    }
}

#endif

extension URL {
    fileprivate var withHttpSchemeIfMissing: URL {
        if self.scheme == "http" || self.scheme == "https" {
            return self
        }

        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }
        components.scheme = "http"
        return components.url ?? self
    }
}
