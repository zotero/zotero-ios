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

class ShareViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var collectionPickerContainer: UIView!
    @IBOutlet private weak var collectionPickerLabel: UILabel!
    @IBOutlet private weak var collectionPickerChevron: UIImageView!
    @IBOutlet private weak var collectionPickerIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var itemPickerStackContainer: UIView!
    @IBOutlet private weak var itemPickerTitleLabel: UILabel!
    @IBOutlet private weak var itemPickerContainer: UIView!
    @IBOutlet private weak var itemPickerLabel: UILabel!
    @IBOutlet private weak var itemPickerChevron: UIImageView!
    @IBOutlet private weak var itemPickerButton: UIButton!
    @IBOutlet private weak var translationErrorLabel: UILabel!
    @IBOutlet private weak var toolbarContainer: UIView!
    @IBOutlet private weak var toolbarLabel: UILabel!
    @IBOutlet private weak var toolbarProgressView: UIProgressView!
    @IBOutlet private weak var preparingContainer: UIView!
    @IBOutlet private weak var notLoggedInOverlay: UIView!
    @IBOutlet private weak var webView: WKWebView!
    // Variables
    private var translatorsController: TranslatorsController!
    private var dbStorage: DbStorage!
    private var debugLogging: DebugLogging!
    private var store: ExtensionStore!
    private var storeCancellable: AnyCancellable?
    // Constants
    private static let toolbarTitleIdx = 1

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        DDLog.add(DDOSLogger.sharedInstance)

        self.debugLogging = DebugLogging(fileStorage: FileStorageController())
        self.debugLogging.startLoggingOnLaunchIfNeeded()

        let session = SessionController(secureStorage: KeychainSecureStorage()).sessionData

        self.setupNavbar(loggedIn: (session != nil))

        if let session = session {
            self.setupControllers(with: session)
        } else {
            self.setupNotLoggedInOverlay()
            return
        }

        // Setup UI
        self.setupPickers()
        self.setupPreparingIndicator()

        // Setup observing
        self.storeCancellable = self.store?.$state.receive(on: DispatchQueue.main)
                                                  .sink { [weak self] state in
                                                      self?.update(to: state)
                                                  }

        // Load initial data
        if let extensionItem = self.extensionContext?.inputItems.first as? NSExtensionItem {
            self.store?.start(with: extensionItem)
        } else {
            // TODO: - Show error about missing file
        }
    }

    // MARK: - Actions

    @IBAction private func showItemPicker() {
        guard let items = self.store.state.itemPicker?.items else { return }

        let view = ItemPickerView(data: items) { [weak self] picked in
            self?.store.pickItem(picked)
            self?.navigationController?.popViewController(animated: true)
        }

        let controller = UIHostingController(rootView: view)
        self.navigationController?.pushViewController(controller, animated: true)
    }

    @IBAction private func showCollectionPicker() {
        guard let dbStorage = self.dbStorage else { return }

        let store = AllCollectionPickerStore(dbStorage: dbStorage)
        let view = AllCollectionPickerView { [weak self] collection, library in
            self?.store?.set(collection: collection, library: library)
            self?.navigationController?.popViewController(animated: true)
        }
        .environmentObject(store)

        let controller = UIHostingController(rootView: view)
        self.navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func done() {
        self.store?.submit()
    }

    @objc private func cancel() {
        self.store.cancel()
        self.debugLogging.storeLogs { [unowned self] in
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func update(to state: ExtensionStore.State) {
        self.navigationItem.title = state.title
        self.setupNavigationItems(for: state.translation, submission: state.submission)
        self.updateCollectionPicker(to: state.collectionPicker)
        self.updateItemPicker(to: state.itemPicker)
        self.updateSubmission(to: state.submission)
        self.updateToolbar(translation: state.translation, submission: state.submission)

        if case .failed = state.translation {
            self.translationErrorLabel.isHidden = false
        } else {
            self.translationErrorLabel.isHidden = true
        }
    }

    private func setupNavigationItems(for translation: ExtensionStore.State.Translation, submission: ExtensionStore.State.Submission?) {
        if submission == .preparing {
            // Disable "Upload" and "Cancel" button if the upload is being prepared so that the user can't start it multiple times or cancel
            self.navigationItem.leftBarButtonItem?.isEnabled = false
            self.navigationItem.rightBarButtonItem?.isEnabled = false
            return
        }

        self.navigationItem.leftBarButtonItem?.isEnabled = true

        switch translation {
        case .downloaded, .translated:
            // Enable "Upload" button if translation and file download (if any) are finished
            self.navigationItem.rightBarButtonItem?.isEnabled = true
        case .failed(let error):
            switch error {
            case .cantLoadWebData, .cantLoadSchema: // These are fatal errors which can't even save as webpage item
                self.navigationItem.rightBarButtonItem?.isEnabled = false
            default: // Other errors are non-fatal and can still save web as webpage item at least
                self.navigationItem.rightBarButtonItem?.isEnabled = true
            }
        default: // Other states are in-progress states and should have "upload" button disabled
            self.navigationItem.rightBarButtonItem?.isEnabled = false
        }
    }

    private func updateSubmission(to state: ExtensionStore.State.Submission?) {
        guard let state = state else { return }

        switch state {
        case .ready:
            self.debugLogging.storeLogs { [unowned self] in
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        case .preparing:
            self.showPreparingIndicator()
        case .error:
            self.hidePreparingIndicator()
        }
    }

    private func showPreparingIndicator() {
        self.preparingContainer.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.preparingContainer.alpha = 1
        }
    }

    private func hidePreparingIndicator() {
        UIView.animate(withDuration: 0.2, animations: {
            self.preparingContainer.alpha = 0
        }, completion: { finished in
            if finished {
                self.preparingContainer.isHidden = true
            }
        })
    }

    private func updateItemPicker(to state: ExtensionStore.State.ItemPicker?) {
        self.itemPickerStackContainer.isHidden = state == nil
        
        guard let state = state else { return }

        if let text = state.picked {
            self.itemPickerLabel.text = text
            self.itemPickerLabel.textColor = .gray
            self.itemPickerChevron.tintColor = .gray
            self.itemPickerButton.isEnabled = false
        } else {
            self.itemPickerLabel.text = L10n.Shareext.Translation.itemSelection
            self.itemPickerLabel.textColor = Asset.Colors.zoteroBlue.color
            self.itemPickerChevron.tintColor = Asset.Colors.zoteroBlue.color
            self.itemPickerButton.isEnabled = true
        }
    }

    private func updateCollectionPicker(to state: ExtensionStore.State.CollectionPicker) {
        switch state {
        case .picked(let library, let collection):
            let title = collection?.name ?? library.name
            self.collectionPickerIndicator.stopAnimating()
            self.collectionPickerChevron.isHidden = false
            self.collectionPickerLabel.text = title
            self.collectionPickerLabel.textColor = Asset.Colors.zoteroBlue.color
        case .loading:
            self.collectionPickerIndicator.isHidden = false
            self.collectionPickerIndicator.startAnimating()
            self.collectionPickerChevron.isHidden = true
            self.collectionPickerLabel.text = "Loading collections"
            self.collectionPickerLabel.textColor = .gray
        case .failed:
            self.collectionPickerIndicator.stopAnimating()
            self.collectionPickerChevron.isHidden = true
            self.collectionPickerLabel.text = "Can't sync collections"
            self.collectionPickerLabel.textColor = .red
        }
    }

    private func updateToolbar(translation: ExtensionStore.State.Translation, submission: ExtensionStore.State.Submission?) {
        if let submission = submission, case let .error(error) = submission {
            self.showToolbarIfNeeded()

            switch error {
            case .fileMissing:
                self.showError(message: "Could not find file to upload.")
            case .missingBackgroundUploader:
                self.showError(message: "Background uploader not initialized.")
            case .unknown, .expired:
                self.showError(message: "Unknown error. Can't upload file.")
            }
            return
        }

        switch translation {
        case .starting:
            self.setToolbarData(title: L10n.Shareext.Translation.start, progress: nil)
            self.showToolbarIfNeeded()

        case .translated, .downloaded:
            self.hideToolbarIfNeeded()

        case .translating(let message):
            self.setToolbarData(title: message, progress: nil)

        case .downloading(_, _, let progress):
            self.setToolbarData(title: L10n.Shareext.Translation.downloading, progress: progress)

        case .failed(let error):
            switch error {
            case .cantLoadSchema:
                self.showError(message: "Could not update schema. Close and try again.")
            case .cantLoadWebData:
                self.showError(message: "Could not load web data. Close and try again.")
            case .downloadFailed:
                self.showError(message: "Could not download attachment file")
            case .itemsNotFound:
                self.showError(message: "Translator couldn't find any items")
            case .parseError:
                self.showError(message: "Translator response couldn't be parsed")
            case .webViewError(let error):
                switch error {
                case .incompatibleItem:
                    self.showError(message: "Translated item contains incompatible data")
                case .javascriptCallMissingResult:
                    self.showError(message: "Javascript call failed")
                case .noSuccessfulTranslators:
                    self.showError(message: "Transation failed")
                case .cantFindBaseFile: // should never happen
                    self.showError(message: "Translator missing")
                }
            case .unknown, .expired:
                self.showError(message: L10n.Shareext.Translation.unknown)
            }
        }
    }

    private func showToolbarIfNeeded() {
        guard self.toolbarContainer.isHidden else { return }
        self.toolbarContainer.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.toolbarContainer.alpha = 1
        }
    }

    private func hideToolbarIfNeeded() {
        guard !self.toolbarContainer.isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: {
            self.toolbarContainer.alpha = 0
        }, completion: { finished in
            if finished {
                self.toolbarContainer.isHidden = true
            }
        })
    }

    private func setToolbarData(title: String, progress: Float?) {
        self.toolbarLabel.text = title
        if let progress = progress {
            self.toolbarProgressView.progress = progress
            self.toolbarProgressView.isHidden = false
        } else {
            self.toolbarProgressView.isHidden = true
        }
    }

    private func showError(message: String) {
        self.setToolbarData(title: "Error: \(message)", progress: nil)
    }

    // MARK: - Setups

    private func setupPickers() {
        [self.collectionPickerContainer,
         self.itemPickerContainer].forEach { container in
            container!.layer.cornerRadius = 8
            container!.layer.masksToBounds = true
            container!.layer.borderWidth = 1
            container!.layer.borderColor = UIColor.opaqueSeparator.cgColor
        }
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

    private func setupPreparingIndicator() {
        self.preparingContainer.layer.cornerRadius = 8
        self.preparingContainer.layer.masksToBounds = true
    }

    private func setupNotLoggedInOverlay() {
        self.notLoggedInOverlay.isHidden = false
    }

    private func setupControllers(with session: SessionData) {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description]
        configuration.sharedContainerIdentifier = AppGroup.identifier
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: configuration)
        let fileStorage = FileStorageController()
        let dbUrl = Files.dbFile(for: session.userId).createUrl()
        let dbStorage = RealmDbStorage(config: Database.mainConfiguration(url: dbUrl))
        let translatorsController = TranslatorsController(apiClient: apiClient,
                                                          indexStorage: RealmDbStorage(config: Database.translatorConfiguration),
                                                          fileStorage: fileStorage)

        apiClient.set(authToken: session.apiToken)
        translatorsController.updateFromRepo()

        self.dbStorage = dbStorage
        self.translatorsController = translatorsController
        self.store = self.createStore(for: session.userId, dbStorage: dbStorage,
                                      apiClient: apiClient, fileStorage: fileStorage,
                                      translatorsController: translatorsController)
    }

    private func createStore(for userId: Int, dbStorage: DbStorage, apiClient: ApiClient,
                             fileStorage: FileStorage, translatorsController: TranslatorsController) -> ExtensionStore {
        let schemaController = SchemaController()
        let dateParser = DateParser()

        let uploadProcessor = BackgroundUploadProcessor(apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage)
        let backgroundUploader = BackgroundUploader(uploadProcessor: uploadProcessor)
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
