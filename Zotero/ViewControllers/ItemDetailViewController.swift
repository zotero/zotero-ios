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
    private var rowIds: [Section: [Int]] = [:]
    private var storeSubscriber: AnyCancellable?

    private static let sectionId = "ItemDetailSectionView"
    private static let addCellId = "ItemDetailAddCell"
    private static let dateFormatter: DateFormatter = createDateFormatter()
    private let oldStore: ItemDetailStore
    private let store: ViewModel<ItemDetailActionHandler>
    private let disposeBag: DisposeBag

    private static func createDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy, h:mm:ss a"
        return formatter
    }

    init(oldStore: ItemDetailStore, store: ViewModel<ItemDetailActionHandler>) {
        self.oldStore = oldStore
        self.store = store
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemDetailViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupTableView()

        self.setNavigationBarEditingButton(toEditing: self.oldStore.state.isEditing)
        self.reloadIfNeeded(state: self.oldStore.state, animated: false, tableView: self.tableView)

        self.storeSubscriber = self.oldStore.$state.receive(on: DispatchQueue.main)
                                                .dropFirst()
                                                .sink(receiveValue: { [weak self] state in
                                                    self?.update(to: state)
                                                })

        self.store.stateObservable
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
            self.oldStore.saveNote(text: text)
        }
        let navigationController = UINavigationController(rootViewController: controller)
        self.present(navigationController, animated: true, completion: nil)
    }

    private func update(to state: ItemDetailState) {

    }

    /// Update UI based on new state.
    /// - parameter state: New state.
    private func update(to state: ItemDetailStore.State) {
        if state.isEditing != self.tableView.isEditing {
            self.setNavigationBarEditingButton(toEditing: state.isEditing)
        }
        self.reloadIfNeeded(state: state, animated: true, tableView: self.tableView)
    }

    private func reloadIfNeeded(state: ItemDetailStore.State, animated: Bool, tableView: UITableView) {
        let sections = self.sections(for: state.data, isEditing: state.isEditing)
        let rows = self.rowIds(from: state.data, sections: sections, isEditing: state.isEditing)
        if sections != self.sections || rows != self.rowIds {
            let editingChanged = tableView.isEditing != state.isEditing
            self.reload(sections: sections, rows: rows, isEditing: state.isEditing, editingChanged: editingChanged, animated: animated, tableView: self.tableView)
        }
    }

    /// Reloads table view.
    /// - parameter data: Current state data.
    /// - parameter isEditing: New editing state for tableView.
    /// - parameter animated: True if reload should happen with animation, false otherwise.
    private func reload(sections: [Section], rows: [Section: [Int]], isEditing: Bool, editingChanged: Bool, animated: Bool, tableView: UITableView) {
        if !animated {
            self.sections = sections
            self.rowIds = rows
            tableView.reloadData()
            if editingChanged {
                tableView.setEditing(isEditing, animated: false)
            }
            return
        }

        let oldSections = self.sections
        self.sections = sections
        let typeChanged = self.rowIds[.type]?.first != rows[.type]?.first
        self.rowIds = rows

        let (sectionInsertions, sectionDeletions) = self.separated(difference: sections.difference(from: oldSections))
        var sectionReloads: Set<Int>
        if editingChanged || !isEditing {
            // Reload all sections if editing is changing or user is not editing
            sectionReloads = Set(0..<oldSections.count)
        } else {
            // Some sections contain cells with text fields. Those shouldn't be reloaded. They already have updated content (from editing) and would
            // just cancel the keyboard input.
            var editableSections: Set<Section> = [.attachments, .notes, .tags, .type]
            if typeChanged {
                editableSections.insert(.fields)
            }
            let indices = oldSections.enumerated().compactMap({ editableSections.contains($0.element) ? $0.offset : nil })
            sectionReloads = Set(indices)
        }
        // Subtract deleted sections to avoid crash
        sectionReloads = sectionReloads.subtracting(Set(sectionDeletions))

        tableView.performBatchUpdates({
            if !sectionReloads.isEmpty {
                let animation: UITableView.RowAnimation = !editingChanged && isEditing && !typeChanged ? .none : .automatic
                tableView.reloadSections(IndexSet(sectionReloads), with: animation)
            }
            if !sectionDeletions.isEmpty {
                tableView.deleteSections(IndexSet(sectionDeletions), with: .automatic)
            }
            if !sectionInsertions.isEmpty {
                tableView.insertSections(IndexSet(sectionInsertions), with: .automatic)
            }
            if editingChanged {
                tableView.setEditing(isEditing, animated: true)
            }
        }, completion: nil)
    }

    private func separated<T>(difference: CollectionDifference<T>) -> ([Int], [Int]) {
        var insertions: [Int] = []
        var deletions: [Int] = []
        difference.forEach { change in
            switch change {
            case .insert(let offset, _, _):
                insertions.append(offset)
            case .remove(let offset, _, _):
                deletions.append(offset)
            }
        }
        return (insertions, deletions)
    }

    /// Creates sectioned arrays of ids for each section. These ids are used for diffing of changes made to current state during editing.
    /// Only those sections should change ids, which want to add/delete/update their rows in table view during editing.
    /// For example, .title, .abstract or .fields don't change their ids, because they are updated by textField/textView and their change
    /// is already reflected there. On the other hand, .type is changed by a picker, so we want to reload the field when the value changes.
    /// .creators can be added or deleted, so their ids are changed as well.
    /// - parameter data: Data from `ItemDetailStore`
    /// - parameter sections: Currently visible sections
    /// - returns: Sectioned arrays of ids.
    private func rowIds(from data: ItemDetailStore.State.Data, sections: [Section], isEditing: Bool) -> [Section: [Int]] {
        var rowIds: [Section: [Int]] = [:]
        sections.forEach { section in
            var ids: [Int] = []
            switch section {
            case .title:
                ids = [data.title.hashValue]
            case .abstract:
                ids = [String(describing: data.abstract).hashValue]
            case .dates:
                ids = [data.dateAdded.hashValue, data.dateModified.hashValue]
            case .type:
                ids = [data.type.hashValue]
            case .fields:
                ids = data.fieldIds.compactMap({ data.fields[$0] }).map({ $0.hashValue })
            case .creators:
                ids = data.creatorIds.compactMap({ data.creators[$0] }).map({ $0.hashValue })
                if isEditing {
                    ids.append("add_button".hashValue)
                }
            case .attachments:
                ids = data.attachments.map({ $0.hashValue })
                if isEditing {
                    ids.append("add_button".hashValue)
                }
            case .notes:
                ids = data.notes.map({ $0.title.hashValue })
                if isEditing {
                    ids.append("add_button".hashValue)
                }
            case .tags:
                ids = data.tags.map({ $0.id.hashValue })
                if isEditing {
                    ids.append("add_button".hashValue)
                }
            }
            rowIds[section] = ids
        }
        return rowIds
    }

    /// Creates array of visible section for current state.
    /// - parameter data: Current state.
    /// - parameter isEditing: Current editing table view state.
    /// - returns: Array of visible sections.
    private func sections(for data: ItemDetailStore.State.Data, isEditing: Bool) -> [Section] {
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
                             self?.oldStore.startEditing()
                         })
                         .disposed(by: self.disposeBag)
            self.navigationItem.rightBarButtonItems = [button]
            return
        }

        let saveButton = UIBarButtonItem(title: "Save", style: .plain, target: nil, action: nil)
        saveButton.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.oldStore.saveChanges()
                         })
                         .disposed(by: self.disposeBag)

        let cancelButton = UIBarButtonItem(title: "Cancel", style: .plain, target: nil, action: nil)
        cancelButton.rx.tap.subscribe(onNext: { [weak self] _ in
                               self?.oldStore.cancelChanges()
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
            return self.oldStore.state.data.creatorIds.count
        case .fields:
            return self.oldStore.state.data.fieldIds.count
        case .attachments:
            return self.oldStore.state.data.attachments.count
        case .notes:
            return self.oldStore.state.data.notes.count
        case .tags:
            return self.oldStore.state.data.tags.count
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
        return self.count(in: self.sections[section], isEditing: self.oldStore.state.isEditing)
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
        let isEditing = self.oldStore.state.isEditing
        let (section, cellId) = self.cellData(for: indexPath, isEditing: isEditing)
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)

        var hasSeparator = true

        switch section {
        case .abstract:
            if let cell = cell as? ItemDetailAbstractCell {
                cell.setup(with: (self.oldStore.state.data.abstract ?? ""), isEditing: isEditing)
            }

        case .title:
            if let cell = cell as? ItemDetailTitleCell {
                cell.setup(with: self.oldStore.state.data.title, isEditing: isEditing)
                cell.textObservable.subscribe(onNext: { [weak self] title in
                    if isEditing {
                        self?.oldStore.state.data.title = title
                    }
                }).disposed(by: self.disposeBag)
            }

        case .attachments:
                if let cell = cell as? ItemDetailAttachmentCell {
                    let attachment = self.oldStore.state.data.attachments[indexPath.row]
                    cell.setup(with: attachment,
                               progress: self.oldStore.state.downloadProgress[attachment.key],
                               error: self.oldStore.state.downloadError[attachment.key])
                } else if let cell = cell as? ItemDetailAddCell {
                    cell.setup(with: "Add attachment")
                }

        case .notes:
            if let cell = cell as? ItemDetailNoteCell {
                cell.setup(with: self.oldStore.state.data.notes[indexPath.row])
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: "Add note")
            }

        case .tags:
            if let cell = cell as? ItemDetailTagCell {
                cell.setup(with: self.oldStore.state.data.tags[indexPath.row])
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: "Add tag")
            }

        case .type:
            if let cell = cell as? ItemDetailFieldCell {
                cell.setup(with: self.oldStore.state.data.localizedType, title: "Item Type")
            }
            hasSeparator = false

        case .fields:
            if let cell = cell as? ItemDetailFieldCell {
                let fieldId = self.oldStore.state.data.fieldIds[indexPath.row]
                if let field = self.oldStore.state.data.fields[fieldId] {
                    cell.setup(with: field, isEditing: isEditing)
                    cell.textObservable.subscribe(onNext: { [weak self] value in
                        self?.oldStore.state.data.fields[fieldId]?.value = value
                    }).disposed(by: self.disposeBag)
                }
            }
            hasSeparator = false

        case .creators:
            if let cell = cell as? ItemDetailCreatorEditingCell {
                let creatorId = self.oldStore.state.data.creatorIds[indexPath.row]
                if let creator = self.oldStore.state.data.creators[creatorId] {
                    cell.setup(with: creator)
                    cell.namePresentationObservable.subscribe(onNext: { [weak self] namePresentation in
                        self?.oldStore.state.data.creators[creatorId]?.namePresentation = namePresentation
                    }).disposed(by: self.disposeBag)
                    cell.fullNameObservable.subscribe(onNext: { [weak self] fullName in
                        self?.oldStore.state.data.creators[creatorId]?.fullName = fullName
                    }).disposed(by: self.disposeBag)
                    cell.firstNameObservable.subscribe(onNext: { [weak self] firstName in
                        self?.oldStore.state.data.creators[creatorId]?.firstName = firstName
                    }).disposed(by: self.disposeBag)
                    cell.lastNameObservable.subscribe(onNext: { [weak self] lastName in
                        self?.oldStore.state.data.creators[creatorId]?.lastName = lastName
                    }).disposed(by: self.disposeBag)
                }
            } else if let cell = cell as? ItemDetailFieldCell {
                let creatorId = self.oldStore.state.data.creatorIds[indexPath.row]
                if let creator = self.oldStore.state.data.creators[creatorId] {
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
                    let date = ItemDetailViewController.dateFormatter.string(from: self.oldStore.state.data.dateAdded)
                    cell.setup(with: date, title: "Date Added")
                case 1:
                    let date = ItemDetailViewController.dateFormatter.string(from: self.oldStore.state.data.dateModified)
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
        self.oldStore.moveCreators(from: IndexSet([sourceIndexPath.row]), to: destinationIndexPath.row)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }

        switch self.sections[indexPath.section] {
        case .creators:
            self.oldStore.deleteCreators(at: [indexPath.row])
        case .tags:
            self.oldStore.deleteTags(at: [indexPath.row])
        case .attachments:
            self.oldStore.deleteAttachments(at: [indexPath.row])
        case .notes:
            self.oldStore.deleteNotes(at: [indexPath.row])
        case .title, .abstract, .fields, .type, .dates: break
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var animated = false

        switch self.sections[indexPath.section] {
        case .attachments:
            if self.oldStore.state.isEditing {
                if indexPath.row == self.oldStore.state.data.attachments.count {
                    NotificationCenter.default.post(name: .presentFilePicker, object: self.oldStore.addAttachments)
                    animated = true
                }
            } else {
                self.oldStore.openAttachment(self.oldStore.state.data.attachments[indexPath.row])
                animated = true
            }
        case .notes:
            if self.oldStore.state.isEditing && indexPath.row == self.oldStore.state.data.notes.count {
                self.oldStore.addNote()
                self.openNote(with: "")
                animated = true
            } else {
                let note = self.oldStore.state.data.notes[indexPath.row]
                self.oldStore.openNote(note)
                self.openNote(with: note.text)
                animated = true
            }
        case .tags:
            if self.oldStore.state.isEditing && indexPath.row == self.oldStore.state.data.tags.count {
                NotificationCenter.default.post(name: .presentTagPicker, object: (Set(self.oldStore.state.data.tags.map({ $0.id })), self.oldStore.state.libraryId, self.oldStore.setTags))
                animated = true
            }
        case .creators:
            if self.oldStore.state.isEditing && indexPath.row == self.oldStore.state.data.creators.count {
                self.oldStore.addCreator()
                animated = true
            }
        case .type:
            if self.oldStore.state.isEditing {
                if self.oldStore.state.data.type != ItemTypes.attachment {
                    NotificationCenter.default.post(name: .presentTypePicker, object: (self.oldStore.state.data.type, self.oldStore.changeType))
                }
                animated = true
            }
        case .title, .abstract, .fields, .dates: break
        }

        tableView.deselectRow(at: indexPath, animated: animated)
    }
}
