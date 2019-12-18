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
    @IBOutlet private weak var pickerContainer: UIView!
    @IBOutlet private weak var pickerLabel: UILabel!
    @IBOutlet private weak var pickerChevron: UIImageView!
    @IBOutlet private weak var pickerIndicator: UIActivityIndicatorView!
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
        self.setupPicker()
        self.setupPreparingIndicator()

        // Setup observing
        self.storeCancellable = self.store?.$state.receive(on: DispatchQueue.main)
                                                  .sink { [weak self] state in
                                                      self?.update(to: state)
                                                  }

        // Load initial data
        if let extensionItem = self.extensionContext?.inputItems.first as? NSExtensionItem {
            self.store?.loadCollections()
            self.store?.loadDocument(with: extensionItem)
        } else {
            // TODO: - Show error about missing file
        }
    }

    // MARK: - Actions

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
        self.store?.upload()
    }

    @objc private func cancel() {
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func update(to state: ExtensionStore.State) {
        var rightButtonEnabled = state.downloadState == nil

        if let state = state.uploadState {
            switch state {
            case .ready:
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                return
            case .preparing:
                self.prepareForUpload()
                rightButtonEnabled = false
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

        self.navigationItem.rightBarButtonItem?.isEnabled = rightButtonEnabled
        self.updateToolbar(to: state.downloadState)
        self.updatePicker(to: state.pickerState)
        self.navigationItem.title = state.title
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

    private func updatePicker(to state: ExtensionStore.State.PickerState) {
        switch state {
        case .picked(let library, let collection):
            let title = collection?.name ?? library.name
            self.pickerIndicator.stopAnimating()
            self.pickerChevron.isHidden = false
            self.pickerLabel.text = title
            self.pickerLabel.textColor = .link
        case .loading:
            self.pickerIndicator.isHidden = false
            self.pickerIndicator.startAnimating()
            self.pickerChevron.isHidden = true
            self.pickerLabel.text = "Loading collections"
            self.pickerLabel.textColor = .gray
        case .failed:
            self.pickerIndicator.stopAnimating()
            self.pickerChevron.isHidden = true
            self.pickerLabel.text = "Can't sync collections"
            self.pickerLabel.textColor = .red
        }
    }

    private func updateToolbar(to state: ExtensionStore.State.DownloadState?) {
        if let state = state {
            if self.toolbarContainer.isHidden {
                self.showToolbar()
            }

            switch state {
            case .loadingMetadata:
                self.setToolbarData(title: "Loading metadata", progress: nil)
            case .failed:
                self.setToolbarData(title: "Could not download file", progress: nil)
            case .progress(let progress):
                self.setToolbarData(title: "Downloading", progress: progress)
            }
        } else {
            if !self.toolbarContainer.isHidden {
                self.hideToolbar()
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

    private func setupPicker() {
        self.pickerContainer.layer.cornerRadius = 8
        self.pickerContainer.layer.masksToBounds = true
        self.pickerContainer.layer.borderWidth = 1
        self.pickerContainer.layer.borderColor = UIColor.opaqueSeparator.cgColor
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

        BackgroundApi.shared.client.set(authToken: authToken)

        let fileStorage = FileStorageController()
        let schemaController = SchemaController(apiClient: apiClient, userDefaults: UserDefaults.zotero)

        let syncHandler = SyncActionHandlerController(userId: userId,
                                                      apiClient: apiClient,
                                                      dbStorage: dbStorage,
                                                      fileStorage: fileStorage,
                                                      schemaController: schemaController,
                                                      syncDelayIntervals: DelayIntervals.sync)
        let syncController = SyncController(userId: userId, handler: syncHandler,
                                            conflictDelays: DelayIntervals.conflict)

        return ExtensionStore(webView: self.webView,
                              apiClient: apiClient,
                              backgroundApi: BackgroundApi.shared,
                              dbStorage: dbStorage,
                              schemaController: schemaController,
                              fileStorage: fileStorage,
                              syncController: syncController)
    }
}
