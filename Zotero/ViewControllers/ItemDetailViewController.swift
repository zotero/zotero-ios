//
//  ItemDetailViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import PSPDFKit
import PSPDFKitUI
import RxSwift

class ItemDetailViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: ItemDetailStore
    private let disposeBag: DisposeBag

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

        self.navigationItem.title = self.store.state.value.item.title
        self.setupNavigationBar(forEditing: false)
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
            self.updateDownloadState(state.downloadState)
        }
        if let error = state.error {
            // TODO: Show error
        }
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

    }

    private func addTag() {

    }

    private func showAttachment(at index: Int) {
        guard let attachment = self.store.state.value.dataSource?.attachment(at: index) else { return }
        self.store.handle(action: .showAttachment(attachment))
    }

    private func updateDownloadState(_ state: ItemDetailStore.StoreState.FileDownload?) {
        guard let state = state else {
            // TODO: - hide UI
            return
        }

        switch state {
        case .progress(let progress):
            // TODO: - show progress ui
            DDLogInfo("ItemDetailViewController: file download progress \(progress)")
            break
        case .downloaded(let file):
            DDLogInfo("ItemDetailViewController: file downloaded to \(file.createUrl().absoluteString)")
            switch file.ext {
            case "pdf":
                self.showPdf(from: file)
            default: break
            }
            DispatchQueue.main.async {
                self.store.handle(action: .attachmentOpened)
            }
        }
    }

    private func showPdf(from file: File) {
        let document = PSPDFDocument(url: file.createUrl())
        let pdfController = PSPDFViewController(document: document)
        let navigationController = UINavigationController(rootViewController: pdfController)
        self.present(navigationController, animated: true, completion: nil)
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
    }

    private func setupNavigationBar(forEditing editing: Bool) {
        let toggleButton = UIBarButtonItem(title: (editing ? "Cancel" : "Edit"), style: .plain,
                                           target: nil, action: nil)
        toggleButton.rx.tap.subscribe(onNext: { [weak self] _ in
                         self?.store.handle(action: (editing ? .stopEditing(false) : .startEditing))
                      })
                     .disposed(by: self.disposeBag)

        var buttons: [UIBarButtonItem] = [toggleButton]
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
            cell.setup(with: dataSource.title, editing: tableView.isEditing)
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
                                self?.store.handle(action: .updateField(field.name, string))
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
                    cell.setup(with: creator.rawType, value: value, editing: tableView.isEditing)
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
            switch section {
            case .attachments:
                model = dataSource.attachment(at: index)
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

        switch dataSource.sections[indexPath.section] {
        case .attachments:
            if indexPath.row > 0 {
                self.showAttachment(at: (indexPath.row - 1))
            }
        default: break
        }
    }
}

extension RTag: ItemSpecialCellModel {
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

extension RItem: ItemSpecialCellModel {
    var specialIcon: UIImage? {
        switch self.type {
        case .attachment:
            return UIImage(named: "icon_cell_attachment")?.withRenderingMode(.alwaysTemplate)
        case .note:
            return UIImage(named: "icon_cell_note")?.withRenderingMode(.alwaysTemplate)
        default:
            return nil
        }
    }

    var tintColor: UIColor? {
        return nil
    }
}
