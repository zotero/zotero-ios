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

import CocoaLumberjack

class ShareViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var collectionPickerContainer: UIView!
    @IBOutlet private weak var collectionPickerLabel: UILabel!
    @IBOutlet private weak var collectionPickerChevron: UIImageView!
    @IBOutlet private weak var collectionPickerIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var itemPickerTitleLabel: UILabel!
    @IBOutlet private weak var itemPickerContainer: UIView!
    @IBOutlet private weak var itemPickerLabel: UILabel!
    @IBOutlet private weak var itemPickerChevron: UIImageView!
    @IBOutlet private weak var itemPickerButton: UIButton!
    @IBOutlet private weak var toolbarContainer: UIView!
    @IBOutlet private weak var toolbarLabel: UILabel!
    @IBOutlet private weak var toolbarProgressView: UIProgressView!
    @IBOutlet private weak var preparingContainer: UIView!
    @IBOutlet private weak var notLoggedInOverlay: UIView!
    @IBOutlet private weak var webView: WKWebView!
    // Variables
    private var dbStorage: DbStorage!
    private var store: ExtensionStore!
    private var storeCancellable: AnyCancellable?
    // Constants
    private static let toolbarTitleIdx = 1

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

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
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func update(to state: ExtensionStore.State) {
        var rightButtonEnabled: Bool
        // Enable "Upload" button if translation and file download (if any) are finished
        switch state.translation {
        case .downloaded, .translated:
            rightButtonEnabled = true
        default:
            rightButtonEnabled = false
        }

        if let state = state.submission {
            self.updateUploadState(state)
            if state == .preparing {
                // Disable "Upload" button if the upload is being prepared so that the user can't start it multiple times
                rightButtonEnabled = false
                // Disable "Cancel" button so that the user doesn't close the extension at this point.
                self.navigationItem.leftBarButtonItem?.isEnabled = false
            }
        }

        self.navigationItem.rightBarButtonItem?.isEnabled = rightButtonEnabled
        self.updateToolbar(to: state.translation)
        self.updateCollectionPicker(to: state.collectionPicker)
        self.navigationItem.title = state.title
        self.updateItemPicker(to: state.itemPicker)
    }

    private func updateUploadState(_ state: ExtensionStore.State.Submission) {
        switch state {
        case .ready:
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        case .preparing:
            self.prepareForUpload()
        case .error(let error):
            self.hidePreparingIndicator()

            switch error {
            case .fileMissing:
                self.showError(message: "Could not find file to upload")
            case .unknown:
                self.showError(message: "Unknown error. Can't upload file.")
            case .expired: break
            }
        }
    }

    private func prepareForUpload() {
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
        self.itemPickerContainer.isHidden = state == nil
        self.itemPickerTitleLabel.isHidden = self.itemPickerContainer.isHidden
        
        guard let state = state else { return }

        if let text = state.picked {
            self.itemPickerLabel.text = text
            self.itemPickerLabel.textColor = .gray
            self.itemPickerChevron.tintColor = .gray
            self.itemPickerButton.isEnabled = false
        } else {
            self.itemPickerLabel.text = "Pick an item"
            self.itemPickerLabel.textColor = .systemBlue
            self.itemPickerChevron.tintColor = .systemBlue
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
            self.collectionPickerLabel.textColor = .link
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

    private func updateToolbar(to state: ExtensionStore.State.Translation) {
        switch state {
        case .translating:
            if self.toolbarContainer.isHidden {
                self.showToolbar()
            }
            self.setToolbarData(title: "Translating", progress: nil)

        case .translated, .downloaded:
            if !self.toolbarContainer.isHidden {
                self.hideToolbar()
            }

        case .downloading(_, _, let progress):
            self.setToolbarData(title: "Downloading", progress: progress)

        case .failed(let error):
            switch error {
            case .cantLoadSchema:
                self.setToolbarData(title: "Could not update schema", progress: nil)
            case .cantLoadWebData:
                self.setToolbarData(title: "Could not load web data", progress: nil)
            case .downloadFailed:
                self.setToolbarData(title: "Could not download attachment file", progress: nil)
            case .itemsNotFound:
                self.setToolbarData(title: "Translator couldn't find any items", progress: nil)
            case .parseError:
                self.setToolbarData(title: "Translator response couldn't be parsed", progress: nil)
            case .webViewError(let error):
                switch error {
                case .jsError(let string):
                    self.setToolbarData(title: "Translation failed: \(string)", progress: nil)
                case .cantFindBaseFile: // should never happen
                    self.setToolbarData(title: "Translator missing", progress: nil)
                }
            case .unknown, .expired:
                self.setToolbarData(title: "Unknown error", progress: nil)
            }

        }
    }

    private func showToolbar() {
        self.toolbarContainer.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.toolbarContainer.alpha = 1
        }
    }

    private func hideToolbar() {
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
        let cancel = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(ShareViewController.cancel))
        self.navigationItem.leftBarButtonItem = cancel

        if loggedIn {
            let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(ShareViewController.done))
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
        self.dbStorage = RealmDbStorage(url: Files.dbFile(for: session.userId).createUrl())
        self.store = self.createStore(for: session.userId, authToken: session.apiToken, dbStorage: self.dbStorage)
    }

    private func createStore(for userId: Int, authToken: String, dbStorage: DbStorage) -> ExtensionStore {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Zotero-API-Version": ApiConstants.version.description]
        configuration.sharedContainerIdentifier = AppGroup.identifier
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: configuration)
        apiClient.set(authToken: authToken)

        let fileStorage = FileStorageController()
        let schemaController = SchemaController()

        let uploadProcessor = BackgroundUploadProcessor(apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage)
        let backgroundUploader = BackgroundUploader(uploadProcessor: uploadProcessor)

        let syncHandler = SyncActionHandlerController(userId: userId,
                                                      apiClient: apiClient,
                                                      dbStorage: dbStorage,
                                                      fileStorage: fileStorage,
                                                      schemaController: schemaController,
                                                      backgroundUploader: backgroundUploader,
                                                      syncDelayIntervals: DelayIntervals.sync)
        let syncController = SyncController(userId: userId, handler: syncHandler,
                                            conflictDelays: DelayIntervals.conflict)

        return ExtensionStore(webView: self.webView,
                              apiClient: apiClient,
                              backgroundUploader: backgroundUploader,
                              dbStorage: dbStorage,
                              schemaController: schemaController,
                              fileStorage: fileStorage,
                              syncController: syncController,
                              syncActionHandler: syncHandler)
    }
}
