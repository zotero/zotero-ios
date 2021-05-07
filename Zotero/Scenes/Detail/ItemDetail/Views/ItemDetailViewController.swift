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

fileprivate enum MainAttachmentButtonState {
    case ready(Int), downloading(Int, CGFloat), error(Int, Error)
}

final class ItemDetailViewController: UIViewController {
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!

    private let viewModel: ViewModel<ItemDetailActionHandler>
    private let controllers: Controllers
    private let disposeBag: DisposeBag

    private var tableViewHandler: ItemDetailTableViewHandler!
    private var downloadingViaNavigationBar: Bool
    private var didAppear: Bool

    weak var coordinatorDelegate: DetailItemDetailCoordinatorDelegate?

    init(viewModel: ViewModel<ItemDetailActionHandler>, controllers: Controllers) {
        self.viewModel = viewModel
        self.controllers = controllers
        self.downloadingViaNavigationBar = false
        self.didAppear = false
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemDetailViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupTableViewHandler()
        self.setupFileObservers()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .reloadData)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if !self.didAppear {
            // Collapsed abstract is sometimes rendered incorrectly initially. The height of cell has proper height, but only 1 line is shown instead of 2.
            self.tableView.reloadData()
        }
    }

    deinit {
        DDLogInfo("ItemDetailViewController deinitialized")
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
            self.tableView.reloadData()
        }, completion: nil)
    }

    // MARK: - Navigation

    private func perform(tableViewAction: ItemDetailTableViewHandler.Action) {
        switch tableViewAction {
        case .openCreatorEditor(let creator):
            self.coordinatorDelegate?.showCreatorEditor(for: creator, itemType: self.viewModel.state.data.type,
                                                        saved: { [weak self] creator in
                                                            self?.viewModel.process(action: .saveCreator(creator))
                                                        },
                                                        deleted: { [weak self] id in
                                                            self?.viewModel.process(action: .deleteCreator(id))
                                                        })
        case .openCreatorCreation:
            self.coordinatorDelegate?.showCreatorCreation(for: self.viewModel.state.data.type, saved: { [weak self] creator in
                self?.viewModel.process(action: .saveCreator(creator))
            })

        case .openFilePicker:
            self.coordinatorDelegate?.showAttachmentPicker(save: { [weak self] urls in
                self?.viewModel.process(action: .addAttachments(urls))
            })

        case .openNoteEditor(let note):
            let library = self.viewModel.state.library
            self.coordinatorDelegate?.showNote(with: (note?.text ?? ""), tags: (note?.tags ?? []), libraryId: library.identifier, readOnly: !library.metadataEditable, save: { [weak self] text, tags in
                self?.viewModel.process(action: .saveNote(key: note?.key, text: text, tags: tags))
            })

        case .openTagPicker:
            self.coordinatorDelegate?.showTagPicker(libraryId: self.viewModel.state.library.identifier,
                                                    selected: Set(self.viewModel.state.data.tags.map({ $0.id })),
                                                    picked: { [weak self] tags in
                                                        self?.viewModel.process(action: .setTags(tags))
                                                    })

        case .openTypePicker:
            self.coordinatorDelegate?.showTypePicker(selected: self.viewModel.state.data.type,
                                                     picked: { [weak self] type in
                                                         self?.viewModel.process(action: .changeType(type))
                                                     })

        case .openUrl(let string):
            if let url = URL(string: string) {
                self.coordinatorDelegate?.showWeb(url: url)
            }

        case .openDoi(let doi):
            guard let encoded = FieldKeys.Item.clean(doi: doi).addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return }
            self.coordinatorDelegate?.show(doi: encoded)

        case .showAttachmentError(let error, let index):
            self.coordinatorDelegate?.showAttachmentError(error, retryAction: { [weak self] in
                self?.viewModel.process(action: .openAttachment(index))
            })

        case .trashAttachment(let attachment):
            self.coordinatorDelegate?.showTrashAttachmentQuestion { [weak self] in
                self?.viewModel.process(action: .trashAttachment(attachment))
            }
        }
    }

    private func cancelEditing() {
        switch self.viewModel.state.type {
        case .preview:
            self.viewModel.process(action: .cancelEditing)
        case .creation, .duplication:
            self.navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - UI state

    /// Update UI based on new state.
    /// - parameter state: New state.
    private func update(to state: ItemDetailState) {
        if state.changes.contains(.item) {
            self.itemChanged(state: state)
        }

        if state.changes.contains(.reloadedData) {
            let wasHidden = self.tableView.isHidden
            self.tableView.isHidden = state.isLoadingData
            self.activityIndicator.isHidden = !state.isLoadingData

            self.setNavigationBarButtons(to: state)
            self.tableViewHandler.reloadTitleWidth(from: state.data)
            self.tableViewHandler.reloadSections(to: state, animated: !wasHidden)
        }

        if let error = state.error {
            self.coordinatorDelegate?.show(error: error, viewModel: self.viewModel)
        }

        guard !state.isLoadingData else { return }

        if state.changes.contains(.editing) {
            self.setNavigationBarButtons(to: state)
        }

        if state.changes.contains(.type) {
            self.tableViewHandler.reloadTitleWidth(from: state.data)
        }

        if state.changes.contains(.editing) || state.changes.contains(.type) {
            self.tableViewHandler.reloadSections(to: state, animated: true)
        } else {
            if state.changes.contains(.attachmentFilesRemoved) {
                self.tableViewHandler.reload(section: .attachments)
            } else if let index = state.updateAttachmentIndex {
                if state.data.mainAttachmentIndex == index {
                    // Update main-attachment related UI
                    let key = state.data.attachments[index].key
                    if self.controllers.userControllers?.fileDownloader.data(for: key, libraryId: state.library.identifier).progress == nil {
                        // Reset navbar download flag after download finishes
                        self.downloadingViaNavigationBar = false
                    }

                    self.setNavigationBarButtons(to: state)
                }

                self.tableViewHandler.updateAttachmentCell(with: state.data.attachments[index], at: index)
            }

            if state.changes.contains(.abstractCollapsed) {
                self.tableViewHandler.reload(section: .abstract)
            }

            if let diff = state.diff {
                self.tableViewHandler.reload(with: diff)
            }
        }
    }

    /// Updates navigation bar with appropriate buttons based on editing state.
    /// - parameter isEditing: Current editing state of tableView.
    private func setNavigationBarButtons(to state: ItemDetailState) {
        guard state.library.metadataEditable && !state.isLoadingData else { return }

        self.navigationItem.setHidesBackButton(state.isEditing, animated: false)

        if state.isEditing {
            self.setEditingNavigationBarButtons(isSaving: state.isSaving)
        } else {
            self.setPreviewNavigationBarButtons(attachmentButtonState: self.mainAttachmentButtonState(from: state))
        }
    }

    private func mainAttachmentButtonState(from state: ItemDetailState) -> MainAttachmentButtonState? {
        guard let index = state.data.mainAttachmentIndex else { return nil }
        guard let downloader = self.controllers.userControllers?.fileDownloader else { return .ready(index) }

        let key = state.data.attachments[index].key
        let (progress, error) = downloader.data(for: key, libraryId: state.library.identifier)

        if let error = error {
            return .error(index, error)
        }
        if let progress = progress {
            return .downloading(index, progress)
        }
        return .ready(index)
    }

    private func setPreviewNavigationBarButtons(attachmentButtonState: MainAttachmentButtonState?) {
        if let state = attachmentButtonState, case .downloading(_, let progress) = state,
           let rightBarButtonItems = self.navigationItem.rightBarButtonItems,
           rightBarButtonItems.count == 3,
           let attachmentFileView = rightBarButtonItems[2].customView as? FileAttachmentView {
            attachmentFileView.set(state: .progress(progress), style: .list)
        }

        self.navigationItem.setHidesBackButton(false, animated: false)

        let button = UIBarButtonItem(title: L10n.edit, style: .plain, target: nil, action: nil)
        button.rx.tap.subscribe(onNext: { [weak self] _ in
                         self?.viewModel.process(action: .startEditing)
                     })
                     .disposed(by: self.disposeBag)

        self.navigationItem.rightBarButtonItems = [button] + self.attachmentButtonItems(for: attachmentButtonState)
        self.navigationItem.leftBarButtonItem = nil
    }

    private func attachmentButtonItems(for state: MainAttachmentButtonState?) -> [UIBarButtonItem] {
        guard let state = state else { return [] }

        let spacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        spacer.width = 16
        var items: [UIBarButtonItem] = [spacer]

        switch state {
        case .ready(let index):
            let button = UIBarButtonItem(title: L10n.ItemDetail.viewPdf, style: .plain, target: nil, action: nil)
            button.rx.tap.subscribe(onNext: { [weak self] _ in
                self?.downloadingViaNavigationBar = true
                self?.viewModel.process(action: .openAttachment(index))
            }).disposed(by: self.disposeBag)
            items.append(button)

        case .error(let index, let error):
            let button = UIBarButtonItem(title: L10n.ItemDetail.viewPdf, style: .plain, target: nil, action: nil)
            button.rx.tap.subscribe(onNext: { [weak self] _ in
                self?.coordinatorDelegate?.showAttachmentError(error, retryAction: {
                    self?.viewModel.process(action: .openAttachment(index))
                })
            }).disposed(by: self.disposeBag)
            items.append(button)

        case .downloading(let index, let progress):
            if self.downloadingViaNavigationBar {
                let view = FileAttachmentView()
                view.set(state: .progress(progress), style: .list)
                view.tapAction = { [weak self] in
                    self?.viewModel.process(action: .openAttachment(index))
                }

                items.append(UIBarButtonItem(customView: view))
            } else {
                let button = UIBarButtonItem(title: L10n.ItemDetail.viewPdf, style: .plain, target: nil, action: nil)
                button.isEnabled = false
                items.append(button)
            }
        }

        return items
    }

    private func setEditingNavigationBarButtons(isSaving: Bool) {
        self.navigationItem.setHidesBackButton(true, animated: false)

        let saveButton: UIBarButtonItem
        if isSaving {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = .gray
            saveButton = UIBarButtonItem(customView: indicator)
        } else {
            saveButton = UIBarButtonItem(title: L10n.save, style: .plain, target: nil, action: nil)
            saveButton.rx.tap.subscribe(onNext: { [weak self] _ in
                                 self?.viewModel.process(action: .save)
                             })
                             .disposed(by: self.disposeBag)
        }
        self.navigationItem.rightBarButtonItem = saveButton

        let cancelButton = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancelButton.isEnabled = !isSaving
        cancelButton.rx.tap.subscribe(onNext: { [weak self] _ in
                               self?.cancelEditing()
                           })
                           .disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancelButton
    }

    // MARK: - Actions

    private func itemChanged(state: ItemDetailState) {
        if !state.isEditing {
            self.viewModel.process(action: .reloadData)
            return
        }

        self.coordinatorDelegate?.showDataReloaded(completion: { [weak self] in
            self?.viewModel.process(action: .reloadData)
        })
    }

    // MARK: - Setups

    private func setupTableViewHandler() {
        let width = self.navigationController?.view.frame.width ?? self.view.frame.width
        self.tableViewHandler = ItemDetailTableViewHandler(tableView: self.tableView,
                                                           containerWidth: width,
                                                           viewModel: self.viewModel,
                                                           fileDownloader: self.controllers.userControllers?.fileDownloader)
        self.tableViewHandler.delegate = self

        self.tableViewHandler.observer
                             .observe(on: MainScheduler.instance)
                             .subscribe(onNext: { [weak self] action in
                                 self?.perform(tableViewAction: action)
                             })
                             .disposed(by: self.disposeBag)
    }

    private func setupFileObservers() {
        NotificationCenter.default
                          .rx
                          .notification(.attachmentFileDeleted)
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let notification = notification.object as? AttachmentFileDeletedNotification {
                                  self?.viewModel.process(action: .updateAttachments(notification))
                              }
                          })
                          .disposed(by: self.disposeBag)

        guard let downloader = self.controllers.userControllers?.fileDownloader else { return }

        downloader.observable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] update in
                self?.viewModel.process(action: .updateDownload(update))
            })
            .disposed(by: self.disposeBag)
    }
}

extension ItemDetailViewController: ItemDetailTableViewHandlerDelegate {
    func isDownloadingFromNavigationBar(for index: Int) -> Bool {
        return self.downloadingViaNavigationBar && index == self.viewModel.state.data.mainAttachmentIndex
    }
}

extension ItemDetailViewController: ConflictViewControllerReceiver {
    func shows(object: SyncObject, libraryId: LibraryIdentifier) -> String? {
        guard object == .item && libraryId == self.viewModel.state.library.identifier else { return nil }
        return self.viewModel.state.type.previewKey
    }

    func canDeleteObject(completion: @escaping (Bool) -> Void) {
        self.coordinatorDelegate?.showDeletedAlertForItem(completion: completion)
    }
}

extension ItemDetailViewController: DetailCoordinatorAttachmentProvider {
    func attachment(for key: String, parentKey: String?, libraryId: LibraryIdentifier) -> (Attachment, Library, UIView, CGRect?)? {
        guard let index = self.viewModel.state.data.attachments.firstIndex(where: { $0.key == key && $0.libraryId == libraryId }) else { return nil }
        let indexPath = IndexPath(row: index, section: self.tableViewHandler.attachmentSection)
        let (sourceView, sourceRect) = self.tableViewHandler.sourceDataForCell(at: indexPath)
        return (self.viewModel.state.data.attachments[index], self.viewModel.state.library, sourceView, sourceRect)
    }
}
