//
//  ItemDetailViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit

import DeepDiff
import RxSwift

class ItemDetailViewController: UIViewController {
    private enum Section: CaseIterable, Equatable, Hashable, DiffAware {
        case abstract, attachments, creators, dates, fields, notes, tags, title, type

        func cellId(isEditing: Bool) -> String {
            switch self {
            case .abstract:
                return "ItemDetailAbstractCell"
            case .attachments:
                return "ItemDetailAttachmentCell"
            case .notes:
                return "ItemDetailNoteCell"
            case .tags:
                return "ItemDetailTagCell"
            case .fields, .type, .dates:
                return "ItemDetailFieldCell"
            case .creators:
                if isEditing {
                    return "ItemDetailCreatorEditingCell"
                } else {
                    return "ItemDetailFieldCell"
                }
            case .title:
                return "ItemDetailTitleCell"
            }
        }
    }

    @IBOutlet private var tableView: UITableView!

    private var sections: [Section] = []

    private static let sectionId = "ItemDetailSectionView"
    private static let addCellId = "ItemDetailAddCell"
    private static let dateFormatter: DateFormatter = createDateFormatter()
    private let viewModel: ViewModel<ItemDetailActionHandler>
    private let disposeBag: DisposeBag

    private static func createDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy, h:mm:ss a"
        return formatter
    }

    init(viewModel: ViewModel<ItemDetailActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemDetailViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupTableView()

        self.setNavigationBarEditingButton(toEditing: self.viewModel.state.isEditing)
        self.sections = self.sections(for: self.viewModel.state.data, isEditing: self.viewModel.state.isEditing)

        self.viewModel.stateObservable
                  .observeOn(MainScheduler.instance)
                  .subscribe(onNext: { [weak self] state in
                      self?.update(to: state)
                  })
                  .disposed(by: self.disposeBag)
    }

    // MARK: - Actions

    private func openNote(with text: String) {
        let controller = NoteEditorViewController(text: text) { [weak self] text in
            guard let `self` = self else { return }
            self.viewModel.process(action: .saveNote(text))
        }
        let navigationController = UINavigationController(rootViewController: controller)
        self.present(navigationController, animated: true, completion: nil)
    }

    /// Update UI based on new state.
    /// - parameter state: New state.
    private func update(to state: ItemDetailState) {
        if state.changes.contains(.editing) {
            self.setNavigationBarEditingButton(toEditing: state.isEditing)
        }

        if state.changes.contains(.editing) ||
           state.changes.contains(.type) {
            self.reloadSections(to: state)
        }

        if state.changes.contains(.downloadProgress) && !state.isEditing,
           let section = self.sections.firstIndex(of: .attachments) {
            self.tableView.reloadSections([section], with: .none)
        }

        if let diff = state.diff {
            self.reload(with: diff)
        }

        if let error = state.error {
            self.show(error: error)
        }
    }

    private func show(error: ItemDetailError) {
        switch error {
        case .droppedFields(let fields): break
        default:
            // TODO: - handle other errors
            break
        }
    }

    private func reloadSections(to state: ItemDetailState) {
        let sections = self.sections(for: state.data, isEditing: state.isEditing)
        let (insertions, deletions) = sections.difference(from: self.sections).separated
        let reloads = Set(0..<self.sections.count).subtracting(Set(deletions))
        self.sections = sections

        self.tableView.performBatchUpdates({
            if !deletions.isEmpty {
                self.tableView.deleteSections(IndexSet(deletions), with: .automatic)
            }
            if !reloads.isEmpty {
                self.tableView.reloadSections(IndexSet(reloads), with: .automatic)
            }
            if !insertions.isEmpty {
                self.tableView.insertSections(IndexSet(insertions), with: .automatic)
            }
            self.tableView.setEditing(state.isEditing, animated: true)
        }, completion: nil)
    }

    private func reload(with diff: ItemDetailState.Diff) {
        guard let section = self.section(from: diff) else { return }
        let insertions = diff.insertions.map({ IndexPath(row: $0, section: section) })
        let deletions = diff.deletions.map({ IndexPath(row: $0, section: section) })
        let reloads = diff.reloads.map({ IndexPath(row: $0, section: section) })

        self.tableView.performBatchUpdates({
            if !deletions.isEmpty {
                self.tableView.deleteRows(at: deletions, with: .automatic)
            }
            if !reloads.isEmpty {
                self.tableView.reloadRows(at: reloads, with: .automatic)
            }
            if !insertions.isEmpty {
                self.tableView.insertRows(at: insertions, with: .automatic)
            }
        }, completion: nil)
    }

    private func section(from diff: ItemDetailState.Diff) -> Int? {
        switch diff {
        case .attachments:
            if let index = self.sections.firstIndex(of: .attachments) {
                return index
            }
        case .creators:
            if let index = self.sections.firstIndex(of: .creators) {
                return index
            }
        case .notes:
            if let index = self.sections.firstIndex(of: .notes) {
                return index
            }
        case .tags:
            if let index = self.sections.firstIndex(of: .tags) {
                return index
            }
        }
        return nil
    }

    /// Creates array of visible section for current state.
    /// - parameter data: Current state.
    /// - parameter isEditing: Current editing table view state.
    /// - returns: Array of visible sections.
    private func sections(for data: ItemDetailState.Data, isEditing: Bool) -> [Section] {
        if isEditing {
            // Each section is visible during editing, so that the user can actually edit them
            return [.title, .type, .creators, .fields, .abstract, .notes, .tags, .attachments]
        }

        var sections: [Section] = []
        if !data.title.isEmpty {
            sections.append(.title)
        }
        // Item type is always visible
        sections.append(.type)
        if !data.creators.isEmpty {
            sections.append(.creators)
        }
        if !data.fieldIds.isEmpty {
            sections.append(.fields)
        }
        if !isEditing {
            sections.append(.dates)
        }
        if let abstract = data.abstract, !abstract.isEmpty {
            sections.append(.abstract)
        }
        if !data.notes.isEmpty {
            sections.append(.notes)
        }
        if !data.tags.isEmpty {
            sections.append(.tags)
        }
        if !data.attachments.isEmpty {
            sections.append(.attachments)
        }
        return sections
    }

    /// Updates navigation bar with appropriate buttons based on editing state.
    /// - parameter isEditing: Current editing state of tableView.
    private func setNavigationBarEditingButton(toEditing editing: Bool) {
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
                               self?.viewModel.process(action: .cancelEditing)
                           })
                           .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItems = [saveButton, cancelButton]
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self

        Section.allCases.forEach { section in
            let cellId = section.cellId(isEditing: false)
            self.tableView.register(UINib(nibName: cellId, bundle: nil), forCellReuseIdentifier: cellId)
            let cellIdEditing = section.cellId(isEditing: true)
            if cellId != cellIdEditing {
                self.tableView.register(UINib(nibName: cellIdEditing, bundle: nil), forCellReuseIdentifier: cellIdEditing)
            }
        }
        self.tableView.register(UINib(nibName: ItemDetailViewController.addCellId, bundle: nil),
                                forCellReuseIdentifier: ItemDetailViewController.addCellId)
        self.tableView.register(UINib(nibName: ItemDetailViewController.sectionId, bundle: nil),
                                forHeaderFooterViewReuseIdentifier: ItemDetailViewController.sectionId)
    }
}

extension ItemDetailViewController: UITableViewDataSource {
    /// Base count of objects in each section. "Base" means just count of actual objects in data arrays, without additional rows shown in tableView.
    private func baseCount(in section: Section) -> Int {
        switch section {
        case .abstract, .title, .type:
            return 1
        case .dates:
            return 2
        case .creators:
            return self.viewModel.state.data.creatorIds.count
        case .fields:
            return self.viewModel.state.data.fieldIds.count
        case .attachments:
            return self.viewModel.state.data.attachments.count
        case .notes:
            return self.viewModel.state.data.notes.count
        case .tags:
            return self.viewModel.state.data.tags.count
        }
    }

    /// Count of rows for each section. This count includes all rows, including additional rows for some sections (add buttons while editing).
    private func count(in section: Section, isEditing: Bool) -> Int {
        let base = self.baseCount(in: section)
        var additional = 0

        switch section {
        case .abstract, .title, .type, .dates, .fields: break
        case .creators, .notes, .attachments, .tags:
            // +1 for add button
            additional = isEditing ? 1 : 0
        }

        return base + additional
    }

    private func cellData(for indexPath: IndexPath, isEditing: Bool) -> (Section, String) {
        let section = self.sections[indexPath.section]
        let cellId: String

        switch section {
        case .fields, .abstract, .title, .type, .dates:
            cellId = section.cellId(isEditing: isEditing)
        case .creators, .attachments, .notes, .tags:
            if indexPath.row < self.baseCount(in: section) {
                cellId = section.cellId(isEditing: isEditing)
            } else {
                cellId = ItemDetailViewController.addCellId
            }
        }

        return (section, cellId)
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.count(in: self.sections[section], isEditing: self.viewModel.state.isEditing)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch self.sections[section] {
        case .notes, .attachments, .tags:
            return 60
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch self.sections[section] {
        case .notes:
            let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: ItemDetailViewController.sectionId) as? ItemDetailSectionView
            view?.setup(with: "Notes")
            return view
        case .attachments:
            let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: ItemDetailViewController.sectionId) as? ItemDetailSectionView
            view?.setup(with: "Attachments")
            return view
        case .tags:
            let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: ItemDetailViewController.sectionId) as? ItemDetailSectionView
            view?.setup(with: "Tags")
            return view
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        switch self.sections[section] {
        case .abstract, .title:
            return 8
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        switch self.sections[section] {
        case .abstract, .title:
            return UIView()
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let isEditing = self.viewModel.state.isEditing
        let (section, cellId) = self.cellData(for: indexPath, isEditing: isEditing)
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)

        var hasSeparator = true

        switch section {
        case .abstract:
            if let cell = cell as? ItemDetailAbstractCell {
                cell.setup(with: (self.viewModel.state.data.abstract ?? ""), isEditing: isEditing)
            }

        case .title:
            if let cell = cell as? ItemDetailTitleCell {
                cell.setup(with: self.viewModel.state.data.title, isEditing: isEditing)
                cell.textObservable.subscribe(onNext: { [weak self] title in
                    if isEditing {
                        self?.viewModel.process(action: .setTitle(title))
                    }
                }).disposed(by: self.disposeBag)
            }

        case .attachments:
                if let cell = cell as? ItemDetailAttachmentCell {
                    let attachment = self.viewModel.state.data.attachments[indexPath.row]
                    cell.setup(with: attachment,
                               progress: self.viewModel.state.downloadProgress[attachment.key],
                               error: self.viewModel.state.downloadError[attachment.key])
                } else if let cell = cell as? ItemDetailAddCell {
                    cell.setup(with: "Add attachment")
                }

        case .notes:
            if let cell = cell as? ItemDetailNoteCell {
                cell.setup(with: self.viewModel.state.data.notes[indexPath.row])
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: "Add note")
            }

        case .tags:
            if let cell = cell as? ItemDetailTagCell {
                cell.setup(with: self.viewModel.state.data.tags[indexPath.row])
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: "Add tag")
            }

        case .type:
            if let cell = cell as? ItemDetailFieldCell {
                cell.setup(with: self.viewModel.state.data.localizedType, title: "Item Type")
            }
            hasSeparator = false

        case .fields:
            if let cell = cell as? ItemDetailFieldCell {
                let fieldId = self.viewModel.state.data.fieldIds[indexPath.row]
                if let field = self.viewModel.state.data.fields[fieldId] {
                    cell.setup(with: field, isEditing: isEditing)
                    cell.textObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .setFieldValue(id: fieldId, value: value))
                    }).disposed(by: self.disposeBag)
                }
            }
            hasSeparator = false

        case .creators:
            if let cell = cell as? ItemDetailCreatorEditingCell {
                let creatorId = self.viewModel.state.data.creatorIds[indexPath.row]
                if let creator = self.viewModel.state.data.creators[creatorId] {
                    cell.setup(with: creator)
                    cell.namePresentationObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .updateCreator(creatorId, .namePresentation(value)))
                    }).disposed(by: self.disposeBag)
                    cell.fullNameObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .updateCreator(creatorId, .fullName(value)))
                    }).disposed(by: self.disposeBag)
                    cell.firstNameObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .updateCreator(creatorId, .firstName(value)))
                    }).disposed(by: self.disposeBag)
                    cell.lastNameObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .updateCreator(creatorId, .lastName(value)))
                    }).disposed(by: self.disposeBag)
                }
            } else if let cell = cell as? ItemDetailFieldCell {
                let creatorId = self.viewModel.state.data.creatorIds[indexPath.row]
                if let creator = self.viewModel.state.data.creators[creatorId] {
                    cell.setup(with: creator)
                }
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: "Add creator")
            }
            hasSeparator = false

        case .dates:
            if let cell = cell as? ItemDetailFieldCell {
                switch indexPath.row {
                case 0:
                    let date = ItemDetailViewController.dateFormatter.string(from: self.viewModel.state.data.dateAdded)
                    cell.setup(with: date, title: "Date Added")
                case 1:
                    let date = ItemDetailViewController.dateFormatter.string(from: self.viewModel.state.data.dateModified)
                    cell.setup(with: date, title: "Date Modified")
                default: break
                }
            }
            hasSeparator = false
        }

        cell.separatorInset = UIEdgeInsets(top: 0, left: (hasSeparator ? .greatestFiniteMagnitude : cell.layoutMargins.left), bottom: 0, right: 0)

        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let section = self.sections[indexPath.section]
        let rows = self.baseCount(in: section)
        switch section {
        case .creators, .attachments, .notes, .tags:
            return indexPath.row < rows
        case .title, .abstract, .fields, .type, .dates:
            return false
        }
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        let section = self.sections[indexPath.section]
        switch section {
        case .creators:
            return indexPath.row < self.baseCount(in: section)
        default:
            return false
        }
    }
}

extension ItemDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView,
                   targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
                   toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        let section = self.sections[proposedDestinationIndexPath.section]
        if section != .creators { return sourceIndexPath }
        if proposedDestinationIndexPath.row == self.baseCount(in: section) { return sourceIndexPath }
        return proposedDestinationIndexPath
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let sourceSection = self.sections[sourceIndexPath.section]
        let destinationSection = self.sections[destinationIndexPath.section]
        guard sourceSection == .creators && destinationSection == .creators else { return }
        self.viewModel.process(action: .moveCreators(from: IndexSet([sourceIndexPath.row]), to: destinationIndexPath.row))
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }

        switch self.sections[indexPath.section] {
        case .creators:
            self.viewModel.process(action: .deleteCreators([indexPath.row]))
        case .tags:
            self.viewModel.process(action: .deleteTags([indexPath.row]))
        case .attachments:
            self.viewModel.process(action: .deleteAttachments([indexPath.row]))
        case .notes:
            self.viewModel.process(action: .deleteNotes([indexPath.row]))
        case .title, .abstract, .fields, .type, .dates: break
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch self.sections[indexPath.section] {
        case .attachments:
            if self.viewModel.state.isEditing {
                if indexPath.row == self.viewModel.state.data.attachments.count {
                    let action: ([URL]) -> Void = { [weak self] urls in
                        self?.viewModel.process(action: .addAttachments(urls))
                    }
                    NotificationCenter.default.post(name: .presentFilePicker, object: action)
                }
            } else {
                let attachment = self.viewModel.state.data.attachments[indexPath.row]
                self.viewModel.process(action: .openAttachment(attachment))
            }
        case .notes:
            if self.viewModel.state.isEditing && indexPath.row == self.viewModel.state.data.notes.count {
                self.viewModel.process(action: .addNote)
                self.openNote(with: "")
            } else {
                let note = self.viewModel.state.data.notes[indexPath.row]
                self.viewModel.process(action: .openNote(note))
                self.openNote(with: note.text)
            }
        case .tags:
            if self.viewModel.state.isEditing && indexPath.row == self.viewModel.state.data.tags.count {
                let action: ([Tag]) -> Void = { [weak self] tags in
                    self?.viewModel.process(action: .setTags(tags))
                }
                NotificationCenter.default.post(name: .presentTagPicker, object: (Set(self.viewModel.state.data.tags.map({ $0.id })), self.viewModel.state.libraryId, action))
            }
        case .creators:
            if self.viewModel.state.isEditing && indexPath.row == self.viewModel.state.data.creators.count {
                self.viewModel.process(action: .addCreator)
            }
        case .type:
            if self.viewModel.state.isEditing {
                if self.viewModel.state.data.type != ItemTypes.attachment {
                    let action: (String) -> Void = { [weak self] type in
                        self?.viewModel.process(action: .changeType(type))
                    }
                    NotificationCenter.default.post(name: .presentTypePicker, object: (self.viewModel.state.data.type, action))
                }
            }
        case .title, .abstract, .fields, .dates: break
        }
    }
}
