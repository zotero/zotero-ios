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
    // Collection picker
    @IBOutlet private weak var collectionPickerStackContainer: UIView!
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
    // Progress
    @IBOutlet private weak var bottomProgressContainer: UIView!
    @IBOutlet private weak var bottomProgressActivityIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var bottomProgressLabel: UILabel!
    @IBOutlet private weak var failureLabel: UILabel!
    // Saving
    @IBOutlet private weak var savingContainer: UIView!
    @IBOutlet private weak var savingInnerContainer: UIView!

    // Variables
    private var translatorsController: TranslatorsController!
    private var dbStorage: DbStorage!
    private var fileStorage: FileStorageController!
    private var debugLogging: DebugLogging!
    private var schemaController: SchemaController!
    private var store: ExtensionStore!
    private var storeCancellable: AnyCancellable?
    private var viewIsVisible: Bool = true

    // Constants
    private static let toolbarTitleIdx = 1
    private static let childAttachmentLeftOffset: CGFloat = 16

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

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
        var size = self.stackView.systemLayoutSizeFitting(CGSize(width: 468.0, height: .greatestFiniteMagnitude))
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

    @IBAction private func showItemPicker() {
        guard let items = self.store.state.itemPicker?.items else { return }

        let view = ItemPickerView(data: items) { [weak self] picked in
            self?.store.pickItem(picked)
            self?.navigationController?.popViewController(animated: true)
        }

        let size = CGSize(width: 468.0, height: 500.0)

        let controller = UIHostingController(rootView: view)
        controller.preferredContentSize = size
        self.navigationController?.preferredContentSize = size
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

        let size = CGSize(width: 468.0, height: 500.0)

        let controller = UIHostingController(rootView: view)
        controller.preferredContentSize = size
        self.navigationController?.preferredContentSize = size
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
        self.updateItemsUi(for: state.title, items: state.items, attachmentState: state.attachmentState)
        self.update(attachmentState: state.attachmentState, itemState: state.itemPicker)
        self.update(collectionPicker: state.collectionPicker)
        self.update(itemPicker: state.itemPicker)

        if self.viewIsVisible {
            self.updatePreferredContentSize()
        }
    }

    private func update(attachmentState state: ExtensionStore.State.AttachmentState, itemState: ExtensionStore.State.ItemPicker?) {
        self.updateNavigationItems(for: state)
        self.updateBottomProgress(for: state, itemState: itemState)
    }

    private func updateItemsUi(for title: String?, items: ExtensionStore.State.ProcessedAttachment?, attachmentState: ExtensionStore.State.AttachmentState) {
        guard let items = items else {
            self.translationContainer.isHidden = true
            return
        }

        self.translationContainer.isHidden = false

        switch items {
        case .item(let item):
            self.itemContainer.isHidden = false
            self.attachmentContainer.isHidden = true

            let titleKey = self.schemaController.titleKey(for: item.rawType)
            let itemTitle = titleKey.flatMap({ item.fields[$0] }) ?? title

            self.itemIcon.image = UIImage(named: ItemTypes.iconName(for: item.rawType, contentType: nil))
            self.itemTitleLabel.text = itemTitle

        case .itemWithAttachment(let item, let attachment, let file):
            self.itemContainer.isHidden = false
            self.attachmentContainer.isHidden = false

            let titleKey = self.schemaController.titleKey(for: item.rawType)
            let itemTitle = titleKey.flatMap({ item.fields[$0] }) ?? title

            self.itemIcon.image = UIImage(named: ItemTypes.iconName(for: item.rawType, contentType: nil))
            self.itemTitleLabel.text = itemTitle
            self.attachmentContainerLeft.constant = ShareViewController.childAttachmentLeftOffset
            self.attachmentIcon.set(state: .stateFrom(contentType: .file(file: file, filename: "", location: .local, linkType: .imported), progress: nil, error: attachmentState.error), style: .detail)
            self.attachmentTitleLabel.text = (attachment["title"] as? String) ?? title

        case .localFile(let file):
            self.itemContainer.isHidden = true
            self.attachmentContainer.isHidden = false

            self.attachmentContainerLeft.constant = 0
            self.attachmentIcon.set(state: .stateFrom(contentType: .file(file: file, filename: "", location: .local, linkType: .imported), progress: nil, error: nil), style: .detail)
            
            self.attachmentTitleLabel.text = file.name
        }

        switch attachmentState {
        case .downloading(let progress):
            self.attachmentProgressView.isHidden = false
            self.attachmentProgressView.progress = CGFloat(progress)

            self.attachmentIcon.alpha = 0.5
            self.attachmentTitleLabel.alpha = 0.5
        default:
            if !self.attachmentContainer.isHidden {
                self.attachmentProgressView.isHidden = true
                self.attachmentIcon.alpha = 1
                self.attachmentTitleLabel.alpha = 1
            }
        }
    }

    private func updateNavigationItems(for state: ExtensionStore.State.AttachmentState) {
        switch state {
        case .submitting:
            // Disable "Upload" and "Cancel" button if the upload is being prepared so that the user can't start it multiple times or cancel
            self.navigationItem.leftBarButtonItem?.isEnabled = false
            self.navigationItem.rightBarButtonItem?.isEnabled = false
        case .decoding, .downloading, .translating: // In-progress states should have "Upload" button disabled
            self.navigationItem.leftBarButtonItem?.isEnabled = true
            self.navigationItem.rightBarButtonItem?.isEnabled = false
        case .processed:
            // Enable "Upload" button if translation and file download (if any) are finished
            self.navigationItem.leftBarButtonItem?.isEnabled = true
            self.navigationItem.rightBarButtonItem?.isEnabled = true
        case .failed(let error):
            // Enable "Upload" button for non-fatal errors, where the user can still at least save the web as webpage item
            self.navigationItem.leftBarButtonItem?.isEnabled = true
            self.navigationItem.rightBarButtonItem?.isEnabled = !error.isFatal
        case .done: break // The extension will close
        }
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

            self.hideSavingOverlay()
            self.collectionPickerStackContainer.isHidden = error.isFatal
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
        } else {
            switch error {
            case .downloadedFileNotPdf: break
            default:
                message += "\n" + L10n.Errors.Shareext.failedAdditional
            }
            self.failureLabel.textColor = .darkGray
        }

        self.failureLabel.text = message
        self.failureLabel.isHidden = false
    }

    private func errorMessage(for error: ExtensionStore.State.AttachmentState.Error) -> String? {
        switch error {
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
                return L10n.Errors.Shareext.translationFailed
            case .cantFindBaseFile, .webExtractionMissingJs: // should never happen
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
        case .downloadedFileNotPdf:
            return nil
        }
    }

    private func update(itemPicker state: ExtensionStore.State.ItemPicker?) {
        self.itemPickerStackContainer.isHidden = state == nil
        
        guard let state = state else { return }

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

    private func update(collectionPicker state: ExtensionStore.State.CollectionPicker) {
        switch state {
        case .picked(let library, let collection):
            self.createCollectionRowsIfNeeded()

            for view in self.collectionPickerStackView.arrangedSubviews {
                guard let row = view as? CollectionRowView else { continue }
                row.change(selected: false)
            }

            if let idx = self.store.state.collectionLibraries.firstIndex(where: { $0.collection == collection && $0.library == library }),
               idx < self.collectionPickerStackView.arrangedSubviews.count,
               let row = self.collectionPickerStackView.arrangedSubviews[idx] as? CollectionRowView {
                // If collection is visible, just select appropriate row
                row.change(selected: true)
                return
            }

            // If collection is not visible, change first row, which shows currently selected collection.
            guard let row = self.collectionPickerStackView.arrangedSubviews.first as? CollectionRowView else { return }
            row.setup(with: (collection?.name ?? library.name), isSelected: true)

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

    private func createCollectionRowsIfNeeded() {
        guard self.collectionPickerLoadingContainer != nil else { return }

        // These are unnecessary anymore
        self.collectionPickerLoadingContainer?.removeFromSuperview()
        self.collectionPickerFailureLabel?.removeFromSuperview()
        // Show pick other button
        self.collectionPickerPickOtherButton.isHidden = false

        // Create rows for selected collection/library and recent collections
        for (idx, collectionLibrary) in self.store.state.collectionLibraries.enumerated() {
            guard let row = Bundle.main.loadNibNamed("CollectionRowView", owner: nil, options: nil)?.first as? CollectionRowView else { continue }
            row.setup(with: (collectionLibrary.collection?.name ?? collectionLibrary.library.name), isSelected: false)
            row.tapAction = { [weak self] in
                self?.store.set(collection: collectionLibrary.collection, library: collectionLibrary.library)
            }
            self.collectionPickerStackView.insertArrangedSubview(row, at: idx)
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
         self.itemPickerContainer].forEach { container in
            container!.layer.cornerRadius = 8
            container!.layer.masksToBounds = true
            container?.backgroundColor = Asset.Colors.defaultCellBackground.color
        }

        self.collectionPickerFailureLabel?.text = L10n.Shareext.syncError
        self.collectionPickerLoadingLabel.text = L10n.Shareext.loadingCollections
        self.collectionPickerPickOtherButton.setTitle(L10n.Shareext.collectionOther, for: .normal)
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
        let dbStorage = RealmDbStorage(config: Database.mainConfiguration(url: dbUrl))
        let translatorsController = TranslatorsController(apiClient: apiClient,
                                                          indexStorage: RealmDbStorage(config: Database.translatorConfiguration),
                                                          fileStorage: fileStorage)

        apiClient.set(authToken: session.apiToken)
        translatorsController.updateFromRepo(type: .shareExtension)

        self.dbStorage = dbStorage
        self.translatorsController = translatorsController
        self.store = self.createStore(for: session.userId, dbStorage: dbStorage, apiClient: apiClient, schemaController: schemaController,
                                      fileStorage: fileStorage, translatorsController: translatorsController)
    }

    private func createStore(for userId: Int, dbStorage: DbStorage, apiClient: ApiClient, schemaController: SchemaController,
                             fileStorage: FileStorage, translatorsController: TranslatorsController) -> ExtensionStore {
        let dateParser = DateParser()

        let uploadProcessor = BackgroundUploadProcessor(apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage)
        let backgroundUploader = BackgroundUploader(uploadProcessor: uploadProcessor, schemaVersion: schemaController.version)
        let syncController = SyncController(userId: userId,
                                            apiClient: apiClient,
                                            dbStorage: dbStorage,
                                            fileStorage: fileStorage,
                                            schemaController: schemaController,
                                            dateParser: dateParser,
                                            backgroundUploader: backgroundUploader,
                                            syncDelayIntervals: DelayIntervals.sync,
                                            conflictDelays: DelayIntervals.conflict)

        return ExtensionStore(webView: self.webView,
                              apiClient: apiClient,
                              backgroundUploader: backgroundUploader,
                              dbStorage: dbStorage,
                              schemaController: schemaController,
                              dateParser: dateParser,
                              fileStorage: fileStorage,
                              syncController: syncController,
                              translatorsController: translatorsController)
    }
}
