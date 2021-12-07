//
//  ShareViewController.swift
//  ZShare
//
//  Created by Michal Rentka on 21/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Social
import SwiftUI
import UIKit
import WebKit

import CocoaLumberjackSwift

final class ShareViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var webView: WKWebView!
    @IBOutlet private weak var stackView: UIStackView!
    // Title
    @IBOutlet private weak var translationContainer: UIView!
    @IBOutlet private weak var itemContainer: UIStackView!
    @IBOutlet private weak var itemIcon: UIImageView!
    @IBOutlet private weak var itemTitleLabel: UILabel!
    @IBOutlet private weak var attachmentContainer: UIView!
    @IBOutlet private weak var attachmentContainerLeft: NSLayoutConstraint!
    @IBOutlet private weak var attachmentIcon: FileAttachmentView!
    @IBOutlet private weak var attachmentTitleLabel: UILabel!
    @IBOutlet private weak var attachmentProgressView: CircularProgressView!
    @IBOutlet private weak var attachmentActivityIndicator: UIActivityIndicatorView!
    // Collection picker
    @IBOutlet private weak var collectionPickerStackContainer: UIView!
    @IBOutlet private weak var collectionPickerTitleLabel: UILabel!
    @IBOutlet private weak var collectionPickerContainer: UIView!
    @IBOutlet private weak var collectionPickerStackView: UIStackView!
    @IBOutlet private weak var collectionPickerLoadingContainer: UIView?
    @IBOutlet private weak var collectionPickerLoadingLabel: UILabel!
    @IBOutlet private weak var collectionPickerPickOtherButton: RightButton!
    @IBOutlet private weak var collectionPickerFailureLabel: UILabel?
    // Item picker
    @IBOutlet private weak var itemPickerStackContainer: UIView!
    @IBOutlet private weak var itemPickerTitleLabel: UILabel!
    @IBOutlet private weak var itemPickerContainer: UIView!
    @IBOutlet private weak var itemPickerLabel: UILabel!
    @IBOutlet private weak var itemPickerChevron: UIImageView!
    @IBOutlet private weak var itemPickerButton: UIButton!
    // Tag picker
    @IBOutlet private weak var tagPickerStackContainer: UIView!
    @IBOutlet private weak var tagPickerTitleLabel: UILabel!
    @IBOutlet private weak var tagPickerContainer: UIView!
    @IBOutlet private weak var tagPickerStackView: UIStackView!
    @IBOutlet private weak var tagPickerAddButton: RightButton!
    // Progress
    @IBOutlet private weak var bottomProgressContainer: UIView!
    @IBOutlet private weak var bottomProgressActivityIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var bottomProgressLabel: UILabel!
    @IBOutlet private weak var failureLabel: UILabel!
    // Saving
    @IBOutlet private weak var savingContainer: UIView!
    @IBOutlet private weak var savingInnerContainer: UIView!

    // Variables
    private var translatorsController: TranslatorsAndStylesController!
    private var dbStorage: DbStorage!
    private var bundledDataStorage: DbStorage!
    private var fileStorage: FileStorageController!
    private var debugLogging: DebugLogging!
    private var schemaController: SchemaController!
    private var secureStorage: KeychainSecureStorage!
    private var store: ExtensionStore!
    private var storeCancellable: AnyCancellable?
    private var viewIsVisible: Bool = true

    // Constants
    private static let toolbarTitleIdx = 1
    private static let childAttachmentLeftOffset: CGFloat = 16
    private static let maxCollectionCount = 5
    private static let width: CGFloat = 468
    private static let pickerSize = CGSize(width: width, height: 500.0)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        DDLogInfo("View loaded")

        DDLog.add(DDOSLogger.sharedInstance)

        self.fileStorage = FileStorageController()

        self.schemaController = SchemaController()
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description,
                                               "Zotero-Schema-Version": self.schemaController.version]
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.timeoutIntervalForRequest = ApiConstants.requestTimeout
        configuration.timeoutIntervalForResource = ApiConstants.resourceTimeout
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: configuration)

        self.debugLogging = DebugLogging(apiClient: apiClient, fileStorage: self.fileStorage)
        self.debugLogging.startLoggingOnLaunchIfNeeded()

        let session = SessionController(secureStorage: KeychainSecureStorage(), defaults: Defaults.shared).sessionData

        self.setupNavbar(loggedIn: (session != nil))

        if let session = session {
            self.setupControllers(with: session, apiClient: apiClient, schemaController: self.schemaController)
        } else {
            self.showInitialError(message: L10n.Errors.Shareext.loggedOut)
            return
        }

        DDLogInfo("Controllers initialized")

        // Setup UI
        self.setupPickers()
        self.setupSavingOverlay()
        self.attachmentIcon.set(backgroundColor: .white)

        // Setup observing
        self.storeCancellable = self.store?.$state.receive(on: DispatchQueue.main)
                                                  .sink { [weak self] state in
                                                      self?.update(to: state)
                                                  }

        // Load initial data
        if let extensionItem = self.extensionContext?.inputItems.first as? NSExtensionItem {
            DDLogInfo("Load extension item")
            self.store?.start(with: extensionItem)
        } else {
            self.showInitialError(message: L10n.Errors.Shareext.cantLoadData)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.viewIsVisible = true
        self.updatePreferredContentSize()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.viewIsVisible = false
    }

    // MARK: - Actions

    private func updatePreferredContentSize() {
        var size = self.stackView.systemLayoutSizeFitting(CGSize(width: ShareViewController.width, height: .greatestFiniteMagnitude))
        size.height += 32

        self.preferredContentSize = size
        self.navigationController?.preferredContentSize = size
    }

    private func showInitialError(message: String) {
        self.navigationController?.view.alpha = 0.0

        let controller = UIAlertController(title: L10n.error, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }))
        self.present(controller, animated: false, completion: nil)
    }

    @IBAction private func showTagPicker() {
        guard let dbStorage = self.dbStorage else { return }

        let state = TagPickerState(libraryId: self.store.state.selectedLibraryId, selectedTags: Set(self.store.state.tags.map({ $0.name })))
        let handler = TagPickerActionHandler(dbStorage: dbStorage)
        let viewModel = ViewModel(initialState: state, handler: handler)
        let controller = TagPickerViewController(viewModel: viewModel, saveAction: { [weak self] tags in
            self?.store.set(tags: tags)
        })
        controller.preferredContentSize = ShareViewController.pickerSize

        self.navigationController?.preferredContentSize = ShareViewController.pickerSize
        self.navigationController?.pushViewController(controller, animated: true)
    }

    @IBAction private func showItemPicker() {
        guard let items = self.store.state.itemPicker?.items else { return }

        let view = ItemPickerView(data: items) { [weak self] picked in
            self?.store.pickItem(picked)
            self?.navigationController?.popViewController(animated: true)
        }

        let controller = UIHostingController(rootView: view)
        controller.preferredContentSize = ShareViewController.pickerSize
        self.navigationController?.preferredContentSize = ShareViewController.pickerSize
        self.navigationController?.pushViewController(controller, animated: true)
    }

    @IBAction private func showCollectionPicker() {
        guard let dbStorage = self.dbStorage else { return }

        let store = AllCollectionPickerStore(selectedCollectionId: self.store.state.selectedCollectionId, selectedLibraryId: self.store.state.selectedLibraryId, dbStorage: dbStorage)
        let view = AllCollectionPickerView { [weak self] collection, library in
            self?.store?.set(collection: collection, library: library)
            self?.navigationController?.popViewController(animated: true)
        }
        .environmentObject(store)

        let controller = UIHostingController(rootView: view)
        controller.preferredContentSize = ShareViewController.pickerSize
        self.navigationController?.preferredContentSize = ShareViewController.pickerSize
        self.navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func done() {
        self.store?.submit()
    }

    @objc private func cancel() {
        self.store?.cancel()
        self.debugLogging.storeLogs { [unowned self] in
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func update(to state: ExtensionStore.State) {
        self.log(attachmentState: state.attachmentState, itemState: state.itemPicker)
        self.updateItemsUi(for: state.title, items: state.items, attachmentState: state.attachmentState)
        self.update(attachmentState: state.attachmentState, itemState: state.itemPicker)
        self.update(collectionPicker: state.collectionPicker, recents: state.recents)
        self.update(itemPicker: state.itemPicker, items: state.items)
        self.updateTagPicker(with: state.tags)

        if self.viewIsVisible {
            self.updatePreferredContentSize()
        }
    }

    private func log(attachmentState: ExtensionStore.State.AttachmentState, itemState: ExtensionStore.State.ItemPicker?) {
        switch attachmentState {
        case .decoding:
            DDLogInfo("State: decoding")
        case .done:
            DDLogInfo("State: done")
        case .downloading(let progress):
            DDLogInfo("State: downloading \(progress)")
        case .failed(let error):
            DDLogInfo("State: failed with \(error)")
        case .processed:
            DDLogInfo("State: processed")
        case .submitting:
            DDLogInfo("State: submitting")
        case .translating(let name):
            DDLogInfo("State: translating with \(name)")
        }

        if let state = itemState {
            if let picked = state.picked {
                DDLogInfo("State: picked item \(picked)")
            } else {
                DDLogInfo("State: loaded \(state.items.count) items")
            }
        }
    }

    private func update(attachmentState state: ExtensionStore.State.AttachmentState, itemState: ExtensionStore.State.ItemPicker?) {
        self.updateNavigationItems(for: state)
        self.updateBottomProgress(for: state, itemState: itemState)
    }

    private func updateItemsUi(for title: String?, items: ExtensionStore.State.ProcessedAttachment?, attachmentState: ExtensionStore.State.AttachmentState) {
        self.translationContainer.isHidden = false

        guard let items = items else {
            guard !attachmentState.translationInProgress, let title = title else {
                self.translationContainer.isHidden = true
                return
            }

            self.setItem(title: title, image: UIImage(named: ItemTypes.iconName(for: ItemTypes.webpage, contentType: nil)))

            return
        }

        switch items {
        case .item(let item):
            let titleKey = self.schemaController.titleKey(for: item.rawType)
            let itemTitle = titleKey.flatMap({ item.fields[$0] }) ?? title ?? ""
            let image = UIImage(named: ItemTypes.iconName(for: item.rawType, contentType: nil))
            self.setItem(title: itemTitle, image: image)

        case .itemWithAttachment(let item, let attachment, let file):
            self.itemContainer.isHidden = false
            self.attachmentContainer.isHidden = false

            let titleKey = self.schemaController.titleKey(for: item.rawType)
            let itemTitle = titleKey.flatMap({ item.fields[$0] }) ?? title

            self.itemIcon.image = UIImage(named: ItemTypes.iconName(for: item.rawType, contentType: nil))
            self.itemTitleLabel.text = itemTitle
            self.attachmentContainerLeft.constant = ShareViewController.childAttachmentLeftOffset
            self.attachmentIcon.set(state: .stateFrom(type: .file(filename: "", contentType: file.mimeType, location: .local, linkType: .importedFile), progress: nil, error: attachmentState.error), style: .detail)
            self.attachmentTitleLabel.text = (attachment["title"] as? String) ?? title

        case .localFile(let file, let filename):
            self.itemContainer.isHidden = true
            self.attachmentContainer.isHidden = false

            self.attachmentContainerLeft.constant = 0
            self.attachmentIcon.set(state: .stateFrom(type: .file(filename: "", contentType: file.mimeType, location: .local, linkType: .importedFile), progress: nil, error: nil), style: .detail)
            
            self.attachmentTitleLabel.text = filename
        }

        switch attachmentState {
        case .downloading(let progress):
            self.attachmentProgressView.isHidden = progress == 0
            self.attachmentActivityIndicator.isHidden = progress > 0
            self.attachmentProgressView.progress = CGFloat(progress)
            if progress == 0 && !self.attachmentActivityIndicator.isAnimating {
                self.attachmentActivityIndicator.startAnimating()
            }

            self.attachmentIcon.alpha = 0.5
            self.attachmentTitleLabel.alpha = 0.5
        default:
            if !self.attachmentContainer.isHidden {
                self.attachmentProgressView.isHidden = true
                if self.attachmentActivityIndicator.isAnimating {
                    self.attachmentActivityIndicator.stopAnimating()
                }
                self.attachmentActivityIndicator.isHidden = true
                self.attachmentIcon.alpha = 1
                self.attachmentTitleLabel.alpha = 1
            }
        }
    }

    private func setItem(title: String, image: UIImage?) {
        self.itemContainer.isHidden = false
        self.attachmentContainer.isHidden = true
        self.itemIcon.image = image
        self.itemTitleLabel.text = title
    }

    private func updateNavigationItems(for state: ExtensionStore.State.AttachmentState) {
        if case .quotaLimit = state.error {
            self.navigationItem.leftBarButtonItem = nil
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(ShareViewController.cancel))
            return
        }

        self.navigationItem.leftBarButtonItem?.isEnabled = state.isCancellable
        self.navigationItem.rightBarButtonItem?.isEnabled = state.isSubmittable
    }

    private func updateBottomProgress(for state: ExtensionStore.State.AttachmentState, itemState: ExtensionStore.State.ItemPicker?) {
        if let state = itemState, state.picked == nil {
            // Don't show progress bar when waiting for item pick
            self.bottomProgressContainer.isHidden = true
            return
        }

        let message: String?
        let showActivityIndicator: Bool

        switch state {
        case .decoding:
            message = L10n.Shareext.decodingAttachment
            showActivityIndicator = true

        case .processed:
            message = nil
            showActivityIndicator = false

        case .translating(let _message):
            message = _message
            showActivityIndicator = true

        case .downloading:
            message = nil
            showActivityIndicator = true

        case .submitting:
            message = nil
            showActivityIndicator = false
            self.showSavingOverlay()

        case .failed(let error):
            message = nil
            showActivityIndicator = false

            let hidePickers = error.isFatalOrQuota

            self.hideSavingOverlay()
            self.collectionPickerStackContainer.isHidden = hidePickers
            self.tagPickerStackContainer.isHidden = hidePickers
            self.itemPickerStackContainer.isHidden = true
            self.show(error: error)

        case .done:
            self.debugLogging.storeLogs { [unowned self] in
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
            return
        }

        self.bottomProgressContainer.isHidden = message == nil
        if let text = message {
            self.bottomProgressLabel.text = text.uppercased()
            self.bottomProgressActivityIndicator.isHidden = !showActivityIndicator
        }
    }

    private func show(error: ExtensionStore.State.AttachmentState.Error) {
        guard var message = self.errorMessage(for: error) else {
            self.failureLabel.isHidden = true
            return
        }

        if error.isFatal {
            self.failureLabel.textColor = .red
            self.failureLabel.textAlignment = .center
        } else {
            switch error {
            case .downloadedFileNotPdf, .apiFailure:
                self.failureLabel.textAlignment = .center
            case .quotaLimit:
                self.failureLabel.textAlignment = .left
            default:
                message += "\n" + L10n.Errors.Shareext.failedAdditional
                self.failureLabel.textAlignment = .center
            }
            self.failureLabel.textColor = .darkGray
        }

        self.failureLabel.text = message
        self.failureLabel.isHidden = false
    }

    private func errorMessage(for error: ExtensionStore.State.AttachmentState.Error) -> String? {
        switch error {
        case .webDavNotVerified:
            return L10n.Errors.Shareext.webdavNotVerified
        case .cantLoadSchema:
            return L10n.Errors.Shareext.cantLoadSchema
        case .cantLoadWebData:
            return L10n.Errors.Shareext.cantLoadData
        case .downloadFailed:
            return L10n.Errors.Shareext.downloadFailed
        case .itemsNotFound:
            return L10n.Errors.Shareext.itemsNotFound
        case .parseError:
            return L10n.Errors.Shareext.parsingError
        case .schemaError:
            return L10n.Errors.Shareext.schemaError
        case .webViewError(let error):
            switch error {
            case .incompatibleItem:
                return L10n.Errors.Shareext.incompatibleItem
            case .javascriptCallMissingResult:
                return L10n.Errors.Shareext.javascriptFailed
            case .noSuccessfulTranslators:
                return nil
            case .cantFindFile, .webExtractionMissingJs, .webViewMissing: // should never happen
                return L10n.Errors.Shareext.missingBaseFiles
            case .webExtractionMissingData:
                return L10n.Errors.Shareext.responseMissingData
            }
        case .unknown, .expired:
            return L10n.Errors.Shareext.unknown
        case .fileMissing:
            return L10n.Errors.Shareext.missingFile
        case .missingBackgroundUploader:
            return L10n.Errors.Shareext.backgroundUploaderFailure
        case .apiFailure:
            return L10n.Errors.Shareext.apiError
        case .quotaLimit(let libraryId):
            switch libraryId {
            case .custom:
                return L10n.Errors.Shareext.personalQuotaReached

            case .group(let groupId):
                let groupName = (try? self.dbStorage.createCoordinator().perform(request: ReadGroupDbRequest(identifier: groupId)))?.name
                return L10n.Errors.Shareext.groupQuotaReached(groupName ?? "\(groupId)")
            }
        case .downloadedFileNotPdf:
            return nil
        }
    }

    private func update(itemPicker state: ExtensionStore.State.ItemPicker?, items: ExtensionStore.State.ProcessedAttachment?) {
        guard let state = state, items == nil else {
            self.itemPickerStackContainer.isHidden = true
            return
        }

        self.itemPickerStackContainer.isHidden = false

        if let text = state.picked {
            self.itemPickerLabel.text = text
            self.itemPickerLabel.textColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
                return traitCollection.userInterfaceStyle == .light ? .darkText : .white
            })
            self.itemPickerChevron.isHidden = true
            self.itemPickerButton.isEnabled = false
        } else {
            self.itemPickerLabel.text = L10n.Shareext.Translation.itemSelection
            self.itemPickerLabel.textColor = Asset.Colors.zoteroBlue.color
            self.itemPickerChevron.tintColor = Asset.Colors.zoteroBlue.color
            self.itemPickerChevron.isHidden = false
            self.itemPickerButton.isEnabled = true
        }
    }

    private func update(collectionPicker state: ExtensionStore.State.CollectionPicker, recents: [RecentData]) {
        switch state {
        case .picked(let library, let collection):
            if self.collectionPickerLoadingContainer != nil {
                // These are unnecessary anymore
                self.collectionPickerLoadingContainer?.removeFromSuperview()
                self.collectionPickerFailureLabel?.removeFromSuperview()
                // Show pick other button
                self.collectionPickerPickOtherButton.isHidden = false
            }

            let count = min(ShareViewController.maxCollectionCount, recents.count)
            self.updateRowCount(in: self.collectionPickerStackView, hasAddButton: true, to: count,
                                createRow: { Bundle.main.loadNibNamed("CollectionRowView", owner: nil, options: nil)?.first as? CollectionRowView })
            self.updateCollections(to: recents, pickedCollection: collection, library: library)

        case .loading:
            self.collectionPickerLoadingContainer?.isHidden = false
            self.collectionPickerFailureLabel?.isHidden = true
            self.collectionPickerPickOtherButton.isHidden = true

        case .failed:
            self.collectionPickerLoadingContainer?.isHidden = true
            self.collectionPickerFailureLabel?.isHidden = false
            self.collectionPickerPickOtherButton.isHidden = true
        }
    }

    private func updateCollections(to recents: [RecentData], pickedCollection collection: Collection?, library: Library) {
        for (idx, view) in self.collectionPickerStackView.arrangedSubviews.enumerated() {
            guard let row = view as? CollectionRowView else { continue }
            let recent = recents[idx]
            let selected = recent.collection?.identifier == collection?.identifier && recent.library.identifier == library.identifier
            row.setup(with: (recent.collection?.name ?? recent.library.name), isSelected: selected)
            row.tapAction = { [weak self] in
                self?.store.setFromRecent(collection: recent.collection, library: recent.library)
            }
        }
    }

    private func updateTagPicker(with tags: [Tag]) {
        self.updateRowCount(in: self.tagPickerStackView, hasAddButton: true, to: tags.count, createRow: { Bundle.main.loadNibNamed("TagRow", owner: nil, options: nil)?.first as? TagRow })

        for (idx, view) in self.tagPickerStackView.arrangedSubviews.enumerated() {
            guard let row = view as? TagRow else { continue }
            row.setup(with: tags[idx])
        }
    }

    private func updateRowCount(in stackView: UIStackView, hasAddButton: Bool, to count: Int, createRow: () -> UIView?) {
        let visibleCount = stackView.arrangedSubviews.count - (hasAddButton ? 1 : 0)

        guard visibleCount != count else { return }

        if visibleCount > count {
            for _ in 0..<(visibleCount - count) {
                guard let view = stackView.arrangedSubviews.first else { break }
                view.removeFromSuperview()
            }
            return
        }

        for _ in 0..<(count - visibleCount) {
            guard let row = createRow() else { continue }
            stackView.insertArrangedSubview(row, at: 0)
        }
    }

    private func showSavingOverlay() {
        guard self.savingContainer.isHidden else { return }

        self.savingContainer.alpha = 0
        self.savingContainer.isHidden = false

        UIView.animate(withDuration: 0.2) {
            self.savingContainer.alpha = 1
        }
    }

    private func hideSavingOverlay() {
        guard !self.savingContainer.isHidden else { return }

        UIView.animate(withDuration: 0.2, animations: {
            self.savingContainer.alpha = 0
        }, completion: { finished in
            guard finished else { return }
            self.savingContainer.isHidden = true
        })
    }

    // MARK: - Setups

    private func setupSavingOverlay() {
        self.savingContainer.isHidden = true
        self.savingInnerContainer.layer.cornerRadius = 8
        self.savingInnerContainer.layer.masksToBounds = true
    }

    private func setupPickers() {
        [self.translationContainer,
         self.collectionPickerContainer,
         self.itemPickerContainer,
         self.tagPickerContainer].forEach { container in
            container!.layer.cornerRadius = 8
            container!.layer.masksToBounds = true
            container?.backgroundColor = Asset.Colors.defaultCellBackground.color
        }

        self.collectionPickerTitleLabel.text = L10n.Shareext.collectionTitle.uppercased()
        self.collectionPickerFailureLabel?.text = L10n.Shareext.syncError
        self.collectionPickerLoadingLabel.text = L10n.Shareext.loadingCollections
        self.collectionPickerPickOtherButton.setTitle(L10n.Shareext.collectionOther, for: .normal)
        self.itemPickerTitleLabel.text = L10n.Shareext.itemTitle.uppercased()
        self.tagPickerTitleLabel.text = L10n.Shareext.tagsTitle.uppercased()
        self.tagPickerAddButton.setTitle(L10n.add, for: .normal)
    }

    private func setupNavbar(loggedIn: Bool) {
        self.navigationController?.navigationBar.tintColor = Asset.Colors.zoteroBlue.color

        let cancel = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(ShareViewController.cancel))
        self.navigationItem.leftBarButtonItem = cancel

        if loggedIn {
            let done = UIBarButtonItem(title: L10n.Shareext.save, style: .done, target: self, action: #selector(ShareViewController.done))
            done.isEnabled = false
            self.navigationItem.rightBarButtonItem = done
        }
    }

    private func setupControllers(with session: SessionData, apiClient: ApiClient, schemaController: SchemaController) {
        let fileStorage = FileStorageController()
        let dbUrl = Files.dbFile(for: session.userId).createUrl()
        let dbStorage = RealmDbStorage(config: Database.mainConfiguration(url: dbUrl, fileStorage: fileStorage))
        let configuration = Database.bundledDataConfiguration(fileStorage: fileStorage)
        let bundledDataStorage = RealmDbStorage(config: configuration)
        let translatorsController = TranslatorsAndStylesController(apiClient: apiClient, bundledDataStorage: bundledDataStorage, fileStorage: fileStorage)
        let secureStorage = KeychainSecureStorage()
        let webDavController = WebDavControllerImpl(dbStorage: dbStorage, fileStorage: fileStorage, sessionStorage: SecureWebDavSessionStorage(secureStorage: secureStorage))

        apiClient.set(authToken: ("Bearer " + session.apiToken), for: .zotero)
        translatorsController.updateFromRepo(type: .shareExtension)

        self.dbStorage = dbStorage
        self.bundledDataStorage = bundledDataStorage
        self.translatorsController = translatorsController
        self.secureStorage = secureStorage
        self.store = self.createStore(for: session.userId, dbStorage: dbStorage, apiClient: apiClient, schemaController: schemaController,
                                      fileStorage: fileStorage, webDavController: webDavController, translatorsController: translatorsController)
    }

    private func createStore(for userId: Int, dbStorage: DbStorage, apiClient: ApiClient, schemaController: SchemaController, fileStorage: FileStorage, webDavController: WebDavController,
                             translatorsController: TranslatorsAndStylesController) -> ExtensionStore {
        let dateParser = DateParser()

        let uploadProcessor = BackgroundUploadProcessor(apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage, webDavController: webDavController)
        let backgroundUploader = BackgroundUploader(uploadProcessor: uploadProcessor, schemaVersion: schemaController.version)
        let syncController = SyncController(userId: userId,
                                            apiClient: apiClient,
                                            dbStorage: dbStorage,
                                            fileStorage: fileStorage,
                                            schemaController: schemaController,
                                            dateParser: dateParser,
                                            backgroundUploader: backgroundUploader,
                                            webDavController: webDavController,
                                            syncDelayIntervals: DelayIntervals.sync,
                                            conflictDelays: DelayIntervals.conflict)

        return ExtensionStore(webView: self.webView,
                              apiClient: apiClient,
                              backgroundUploader: backgroundUploader,
                              dbStorage: dbStorage,
                              schemaController: schemaController,
                              webDavController: webDavController,
                              dateParser: dateParser,
                              fileStorage: fileStorage,
                              syncController: syncController,
                              translatorsController: translatorsController)
    }
}
