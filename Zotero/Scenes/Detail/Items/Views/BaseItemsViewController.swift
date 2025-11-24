//
//  BaseItemsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
import RxSwift
import WebKit
import ZIPFoundation

class BaseItemsViewController: UIViewController {
    enum RightBarButtonItem: Int {
        case select
        case done
        case selectAll
        case deselectAll
        case add
        case emptyTrash
    }

    private static let itemBatchingLimit = 150
    unowned let controllers: Controllers
    let disposeBag: DisposeBag

    weak var tableView: UITableView!
    var toolbarController: ItemsToolbarController?
    var refreshController: SyncRefreshController?
    var handler: ItemsTableViewHandler?
    weak var tagFilterDelegate: ItemsTagFilterDelegate?
    weak var coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)?
    private let debugReaderQueue: DispatchQueue?
    private var readerURL: URL?

    init(controllers: Controllers, coordinatorDelegate: (DetailItemsCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)) {
        self.controllers = controllers
        self.coordinatorDelegate = coordinatorDelegate
        disposeBag = DisposeBag()
        #if DEBUG
        debugReaderQueue = DispatchQueue(label: "org.zotero.DebugReaderQueue", qos: .userInteractive)
        #endif
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        createTableView()
        navigationController?.toolbar.barTintColor = UIColor(dynamicProvider: { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .black : .white
        })
        setupTitle()
        setupSearchBar()
        if let scheduler = controllers.userControllers?.syncScheduler {
            refreshController = SyncRefreshController(libraryId: library.identifier, view: tableView, syncScheduler: scheduler)
        }
        startObservingSyncProgress()

        func createTableView() {
            let tableView = UITableView()
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)

            NSLayoutConstraint.activate([
                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])

            self.tableView = tableView
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 18, *) {
            // In some cases in iOS 18, where the horizontal size class changes, e.g. when switching to a scene with a PDF reader and dismissing it,
            // this error is logged multiple times, and leaves the search bar in stack placement, but overlapping the table view:
            // "UINavigationBar has changed horizontal size class without updating search bar to new placement. Fixing, but delegate searchBarPlacement callbacks have been skipped."
            // Setting "navigationItem.preferredSearchBarPlacement = .inline" explicitly, would even freeze the app and crash it.
            // Instead, hiding and showing the navigation bar momentarily when the view will appear, fixes the issue.
            navigationController?.setNavigationBarHidden(true, animated: false)
            navigationController?.setNavigationBarHidden(false, animated: false)
        }
        toolbarController?.willAppear()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // willTransition(to:with:) seems to not be not called for all transitions, so instead traitCollectionDidChange(_:) is used w/ a short animation block.
        guard UIDevice.current.userInterfaceIdiom == .pad, traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass else { return }
        setupTitle()
        UIView.animate(withDuration: 0.1) {
            self.toolbarController?.reloadToolbarItems(for: self.toolbarData)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key, key.characters == "f", key.modifierFlags.contains(.command) else {
            super.pressesBegan(presses, with: event)
            return
        }
        navigationItem.searchController?.searchBar.becomeFirstResponder()
    }

    // MARK: - Actions

    func updateTagFilter(filters: [ItemsFilter], collectionId: CollectionIdentifier, libraryId: LibraryIdentifier) {
        tagFilterDelegate?.itemsDidChange(filters: filters, collectionId: collection.identifier, libraryId: library.identifier)
    }

    /// Starts observing progress of sync. The sync progress needs to be observed to optimize `UITableView` reloads for big syncs of items in current library.
    private func startObservingSyncProgress() {
        guard let syncController = controllers.userControllers?.syncScheduler.syncController else { return }

        syncController.progressObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] progress in
                guard let self else { return }
                switch progress {
                case .object(let object, let progress, _, let libraryId):
                    if library.identifier == libraryId && object == .item {
                        if let progress = progress, progress.total >= BaseItemsViewController.itemBatchingLimit {
                            // Disable batched reloads when there are a lot of upcoming updates. Batched updates kill tableView performance when many are performed in short period of time.
                            handler?.disableReloadAnimations()
                        }
                    } else {
                        // Re-enable batched reloads when items are synced.
                        handler?.enableReloadAnimations()
                    }

                default:
                    // Re-enable batched reloads when items are synced.
                    handler?.enableReloadAnimations()
                }
            })
            .disposed(by: disposeBag)
    }

    func process(downloadUpdate update: AttachmentDownloader.Update, toOpen: String?, downloader: AttachmentDownloader?, dataUpdate: (ItemsState.DownloadBatchData?) -> Void, attachmentWillOpen: (AttachmentDownloader.Update) -> Void) {
        if let downloader {
            let batchData = ItemsState.DownloadBatchData(batchData: downloader.batchData)
            dataUpdate(batchData)
        }

        guard !update.kind.isProgress && toOpen == update.key else { return }

        attachmentWillOpen(update)

        switch update.kind {
        case .ready:
            coordinatorDelegate?.showAttachment(key: update.key, parentKey: update.parentKey, libraryId: update.libraryId, readerURL: readerURL)
            readerURL = nil

        case .failed(let error):
            coordinatorDelegate?.showAttachmentError(error)

        case .progress, .cancelled:
            break
        }
    }

    private enum DebugReaderError: LocalizedError {
        case invalidInput
        
        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Please enter a valid commit hash."
            }
        }
    }

    func processDebugReaderAction(tapAction: ItemsTableViewHandler.TapAction, completion: @escaping (() -> Void)) {
        guard case .attachment = tapAction else { return }
        let alertController = UIAlertController(title: "Debug Reader", message: "Enter reader commit hash", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "reader commit hash"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.keyboardType = .default
            textField.text = Defaults.shared.lastDebugReaderHash
        }
        alertController.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        alertController.addAction(UIAlertAction(title: L10n.ok, style: .default) { [weak self, weak alertController] _ in
            guard let self, let hash = alertController?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty else {
                showError(DebugReaderError.invalidInput)
                return
            }
            if let uuidString = Defaults.shared.debugReaderUUIDByHash[hash] {
                cache(uuidString: uuidString, for: hash)
                readerURL = FileData.directory(rootPath: Files.cachesRootPath, relativeComponents: ["Zotero", uuidString, "ios"]).createUrl()
                completion()
                return
            }
            guard let url = URL(string: "https://zotero-download.s3.amazonaws.com/ci/reader/\(hash).zip"), let debugReaderQueue else {
                cache(uuidString: nil, for: hash)
                showError(DebugReaderError.invalidInput)
                return
            }
            // TODO: destination should be cached if ok, and based on hash or random
            let temporaryDirectory = Files.temporaryDirectory
            let zipFile = FileData(rootPath: temporaryDirectory.rootPath, relativeComponents: temporaryDirectory.relativeComponents, name: hash, ext: "zip")
            let request = FileRequest(url: url, destination: zipFile)
            controllers.apiClient
                .download(request: request, queue: debugReaderQueue)
                .subscribe(onNext: { request in
                    request.resume()
                }, onError: { [weak self] error in
                    cache(uuidString: nil, for: hash)
                    guard let self else { return }
                    readerURL = nil
                    showError(error)
                }, onCompleted: { [weak self] in
                    guard let self else { return }
                    do {
                        let destinationURL = zipFile.createRelativeUrl()
                        try FileManager.default.unzipItem(at: zipFile.createUrl(), to: destinationURL)
                        try? controllers.fileStorage.remove(zipFile)
                        cache(uuidString: destinationURL.lastPathComponent, for: hash)
                        readerURL = destinationURL.appending(path: "ios")
                        DispatchQueue.main.async {
                            completion()
                        }
                    } catch {
                        cache(uuidString: nil, for: hash)
                        readerURL = nil
                        showError(error)
                    }
                })
                .disposed(by: disposeBag)
        })
        present(alertController, animated: true)

        func cache(uuidString: String?, for hash: String) {
            var debugReaderUUIDByHash = Defaults.shared.debugReaderUUIDByHash
            debugReaderUUIDByHash[hash] = uuidString
            Defaults.shared.debugReaderUUIDByHash = debugReaderUUIDByHash
            Defaults.shared.lastDebugReaderHash = (uuidString != nil) ? hash : nil
        }

        func showError(_ error: Error) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let alert = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L10n.ok, style: .cancel))
                present(alert, animated: true)
            }
        }
    }

    // MARK: - To override

    var library: Library {
        return Library(identifier: .custom(.myLibrary), name: "", metadataEditable: false, filesEditable: false)
    }
    
    var collection: Collection {
        return .init(custom: .all)
    }

    var toolbarData: ItemsToolbarController.Data {
        return .init(
            isEditing: false,
            selectedItems: [],
            filters: [],
            downloadBatchData: nil,
            remoteDownloadBatchData: nil,
            identifierLookupBatchData: ItemsState.IdentifierLookupBatchData(saved: 0, total: 0),
            itemCount: 0
        )
    }

    func search(for term: String) {}

    func tagSelectionDidChange(selected: Set<String>) {}

    func process(barButtonItemAction: RightBarButtonItem, sender: UIBarButtonItem) {}

    func downloadsFilterDidChange(enabled: Bool) {}

    // MARK: - Setups

    func setupTitle() {
        title = traitCollection.horizontalSizeClass == .compact ? collection.name : nil
    }

    private func setupSearchBar() {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchBar.placeholder = L10n.Items.searchTitle
        controller.searchBar.rx
            .text.observe(on: MainScheduler.instance)
            .skip(1)
            .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] text in
                self?.search(for: text ?? "")
            })
            .disposed(by: disposeBag)
        controller.obscuresBackgroundDuringPresentation = false
        controller.delegate = self
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.searchController = controller
    }

    func setupRightBarButtonItems(expectedItems: [RightBarButtonItem]) {
        let currentItems = (self.navigationItem.rightBarButtonItems ?? []).compactMap({ RightBarButtonItem(rawValue: $0.tag) })
        guard currentItems != expectedItems else { return }
        self.navigationItem.rightBarButtonItems = expectedItems.compactMap({ createRightBarButtonItem($0) }).reversed()

        func createRightBarButtonItem(_ type: RightBarButtonItem) -> UIBarButtonItem? {
            var image: UIImage?
            var title: String?
            let accessibilityLabel: String

            switch type {
            case .deselectAll:
                title = L10n.Items.deselectAll
                accessibilityLabel = L10n.Accessibility.Items.deselectAllItems

            case .selectAll:
                title = L10n.Items.selectAll
                accessibilityLabel = L10n.Accessibility.Items.selectAllItems

            case .done:
                title = L10n.done
                accessibilityLabel = L10n.done

            case .select:
                title = L10n.select
                accessibilityLabel = L10n.Accessibility.Items.selectItems

            case .add:
                image = UIImage(systemName: "plus")
                accessibilityLabel = L10n.Items.new
                title = L10n.Items.new

            case .emptyTrash:
                title = L10n.Collections.emptyTrash
                accessibilityLabel = L10n.Collections.emptyTrash
            }

            let primaryAction = UIAction { [weak self] action in
                guard let self, let sender = action.sender as? UIBarButtonItem else { return }
                process(barButtonItemAction: type, sender: sender)
            }
            let item = UIBarButtonItem(title: title, image: image, primaryAction: primaryAction)
            item.tag = type.rawValue
            item.accessibilityLabel = accessibilityLabel
            return item
        }
    }
}

extension BaseItemsViewController: FiltersDelegate {
    var currentLibrary: Library {
        return library
    }

    func tagOptionsDidChange() {
        updateTagFilter(filters: toolbarData.filters, collectionId: collection.identifier, libraryId: library.identifier)
    }
}

extension BaseItemsViewController: UISearchControllerDelegate {
    func didDismissSearchController(_ searchController: UISearchController) {
        search(for: "")
    }
}
