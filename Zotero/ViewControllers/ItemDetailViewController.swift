//
//  ItemDetailViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import RxSwift
import SafariServices

#if PDFENABLED
import PSPDFKit
import PSPDFKitUI
#endif

class ItemDetailViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: ItemDetailStore
    private let disposeBag: DisposeBag
    // Variables
    private weak var lastSelectedAttachmentCell: UITableViewCell?

    // MARK: - Lifecycle

    init(store: ItemDetailStore) {
        self.store = store
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemDetailViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        switch self.store.state.value.type {
        case .preview(let item):
            self.navigationItem.title = item.title
        case .creation:
            self.navigationItem.title = "Create item"
        }
        self.setupNavigationBar(forEditing: self.store.state.value.isEditing)
        self.registerNotifications()
        self.setupTableView()

        self.store.state.asObservable()
                        .observeOn(MainScheduler.instance)
                        .subscribe(onNext: { [weak self] state in
                            self?.process(state: state)
                        })
                        .disposed(by: self.disposeBag)

        self.store.handle(action: .load)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.splitViewController?.presentsWithGesture = false
    }

    // MARK: - Actions

    private func process(state: ItemDetailStore.StoreState) {
        if state.changes.contains(.data) {
            if let diff = state.editingDiff {
                self.setEditing(state.isEditing, diff: diff)
            } else {
                self.tableView.reloadData()
            }
        }
        if state.changes.contains(.download) {
            self.updateDownloadStates(state.attachmentStates)
            self.showAttachmentIfNeeded(in: state.attachmentStates)
        }
        if let error = state.error {
            // TODO: Show error
        }
    }

    private func showTypePicker(for cell: UITableViewCell) {
        let schemaController = self.store.schemaController
        let sortedData = schemaController.itemTypes
                                         .compactMap({ type -> (String, String)? in
                                            guard let localized = schemaController.localized(itemType: type) else { return nil }
                                            return (type, localized)
                                         })
                                         .sorted(by: { $0.1 <    $1.1 })
        let titles = sortedData.map({ $0.1 })

        let pickerController = PickerViewController(values: titles) { [weak self] row in
            let type = sortedData[row].0
            self?.store.handle(action: .changeType(type))
        }

        let navigationController = UINavigationController(rootViewController: pickerController)
        navigationController.modalPresentationStyle = .popover
        navigationController.popoverPresentationController?.sourceView = cell
        navigationController.popoverPresentationController?.sourceRect = cell.bounds
        self.present(navigationController, animated: true, completion: nil)
    }

    private func setEditing(_ editing: Bool, diff: [EditingSectionDiff]) {
        self.setupNavigationBar(forEditing: editing)

        if #available(iOS 11.0, *) {
            self.tableView.performBatchUpdates({
                self.performEditingSectionDiffActions(diff: diff)
                self.tableView.isEditing = editing
            }, completion: nil)
        } else {
            self.tableView.beginUpdates()
            self.performEditingSectionDiffActions(diff: diff)
            self.tableView.isEditing = editing
            self.tableView.endUpdates()
        }
    }

    private func performEditingSectionDiffActions(diff: [EditingSectionDiff]) {
        diff.forEach { section in
            switch section.type {
            case .delete:
                self.tableView.deleteSections(IndexSet(integer: section.index), with: .fade)
            case .insert:
                self.tableView.insertSections(IndexSet(integer: section.index), with: .fade)
            case .update:
                self.tableView.reloadSections(IndexSet(integer: section.index), with: .fade)
            }
        }
    }

    private func addAttachment() {

    }

    private func addNote() {
        let controller = NoteViewController(text: "") { [weak self] newText in
            self?.store.handle(action: .createNote(newText))
        }
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .formSheet
        self.present(navigationController, animated: true, completion: nil)
    }

    private func addTag() {

    }

    private func editNote(_ note: ItemDetailStore.StoreState.Note) {
        let controller = NoteViewController(text: note.text) { [weak self] newText in
            self?.store.handle(action: .updateNote(key: note.key, text: newText))
        }
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .formSheet
        self.present(navigationController, animated: true, completion: nil)
    }

    private func showAttachmentIfNeeded(in states: [String: ItemDetailStore.StoreState.AttachmentState]) {
        for data in states {
            switch data.value {
            case .result(let type, let wasDownloaded):
                if !wasDownloaded {
                    self.showAttachment(type)
                    self.store.handle(action: .clearAttachment(data.key))
                }

            default: break
            }
        }
    }

    private func showAttachment(_ attachment: ItemDetailStore.StoreState.AttachmentType) {
        switch attachment {
        case .url(let url):
            self.showUrl(url)

        case .file(let file, _):
            switch file.ext {
            case "pdf":
                self.showPdf(from: file)
            default:
                self.showUnknown(from: file)
            }
        }
    }

    private func updateDownloadStates(_ states: [String: ItemDetailStore.StoreState.AttachmentState]) {
        let sections = self.store.state.value.dataSource?.sections ?? []
        guard let attachmentSection = sections.firstIndex(of: .attachments),
              let visibleIndexPaths = self.tableView.indexPathsForVisibleRows else { return }

        var needsReload = false
        for indexPath in visibleIndexPaths {
            guard indexPath.section == attachmentSection && indexPath.row > 0,
                  let attachment = self.store.state.value.dataSource?.attachment(at: (indexPath.row - 1)),
                  let state = states[attachment.key] else { continue }
            if self.updateDownloadState(state, at: indexPath) {
                needsReload = true
            }
        }
        if needsReload {
            self.tableView.reloadData()
        }
    }

    private func updateDownloadState(_ state: ItemDetailStore.StoreState.AttachmentState,
                                     at indexPath: IndexPath) -> Bool {
        switch state {
        case .progress(let progress):
            if let cell = self.tableView.cellForRow(at: indexPath) as? ItemSpecialCell {
                cell.setProgress(Float(progress))
            }
        case .result(_, let wasDownloaded):
            return wasDownloaded
        case .failure:
            return true
        }
        return false
    }

    private func showUrl(_ url: URL) {
        let controller = SFSafariViewController(url: url)
        self.present(controller, animated: true, completion: nil)
    }

    private func showPdf(from file: File) {
        #if PDFENABLED
        let document = PSPDFDocument(url: file.createUrl())
        let pdfController = PSPDFViewController(document: document)
        let navigationController = UINavigationController(rootViewController: pdfController)
        self.present(navigationController, animated: true, completion: nil)
        #endif
    }

    private func showUnknown(from file: File) {
        let controller = UIActivityViewController(activityItems: [file.createUrl()], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = self.lastSelectedAttachmentCell ?? self.view
        if let frame = self.lastSelectedAttachmentCell?.bounds {
            controller.popoverPresentationController?.sourceRect = frame
        }
        self.present(controller, animated: true)
    }

    private func cellId(for row: Int, section: ItemDetailStore.StoreState.Section) -> String {
        switch section {
        case .title, .fields, .abstract, .creators:
            return self.cellId(for: section)
        case .tags, .related, .notes, .attachments:
            if row == 0 {
                return ItemSpecialTitleCell.nibName
            }
            return self.cellId(for: section)
        }
    }

    private func cellId(for section: ItemDetailStore.StoreState.Section) -> String {
        switch section {
        case .title:
            return ItemTitleCell.nibName
        case .fields, .creators:
            return ItemFieldCell.nibName
        case .abstract:
            return ItemAbstractCell.nibName
        case .tags, .related, .notes, .attachments:
            return ItemSpecialCell.nibName
        }
    }

    private func registerNotifications() {
        NotificationCenter.default.rx.notification(NSLocale.currentLocaleDidChangeNotification)
                                     .observeOn(MainScheduler.instance)
                                     .subscribe(onNext: { [weak self] _ in
                                         self?.store.handle(action: .reloadLocale)
                                     })
                                     .disposed(by: self.disposeBag)
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        ItemDetailStore.StoreState.Section.allCases.forEach { section in
            let identifier = self.cellId(for: section)
            self.tableView.register(UINib(nibName: identifier, bundle: nil),
                                    forCellReuseIdentifier: identifier)
        }
        self.tableView.register(UINib(nibName: ItemSpecialTitleCell.nibName, bundle: nil),
                                forCellReuseIdentifier: ItemSpecialTitleCell.nibName)
        self.tableView.tableFooterView = UIView()
        self.tableView.allowsSelectionDuringEditing = true
        self.tableView.isEditing = self.store.state.value.isEditing
    }

    private func setupNavigationBar(forEditing editing: Bool) {
        var buttons: [UIBarButtonItem] = []

        switch self.store.state.value.type {
        case .preview:
            let toggleButton = UIBarButtonItem(title: (editing ? "Cancel" : "Edit"), style: .plain,
                                               target: nil, action: nil)
            toggleButton.rx.tap.subscribe(onNext: { [weak self] _ in
                                              self?.store.handle(action: (editing ? .stopEditing(false) : .startEditing))
                                          })
                                          .disposed(by: self.disposeBag)
            buttons.append(toggleButton)

        case .creation: break
        }

        if editing {
            let saveButton = UIBarButtonItem(title: "Save", style: .done, target: nil, action: nil)

            saveButton.rx.tap.subscribe(onNext: { [weak self] _ in
                          self?.store.handle(action: .stopEditing(true))
                      })
                      .disposed(by: self.disposeBag)

            buttons.insert(saveButton, at: 0)
        }
        self.navigationItem.rightBarButtonItems = buttons
    }
}

extension ItemDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.store.state.value.dataSource?.sections.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let dataSource = self.store.state.value.dataSource else { return 0 }
        return dataSource.rowCount(for: dataSource.sections[section])
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let section = self.store.state.value.dataSource?.sections[section] else { return 0 }
        switch section {
        case .title, .fields, .abstract, .creators:
            return 0
        case .attachments, .notes, .tags, .related:
            return 10
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard let section = self.store.state.value.dataSource?.sections[section] else { return 0 }
        switch section {
        case .title, .fields, .creators:
            return 0
        case .attachments, .notes, .tags, .abstract, .related:
            return 10
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let dataSource = self.store.state.value.dataSource else { return UITableViewCell() }

        let section = dataSource.sections[indexPath.section]
        let cellId = self.cellId(for: indexPath.row, section: section)
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)

        if let cell = cell as? ItemTitleCell {
            let localizedType = self.store.schemaController.localized(itemType: dataSource.type) ?? ""
            cell.setup(with: dataSource.title, type: localizedType, editing: tableView.isEditing)
            cell.typeObservable.subscribe(onNext: { [weak self, weak cell] _ in
                                   guard let cell = cell, let `self` = self else { return }
                                   self.showTypePicker(for: cell)
                               })
                               .disposed(by: self.disposeBag)
            cell.textObservable.subscribe { [weak self] event in
                                   switch event {
                                   case .next(let string):
                                       self?.store.handle(action: .updateTitle(string))
                                   default: break
                                   }
                               }
                               .disposed(by: self.disposeBag)
        } else if let cell = cell as? ItemAbstractCell {
            cell.setup(with: (dataSource.abstract ?? ""), editing: tableView.isEditing)
            cell.textObservable.subscribe { [weak self] event in
                                   switch event {
                                   case .next(let string):
                                       self?.store.handle(action: .updateAbstract(string))
                                   default: break
                                   }
                               }
                                .disposed(by: self.disposeBag)
        } else if let cell = cell as? ItemFieldCell {
            switch section {
            case .fields:
                if let field = dataSource.field(at: indexPath.row) {
                    cell.setup(with: field.name, value: field.value, editing: tableView.isEditing)
                    cell.textObservable.throttle(0.8, scheduler: MainScheduler.instance)
                        .subscribe { [weak self] event in
                            switch event {
                            case .next(let string):
                                self?.store.handle(action: .updateField(field.type, string))
                            default: break
                            }
                        }
                        .disposed(by: self.disposeBag)
                }

            case .creators:
                if let creator = dataSource.creator(at: indexPath.row) {
                    var value = ""
                    if !creator.name.isEmpty {
                        value = creator.name
                    } else if !creator.firstName.isEmpty || !creator.lastName.isEmpty {
                        value = creator.firstName + " " + creator.lastName
                    }
                    let localizedType = self.store.schemaController.localized(creator: creator.rawType) ?? ""
                    cell.setup(with: localizedType, value: value, editing: tableView.isEditing)
                }

            default: break
            }
        } else if let cell = cell as? ItemSpecialTitleCell {
            switch section {
            case .attachments:
                cell.setup(with: "Attachments", showAddButton: tableView.isEditing, addAction: { [weak self] in
                    self?.addAttachment()
                })
            case .notes:
                cell.setup(with: "Notes", showAddButton: tableView.isEditing, addAction: { [weak self] in
                    self?.addNote()
                })
            case .tags:
                cell.setup(with: "Tags", showAddButton: tableView.isEditing, addAction: { [weak self] in
                    self?.addTag()
                })
            case .related: break
            default: break
            }
        } else if let cell = cell as? ItemSpecialCell {
            let index = indexPath.row - 1
            let model: ItemSpecialCellModel?
            var attachmentType: ItemDetailStore.StoreState.AttachmentType?
            var progress: Float = 0

            switch section {
            case .attachments:
                let data = dataSource.attachment(at: index)
                model = data
                attachmentType = data?.type

                if let key = data?.key,
                   let attachmentState = self.store.state.value.attachmentStates[key] {
                    switch attachmentState {
                    case .progress(let fileProgress):
                        progress = Float(fileProgress)
                    case .failure:
                        // TODO: - Show failure in cell
                        break
                    case .result: break
                    }
                }
            case .notes:
                model = dataSource.note(at: index)
            case .tags:
                model = dataSource.tag(at: index)
            case .related:
                model = nil
            default:
                model = nil
            }

            if let model = model {
                cell.setup(with: model)
            }
            if let metadata = attachmentType {
                cell.setAttachmentType(metadata)
            }
            cell.setProgress(progress)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if !tableView.isEditing {
            return .none
        }

        guard let dataSource = self.store.state.value.dataSource else { return .none }

        switch dataSource.sections[indexPath.section] {
        case .title, .fields, .abstract, .creators:
            return .none
        case .attachments, .tags, .related, .notes:
            return indexPath.row == 0 ? .none : .delete
        }
    }
}

extension ItemDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let dataSource = self.store.state.value.dataSource else { return }
        let isEditing = self.store.state.value.isEditing

        switch dataSource.sections[indexPath.section] {
        case .attachments:
            if indexPath.row > 0,
               let attachment = dataSource.attachment(at: (indexPath.row - 1)) {
                if !isEditing {
                    self.lastSelectedAttachmentCell = tableView.cellForRow(at: indexPath)
                    self.store.handle(action: .showAttachment(attachment))
                }
            }
        case .notes:
            if isEditing && indexPath.row > 0,
               let note = dataSource.note(at: (indexPath.row - 1)) {
                self.editNote(note)
            }
        default: break
        }
    }
}

extension ItemDetailStore.StoreState.Tag: ItemSpecialCellModel {
    var tintColor: UIColor? {
        return self.uiColor
    }

    var title: String {
        return self.name
    }

    var specialIcon: UIImage? {
        return UIImage(named: "icon_cell_tag")?.withRenderingMode(.alwaysTemplate)
    }
}

extension ItemDetailStore.StoreState.Attachment: ItemSpecialCellModel {
    var specialIcon: UIImage? {
        return UIImage(named: "icon_cell_attachment")?.withRenderingMode(.alwaysTemplate)
    }

    var tintColor: UIColor? {
        return nil
    }
}

extension ItemDetailStore.StoreState.Note: ItemSpecialCellModel {
    var specialIcon: UIImage? {
        return UIImage(named: "icon_cell_note")?.withRenderingMode(.alwaysTemplate)
    }

    var tintColor: UIColor? {
        return nil
    }
}
