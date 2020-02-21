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
import SwiftUI

import RxSwift

class ItemDetailViewController: UIViewController {
    @IBOutlet private var tableView: UITableView!

    private let viewModel: ViewModel<ItemDetailActionHandler>
    private let controllers: Controllers
    private let disposeBag: DisposeBag

    private var tableViewHandler: ItemDetailTableViewHandler!

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

        self.setNavigationBarEditingButton(toEditing: self.viewModel.state.isEditing)
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
            self.openCreatorTypePicker(for: creator)
        case .openFilePicker:
            self.openFilePicker()
        case .openNoteEditor(let note):
            self.open(note: note)
        case .openTagPicker:
            self.openTagPicker()
        case .openTypePicker:
            self.openTypePicker()
        }
    }

    private func open(note: Note?) {
        let controller = NoteEditorViewController(text: (note?.text ?? "")) { [weak self] text in
            guard let `self` = self else { return }
            self.viewModel.process(action: .saveNote(key: note?.key, text: text))
        }
        let navigationController = UINavigationController(rootViewController: controller)
        self.present(navigationController, animated: true, completion: nil)
    }

    private func openFilePicker() {
        let documentTypes = [String(kUTTypePDF), String(kUTTypePNG), String(kUTTypeJPEG)]
        let controller = DocumentPickerViewController(documentTypes: documentTypes, in: .import)
        controller.popoverPresentationController?.sourceView = self.view
        controller.observable
                  .observeOn(MainScheduler.instance)
                  .subscribe(onNext: { [weak self] urls in
                      self?.viewModel.process(action: .addAttachments(urls))
                  })
                  .disposed(by: self.disposeBag)
        self.present(controller, animated: true, completion: nil)
    }

    private func openTagPicker() {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
        let libraryId = self.viewModel.state.libraryId
        let selectedIds = Set(self.viewModel.state.data.tags.map({ $0.id }))

        let view = TagPickerView(saveAction: { [weak self] tags in
                                     self?.viewModel.process(action: .setTags(tags))
                                 }, dismiss: { [weak self] in
                                     self?.dismiss(animated: true, completion: nil)
                                 })
                            .environmentObject(TagPickerStore(libraryId: libraryId, selectedTags: selectedIds, dbStorage: dbStorage))

        let controller = UINavigationController(rootViewController: UIHostingController(rootView: view))
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func openCreatorTypePicker(for creator: ItemDetailState.Creator) {
        let store = CreatorTypePickerStore(itemType: self.viewModel.state.data.type, selected: creator.type, schemaController: self.controllers.schemaController)
        self.presentTypePicker(store: store) { [weak self] type in
            self?.viewModel.process(action: .updateCreator(creator.id, .type(type)))
        }
    }

    private func openTypePicker() {
        let store = ItemTypePickerStore(selected: self.viewModel.state.data.type, schemaController: self.controllers.schemaController)
        self.presentTypePicker(store: store) { [weak self] type in
            self?.viewModel.process(action: .changeType(type))
        }
    }

    private func presentTypePicker<Store: ObservableObject&TypePickerStore>(store: Store, saveAction: @escaping (String) -> Void) {
        let view = TypePickerView<Store>(saveAction: saveAction) { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }
        .environmentObject(store)

        let controller = UINavigationController(rootViewController: UIHostingController(rootView: view))
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
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
    }

    /// Updates navigation bar with appropriate buttons based on editing state.
    /// - parameter isEditing: Current editing state of tableView.
    private func setNavigationBarEditingButton(toEditing editing: Bool) {
        self.navigationItem.setHidesBackButton(editing, animated: false)

        if !editing {
            let button = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)
            button.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.viewModel.process(action: .startEditing)
                         })
                         .disposed(by: self.disposeBag)
            self.navigationItem.rightBarButtonItems = [button]
            return
        }

        let saveButton = UIBarButtonItem(title: "Save", style: .plain, target: nil, action: nil)
        saveButton.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.viewModel.process(action: .save)
                         })
                         .disposed(by: self.disposeBag)

        let cancelButton = UIBarButtonItem(title: "Cancel", style: .plain, target: nil, action: nil)
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
            let controller = UIAlertController(title: "Change Item Type", message: self.droppedFieldsMessage(for: fields), preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: "Ok", style: .default, handler: { [weak self] _ in
                self?.viewModel.process(action: .acceptPrompt)
            }))
            controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { [weak self] _ in
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
        return """
               Are you sure you want to change the item type?
               The following fields will be lost:
               \(formattedNames)
               """
    }
}
