//
//  ItemDetailViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import MobileCoreServices
import UIKit
import SafariServices

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

private enum MainAttachmentButtonState {
    case ready(String)
    case downloading(String, CGFloat)
    case error(String, Error)
}

final class ItemDetailViewController: UIViewController {
    @IBOutlet private weak var collectionView: UICollectionView!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!

    private let viewModel: ViewModel<ItemDetailActionHandler>
    private let controllers: Controllers
    private let disposeBag: DisposeBag

    lazy private var collectionViewHandler: ItemDetailCollectionViewHandler = {
        let width = navigationController?.view.frame.width ?? view.frame.width
        let collectionViewHandler = ItemDetailCollectionViewHandler(
            collectionView: collectionView,
            containerWidth: width,
            viewModel: viewModel,
            fileDownloader: controllers.userControllers?.fileDownloader
        )
        collectionViewHandler.delegate = self
        collectionViewHandler.observer
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] action in
                self?.perform(collectionViewAction: action)
            })
            .disposed(by: disposeBag)
        return collectionViewHandler
    }()
    private var downloadingViaNavigationBar: Bool
    var key: String {
        return viewModel.state.key
    }

    weak var coordinatorDelegate: (DetailItemDetailCoordinatorDelegate & DetailNoteEditorCoordinatorDelegate)?

    init(viewModel: ViewModel<ItemDetailActionHandler>, controllers: Controllers) {
        self.viewModel = viewModel
        self.controllers = controllers
        downloadingViaNavigationBar = false
        disposeBag = DisposeBag()

        super.init(nibName: "ItemDetailViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setToolbarHidden(true, animated: false)
        collectionView.isHidden = true
        setupFileObservers()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: disposeBag)

        viewModel.process(action: .loadInitialData)

        func setupFileObservers() {
            NotificationCenter.default.rx
                .notification(.attachmentFileDeleted)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak viewModel] notification in
                    guard let viewModel, let notification = notification.object as? AttachmentFileDeletedNotification else { return }
                    viewModel.process(action: .updateAttachments(notification))
                })
                .disposed(by: disposeBag)

            NotificationCenter.default.rx
                .notification(UIApplication.willEnterForegroundNotification)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    // Need to reload data to current state before going back to foreground. iOS reloads the collection view when going to foreground with current snapshot. When
                    // editing text fields we don't update the snapshot (so that the cell is not reloaded while typing), so the edited fields are reset to previous state.
                    collectionViewHandler.reloadAll(to: viewModel.state, animated: false)
                })
                .disposed(by: disposeBag)

            controllers.userControllers?.fileDownloader.observable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] update in
                    guard let self else { return }
                    viewModel.process(action: .updateDownload(update))

                    guard viewModel.state.attachmentToOpen == update.key else { return }

                    switch update.kind {
                    case .ready:
                        viewModel.process(action: .attachmentOpened(update.key))
                        coordinatorDelegate?.showAttachment(key: update.key, parentKey: update.parentKey, libraryId: update.libraryId, readerURL: nil)

                    case .failed(let error):
                        viewModel.process(action: .attachmentOpened(update.key))
                        coordinatorDelegate?.showAttachmentError(error)

                    case .cancelled:
                        viewModel.process(action: .attachmentOpened(update.key))

                    case .progress:
                        return
                    }
                })
                .disposed(by: disposeBag)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let key = viewModel.state.preScrolledChildKey, collectionViewHandler.hasRows else { return }
        collectionViewHandler.scrollTo(itemKey: key, animated: false)
        viewModel.process(action: .clearPreScrolledItemKey)
    }

    deinit {
        DDLogInfo("ItemDetailViewController deinitialized")
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { _ in
            self.collectionView?.reloadData()
        }
    }

    // MARK: - Navigation

    private func perform(collectionViewAction: ItemDetailCollectionViewHandler.Action) {
        switch collectionViewAction {
        case .openCreatorEditor(let creator):
            coordinatorDelegate?.showCreatorEditor(for: creator, itemType: viewModel.state.data.type, saved: { [weak self] creator in
                self?.viewModel.process(action: .saveCreator(creator))
            }, deleted: { [weak self] id in
                self?.viewModel.process(action: .deleteCreator(id))
            })

        case .openCreatorCreation:
            coordinatorDelegate?.showCreatorCreation(for: viewModel.state.data.type, saved: { [weak self] creator in
                self?.viewModel.process(action: .saveCreator(creator))
            })

        case .openFilePicker:
            coordinatorDelegate?.showAttachmentPicker(save: { [weak self] urls in
                self?.viewModel.process(action: .addAttachments(urls))
            })

        case .openNoteEditor(let key):
            let library = viewModel.state.library
            var kind: NoteEditorKind = .itemCreation(parentKey: viewModel.state.key)
            var text: String = ""
            var tags: [Tag] = []
            var title: String?
            let parentTitleData = NoteEditorState.TitleData(type: viewModel.state.data.type, title: viewModel.state.data.title)
            if let note = viewModel.state.notes.first(where: { $0.key == key }) {
                if library.metadataEditable {
                    kind = .edit(key: note.key)
                } else {
                    kind = .readOnly(key: note.key)
                }
                text = note.text
                tags = note.tags
                title = note.title
            }
            coordinatorDelegate?.showNote(library: library, kind: kind, text: text, tags: tags, parentTitleData: parentTitleData, title: title) { [weak self] note in
                self?.viewModel.process(action: .processNoteSaveResult(note: note))
            }

        case .openTagPicker:
            coordinatorDelegate?.showTagPicker(libraryId: viewModel.state.library.identifier, selected: Set(viewModel.state.tags.map({ $0.id })), picked: { [weak self] tags in
                self?.viewModel.process(action: .setTags(tags))
            })

        case .openTypePicker:
            coordinatorDelegate?.showTypePicker(selected: viewModel.state.data.type, picked: { [weak self] type in
                self?.viewModel.process(action: .changeType(type))
            })

        case .openUrl(let string):
            guard let url = URL(string: string) else { return }
            coordinatorDelegate?.show(url: url)

        case .openDoi(let doi):
            guard let encoded = FieldKeys.Item.clean(doi: doi).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
            coordinatorDelegate?.show(doi: encoded)
            
        case .openCollection(let collection):
            coordinatorDelegate?.show(collection: collection, libraryId: viewModel.state.library.identifier)
        }
    }

    // MARK: - UI state

    /// Update UI based on new state.
    /// - parameter state: New state.
    private func update(to state: ItemDetailState) {
        if state.hideController {
            navigationController?.popViewController(animated: true)
            return
        }

        if let error = state.error {
            coordinatorDelegate?.show(error: error, viewModel: viewModel)
        }

        if state.changes.contains(.item) {
            // Another viewModel state update is made inside `subscribe(onNext:)`, to avoid reentrancy process it later on main queue.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !state.isEditing {
                    self.viewModel.process(action: .reloadData)
                    return
                }

                coordinatorDelegate?.showDataReloaded(completion: { [weak viewModel] in
                    viewModel?.process(action: .reloadData)
                })
            }
            return
        }

        if state.changes.contains(.reloadedData) {
            let wasHidden = collectionView.isHidden
            collectionView.isHidden = state.isLoadingData
            activityIndicator.isHidden = !state.isLoadingData

            setNavigationBarButtons(to: state)
            collectionViewHandler.recalculateTitleWidth(from: state.data)
            collectionViewHandler.reloadAll(to: state, animated: !wasHidden) { [weak self] in
                if wasHidden, case .creation = state.type {
                    self?.collectionViewHandler.focus(row: .title)
                }
            }

            return
        }

        guard !state.isLoadingData else { return }

        if state.changes.contains(.editing) || state.changes.contains(.type) {
            if state.changes.contains(.editing) {
                DDLogInfo("ItemDetailViewController: editing changed to \(state.isEditing)")
                setNavigationBarButtons(to: state)
            }
            if state.changes.contains(.type) {
                collectionViewHandler.recalculateTitleWidth(from: state.data)
            }
            collectionViewHandler.reloadAll(to: state, animated: true)
            return
        }

        if let reload = state.reload {
            switch reload {
            case .row(let row):
                collectionViewHandler.updateHeightAndScrollToUpdated(row: row, state: state)

            case .rows(let rows):
                collectionViewHandler.updateRows(rows: rows, state: state)

            case .section(let section):
                collectionViewHandler.reload(section: section, state: state, animated: true)
            }
            return
        }

        if let key = state.updateAttachmentKey {
            if state.mainAttachmentKey == key {
                // Update main-attachment related UI
                if controllers.userControllers?.fileDownloader.data(for: key, parentKey: viewModel.state.key, libraryId: state.library.identifier).progress == nil {
                    // Reset navbar download flag after download finishes
                    downloadingViaNavigationBar = false
                }

                setNavigationBarButtons(to: state)
            }

            if let attachment = state.attachments.first(where: { $0.key == key }) {
                collectionViewHandler.updateAttachment(with: attachment, isProcessing: state.backgroundProcessedItems.contains(key))
            }
        }

        if state.attachmentToOpen == nil {
            // Reset this flag in case the attachment has been opened already (happens when attachment was already downloaded, this is set to true when trying to open, but is not set to false when
            // it opens without download).
            downloadingViaNavigationBar = false
        }

        /// Updates navigation bar with appropriate buttons based on editing state.
        /// - parameter isEditing: Current editing state of tableView.
        func setNavigationBarButtons(to state: ItemDetailState) {
            guard !state.isLoadingData else { return }

            navigationItem.setHidesBackButton(state.isEditing, animated: false)

            if state.isEditing {
                let includesCancel: Bool
                switch state.type {
                case .preview:
                    includesCancel = false

                case .creation, .duplication:
                    includesCancel = true
                }
                setEditingNavigationBarButtons(isSaving: state.isSaving, includesCancel: includesCancel)
            } else {
                setPreviewNavigationBarButtons(attachmentButtonState: mainAttachmentButtonState(from: state), library: state.library)
            }

            func setEditingNavigationBarButtons(isSaving: Bool, includesCancel: Bool) {
                navigationItem.setHidesBackButton(true, animated: false)

                let saveButton: UIBarButtonItem
                if isSaving {
                    let indicator = UIActivityIndicatorView(style: .medium)
                    indicator.color = .gray
                    saveButton = UIBarButtonItem(customView: indicator)
                } else {
                    saveButton = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak viewModel] _ in
                        viewModel?.process(action: .endEditing)
                    })
                }
                navigationItem.rightBarButtonItem = saveButton

                guard includesCancel else { return }
                let cancelButton = UIBarButtonItem(primaryAction: UIAction(title: L10n.cancel) { [weak viewModel] _ in
                    viewModel?.process(action: .cancelEditing)
                })
                navigationItem.leftBarButtonItem = cancelButton
            }

            func setPreviewNavigationBarButtons(attachmentButtonState: MainAttachmentButtonState?, library: Library) {
                if let state = attachmentButtonState, case .downloading(_, let progress) = state,
                   let rightBarButtonItems = navigationItem.rightBarButtonItems,
                   rightBarButtonItems.count == 3,
                   let attachmentFileView = rightBarButtonItems[2].customView as? FileAttachmentView {
                    attachmentFileView.set(state: .progress(progress), style: .list)
                }

                navigationItem.setHidesBackButton(false, animated: false)

                var buttons: [UIBarButtonItem] = []
                if library.metadataEditable {
                    let button = UIBarButtonItem(primaryAction: UIAction(title: L10n.edit) { [weak viewModel] _ in
                        viewModel?.process(action: .startEditing)
                    })
                    buttons.append(button)
                }
                buttons.append(contentsOf: attachmentButtonItems(for: attachmentButtonState))

                navigationItem.rightBarButtonItems = buttons
                navigationItem.leftBarButtonItem = nil

                func attachmentButtonItems(for state: MainAttachmentButtonState?) -> [UIBarButtonItem] {
                    guard let state else { return [] }

                    let spacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
                    spacer.width = 16
                    var items: [UIBarButtonItem] = [spacer]

                    switch state {
                    case .ready(let key), .error(let key, _):
                        let button = UIBarButtonItem(primaryAction: UIAction(title: L10n.ItemDetail.viewPdf) { [weak self] _ in
                            guard let self else { return }
                            downloadingViaNavigationBar = true
                            viewModel.process(action: .openAttachment(key))
                        })
                        items.append(button)

                    case .downloading(_, let progress):
                        if downloadingViaNavigationBar {
                            let view = FileAttachmentView()
                            view.set(state: .progress(progress), style: .list)

                            items.append(UIBarButtonItem(customView: view))
                        } else {
                            let button = UIBarButtonItem(title: L10n.ItemDetail.viewPdf)
                            button.isEnabled = false
                            items.append(button)
                        }
                    }

                    return items
                }
            }

            func mainAttachmentButtonState(from state: ItemDetailState) -> MainAttachmentButtonState? {
                guard let key = state.mainAttachmentKey else { return nil }
                guard let downloader = controllers.userControllers?.fileDownloader else { return .ready(key) }

                let (progress, error) = downloader.data(for: key, parentKey: state.key, libraryId: state.library.identifier)

                if let error {
                    return .error(key, error)
                }
                if let progress {
                    return .downloading(key, progress)
                }
                return .ready(key)
            }
        }
    }
}

extension ItemDetailViewController: ItemDetailCollectionViewHandlerDelegate {
    func isDownloadingFromNavigationBar(for key: String) -> Bool {
        return downloadingViaNavigationBar && key == viewModel.state.mainAttachmentKey
    }
}

extension ItemDetailViewController: ConflictViewControllerReceiver {
    func shows(object: SyncObject, libraryId: LibraryIdentifier) -> String? {
        guard object == .item && libraryId == viewModel.state.library.identifier else { return nil }
        return viewModel.state.key
    }

    func canDeleteObject(completion: @escaping (Bool) -> Void) {
        coordinatorDelegate?.showDeletedAlertForItem(completion: completion)
    }
}

extension ItemDetailViewController: DetailCoordinatorAttachmentProvider {
    func attachment(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Attachment, UIPopoverPresentationControllerSourceItem)? {
        guard let index = viewModel.state.attachments.firstIndex(where: { $0.key == key && $0.libraryId == libraryId }) else { return nil }

        let attachment = viewModel.state.attachments[index]

        guard let section = collectionViewHandler.attachmentSectionIndex else {
            return (attachment, view)
        }

        let sourceItem = collectionViewHandler.sourceItemForCell(at: IndexPath(row: index, section: section))
        return (attachment, sourceItem)
    }
}
