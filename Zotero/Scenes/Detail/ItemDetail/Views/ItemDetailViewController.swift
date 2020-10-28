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
import RxSwift

class ItemDetailViewController: UIViewController {
    @IBOutlet private var tableView: UITableView!

    private let viewModel: ViewModel<ItemDetailActionHandler>
    private let controllers: Controllers
    private let disposeBag: DisposeBag

    private var tableViewHandler: ItemDetailTableViewHandler!

    weak var coordinatorDelegate: DetailItemDetailCoordinatorDelegate?

    init(viewModel: ViewModel<ItemDetailActionHandler>, controllers: Controllers) {
        self.viewModel = viewModel
        self.controllers = controllers
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemDetailViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if self.viewModel.state.library.metadataEditable {
            self.setNavigationBarEditingButton(toEditing: self.viewModel.state.isEditing, isSaving: self.viewModel.state.isSaving)
        }
        self.tableViewHandler = ItemDetailTableViewHandler(tableView: self.tableView, viewModel: self.viewModel,
                                                           fileDownloader: self.controllers.userControllers?.fileDownloader)
        self.setupFileObservers()

        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)

        self.tableViewHandler.observer
                             .observeOn(MainScheduler.instance)
                             .subscribe(onNext: { [weak self] action in
                                 self?.perform(tableViewAction: action)
                             })
                             .disposed(by: self.disposeBag)
    }

    deinit {
        DDLogInfo("ItemDetailViewController deinitialized")
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
            self.coordinatorDelegate?.showNote(with: (note?.text ?? ""), readOnly: !self.viewModel.state.library.metadataEditable, save: { [weak self] text in
                self?.viewModel.process(action: .saveNote(key: note?.key, text: text))
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
                self.showWeb(for: url)
            }
        case .openDoi(let doi):
            guard let encoded = FieldKeys.Item.clean(doi: doi).addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return }
            if let url = URL(string: "https://doi.org/\(encoded)") {
                self.showWeb(for: url)
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

    private func open(attachment: Attachment, at index: Int) {
        let indexPath = IndexPath(row: index, section: self.tableViewHandler.attachmentSection)
        let (sourceView, sourceRect) = self.tableViewHandler.sourceDataForCell(at: indexPath)
        self.coordinatorDelegate?.show(attachment: attachment, library: self.viewModel.state.library, sourceView: sourceView, sourceRect: sourceRect)
    }

    private func showWeb(for url: URL) {
        if url.scheme == "http" || url.scheme == "https" {
            self.coordinatorDelegate?.showWeb(url: url)
            return
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        components.scheme = "http"

        if let url = components.url {
            self.coordinatorDelegate?.showWeb(url: url)
        }
    }

    // MARK: - UI state

    /// Update UI based on new state.
    /// - parameter state: New state.
    private func update(to state: ItemDetailState) {
        if state.changes.contains(.editing) {
            self.setNavigationBarEditingButton(toEditing: state.isEditing, isSaving: state.isSaving)
        }

        if state.changes.contains(.type) {
            self.tableViewHandler.reloadTitleWidth(from: state.data)
        }

        if state.changes.contains(.editing) ||
           state.changes.contains(.type) {
            self.tableViewHandler.reloadSections(to: state)
        } else {
            if (state.changes.contains(.downloadProgress) && !state.isEditing) ||
                state.changes.contains(.attachmentFilesRemoved) {
                self.tableViewHandler.reload(section: .attachments)
            } else if let index = state.updateAttachmentIndex {
                self.tableViewHandler.updateAttachmentCell(with: state.data.attachments[index], at: index)
            }

            if state.changes.contains(.abstractCollapsed) {
                self.tableViewHandler.reload(section: .abstract)
            }

            if let diff = state.diff {
                self.tableViewHandler.reload(with: diff)
            }
        }

        if let error = state.error {
            self.show(error: error)
        }

        if let (attachment, index) = state.openAttachment {
            self.open(attachment: attachment, at: index)
        }
    }

    /// Updates navigation bar with appropriate buttons based on editing state.
    /// - parameter isEditing: Current editing state of tableView.
    private func setNavigationBarEditingButton(toEditing editing: Bool, isSaving: Bool) {
        self.navigationItem.setHidesBackButton(editing, animated: false)

        if !editing {
            let button = UIBarButtonItem(title: L10n.edit, style: .plain, target: nil, action: nil)
            button.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.viewModel.process(action: .startEditing)
                         })
                         .disposed(by: self.disposeBag)
            self.navigationItem.rightBarButtonItems = [button]
            self.navigationItem.leftBarButtonItem = nil
            return
        }

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

    /// Shows appropriate error alert for given error.
    private func show(error: ItemDetailError) {
        switch error {
        case .droppedFields(let fields):
            let controller = UIAlertController(title: L10n.ItemDetail.Error.droppedFieldsTitle,
                                               message: self.droppedFieldsMessage(for: fields),
                                               preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: L10n.ok, style: .default, handler: { [weak self] _ in
                self?.viewModel.process(action: .acceptPrompt)
            }))
            controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { [weak self] _ in
                self?.viewModel.process(action: .cancelPrompt)
            }))
            self.present(controller, animated: true, completion: nil)
        default:
            // TODO: - handle other errors
            break
        }
    }

    // MARK: - Setups

    private func setupFileObservers() {
        NotificationCenter.default
                          .rx
                          .notification(.attachmentFileDeleted)
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let notification = notification.object as? AttachmentFileDeletedNotification {
                                  self?.viewModel.process(action: .updateAttachments(notification))
                              }
                          })
                          .disposed(by: self.disposeBag)

        guard let downloader = self.controllers.userControllers?.fileDownloader else { return }

        downloader.observable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] update in
                self?.viewModel.process(action: .updateDownload(update))
            })
            .disposed(by: self.disposeBag)
    }

    // MARK: - Helpers

    /// Message for `ItemDetailError.droppedFields` error.
    /// - parameter names: Names of fields with values that will disappear if type will change.
    /// - returns: Error message.
    private func droppedFieldsMessage(for names: [String]) -> String {
        let formattedNames = names.map({ "- \($0)\n" }).joined()
        return L10n.ItemDetail.Error.droppedFieldsMessage(formattedNames)
    }
}
