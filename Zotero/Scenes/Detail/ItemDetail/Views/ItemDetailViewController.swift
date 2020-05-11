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
import SwiftUI

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
            self.setNavigationBarEditingButton(toEditing: self.viewModel.state.isEditing)
        }
        self.tableViewHandler = ItemDetailTableViewHandler(tableView: self.tableView, viewModel: self.viewModel)

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

    // MARK: - Navigation

    private func perform(tableViewAction: ItemDetailTableViewHandler.Action) {
        switch tableViewAction {
        case .openCreatorTypePicker(let creator):
            self.coordinatorDelegate?.showCreatorTypePicker(itemType: self.viewModel.state.data.type,
                                                            selected: creator.type,
                                                            picked: { [weak self] creatorType in
                                                                self?.viewModel.process(action: .updateCreator(creator.id, .type(creatorType)))
                                                            })
        case .openFilePicker:
            self.coordinatorDelegate?.showAttachmentPicker(save: { [weak self] urls in
                self?.viewModel.process(action: .addAttachments(urls))
            })
        case .openNoteEditor(let note):
            self.coordinatorDelegate?.showNote(with: (note?.text ?? ""), save: { [weak self] text in
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

    private func open(attachmentAction: ItemDetailState.OpenAttachmentAction) {
        switch attachmentAction {
        case .pdf(let url, let key):
            self.coordinatorDelegate?.showPdf(at: url, key: key)

        case .unknownFile(let url):
            self.coordinatorDelegate?.showUnknownAttachment(at: url)

        case .web(let url):
            self.coordinatorDelegate?.showWeb(url: url)
        }
    }

    // MARK: - UI state

    /// Update UI based on new state.
    /// - parameter state: New state.
    private func update(to state: ItemDetailState) {
        if state.changes.contains(.editing) {
            self.setNavigationBarEditingButton(toEditing: state.isEditing)
        }

        if state.changes.contains(.type) {
            self.tableViewHandler.reloadTitleWidth(from: state.data)
        }

        if state.changes.contains(.editing) ||
           state.changes.contains(.type) {
            self.tableViewHandler.reloadSections(to: state)
        }

        if state.changes.contains(.downloadProgress) && !state.isEditing {
            self.tableViewHandler.reload(section: .attachments)
        }

        if let diff = state.diff {
            self.tableViewHandler.reload(with: diff)
        }

        if let error = state.error {
            self.show(error: error)
        }

        if let action = state.openAttachmentAction {
            self.open(attachmentAction: action)
        }
    }

    /// Updates navigation bar with appropriate buttons based on editing state.
    /// - parameter isEditing: Current editing state of tableView.
    private func setNavigationBarEditingButton(toEditing editing: Bool) {
        self.navigationItem.setHidesBackButton(editing, animated: false)

        if !editing {
            let button = UIBarButtonItem(title: L10n.edit, style: .plain, target: nil, action: nil)
            button.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.viewModel.process(action: .startEditing)
                         })
                         .disposed(by: self.disposeBag)
            self.navigationItem.rightBarButtonItems = [button]
            return
        }

        let saveButton = UIBarButtonItem(title: L10n.save, style: .plain, target: nil, action: nil)
        saveButton.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.viewModel.process(action: .save)
                         })
                         .disposed(by: self.disposeBag)

        let cancelButton = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancelButton.rx.tap.subscribe(onNext: { [weak self] _ in
                               self?.cancelEditing()
                           })
                           .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItems = [saveButton, cancelButton]
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

    // MARK: - Helpers

    /// Message for `ItemDetailError.droppedFields` error.
    /// - parameter names: Names of fields with values that will disappear if type will change.
    /// - returns: Error message.
    private func droppedFieldsMessage(for names: [String]) -> String {
        let formattedNames = names.map({ "- \($0)\n" }).joined()
        return L10n.ItemDetail.Error.droppedFieldsMessage(formattedNames)
    }
}
