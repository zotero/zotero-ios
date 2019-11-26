//
//  ShareViewController.swift
//  ZShare
//
//  Created by Michal Rentka on 21/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Social
import UIKit

class ShareViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var pickerContainer: UIView!
    @IBOutlet private weak var pickerLabel: UILabel!
    @IBOutlet private weak var pickerChevron: UIImageView!
    @IBOutlet private weak var pickerIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var toolbarContainer: UIView!
    @IBOutlet private weak var toolbarLabel: UILabel!
    @IBOutlet private weak var toolbarProgressView: UIProgressView!
    // Variables
    private var store: ExtensionStore!
    private var storeCancellable: AnyCancellable?
    // Constants
    private static let toolbarTitleIdx = 1

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavbar()
        self.setupPicker()
        self.setupStore()

        self.store.loadDocument()
    }

    // MARK: - Actions

    private func update(to state: ExtensionStore.State) {
        self.navigationItem.rightBarButtonItem?.isEnabled = state.downloadState == nil
        self.updateToolbar(to: state.downloadState)
        self.updatePicker(to: state.pickerState)
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

    @objc private func done() {
        // TODO: - start file upload
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    @objc private func cancel() {
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    // MARK: - Setups

    private func setupStore() {
        guard let context = self.extensionContext else { return }

        let userId = Defaults.shared.userId
        let apiClient = ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, headers: ["Zotero-API-Version": ApiConstants.version.description])
        let dbStorage = RealmDbStorage(url: Files.dbFile(for: userId).createUrl())
        let schemaController = SchemaController(apiClient: apiClient, userDefaults: UserDefaults.zotero)
        let syncHandler = SyncActionHandlerController(userId: userId,
                                                      apiClient: apiClient,
                                                      dbStorage: dbStorage,
                                                      fileStorage: FileStorageController(),
                                                      schemaController: schemaController,
                                                      syncDelayIntervals: DelayIntervals.sync)
        let syncController = SyncController(userId: userId, handler: syncHandler,
                                            conflictDelays: DelayIntervals.conflict)

        self.store = ExtensionStore(context: context, apiClient: apiClient, syncController: syncController)

        self.storeCancellable = self.store.$state.receive(on: DispatchQueue.main)
                                                 .sink { [weak self] state in
                                                    self?.update(to: state)
                                                 }
    }

    private func setupPicker() {
        self.pickerContainer.layer.cornerRadius = 8
        self.pickerContainer.layer.masksToBounds = true
        self.pickerContainer.layer.borderWidth = 1
        self.pickerContainer.layer.borderColor = UIColor.opaqueSeparator.cgColor
    }

    private func setupNavbar() {
        let cancel = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(ShareViewController.cancel))
        self.navigationItem.leftBarButtonItem = cancel
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(ShareViewController.done))
        done.isEnabled = false
        self.navigationItem.rightBarButtonItem = done
    }
}
