//
//  ItemDetailViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit

import RxSwift

class ItemDetailViewController: UIViewController {
    private enum Section: CaseIterable {
        case abstract, attachments, creators, fields, notes, tags, title

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
            case .fields:
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
    private var storeSubscriber: AnyCancellable?

    private static let sectionId = "ItemDetailSectionView"
    private static let addCellId = "ItemDetailAddCell"
    private static let dateFormatter: DateFormatter = createDateFormatter()
    private let store: ItemDetailStore
    private let disposeBag: DisposeBag

    private static func createDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy, h:mm:ss a"
        return formatter
    }

    init(store: ItemDetailStore) {
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

        self.setNavigationBarEditingButton(toEditing: self.store.state.isEditing)
        self.tableView.setEditing(self.store.state.isEditing, animated: false)
        self.reloadSections(isEditing: self.store.state.isEditing, animated: false)

        self.storeSubscriber = self.store.$state.receive(on: DispatchQueue.main)
                                                .dropFirst()
                                                .sink(receiveValue: { [weak self] state in
                                                    self?.update(to: state)
                                                })
    }

    // MARK: - Actions

    private func update(to state: ItemDetailStore.State) {
        if state.isEditing != self.tableView.isEditing {
            self.setNavigationBarEditingButton(toEditing: state.isEditing)
            self.reloadSections(isEditing: state.isEditing, animated: true)
            self.tableView.setEditing(state.isEditing, animated: true)
        }
    }

    private func reloadSections(isEditing: Bool, animated: Bool) {
        if !animated {
            self.sections = self.sections(for: self.store.state.data, isEditing: isEditing)
            self.tableView.reloadData()
        }

        // TODO: - create diff, reload sections with animation based on diff
        let oldSections = self.sections
        self.sections = self.sections(for: self.store.state.data, isEditing: isEditing)
        self.tableView.reloadData()
    }

    private func sections(for data: ItemDetailStore.State.Data, isEditing: Bool) -> [Section] {
        if isEditing {
            // Each section is visible during editing, so that the user can actually edit them
            return [.title, .creators, .fields, .abstract, .notes, .tags, .attachments]
        }

        var sections: [Section] = []
        if !data.title.isEmpty {
            sections.append(.title)
        }
        if !data.creators.isEmpty {
            sections.append(.creators)
        }
        // Fields always contain at least dates, so they are always visible
        sections.append(.fields)
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

    private func setNavigationBarEditingButton(toEditing editing: Bool) {
        if !editing {
            let button = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)
            button.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.store.startEditing()
                         })
                         .disposed(by: self.disposeBag)
            self.navigationItem.rightBarButtonItems = [button]
            return
        }

        let saveButton = UIBarButtonItem(title: "Save", style: .plain, target: nil, action: nil)
        saveButton.rx.tap.subscribe(onNext: { [weak self] _ in
                             self?.store.saveChanges()
                         })
                         .disposed(by: self.disposeBag)

        let cancelButton = UIBarButtonItem(title: "Cancel", style: .plain, target: nil, action: nil)
        cancelButton.rx.tap.subscribe(onNext: { [weak self] _ in
                               self?.store.cancelChanges()
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
    private func baseCount(in section: Section) -> Int {
        switch section {
        case .abstract, .title:
            return 1
        case .creators:
            return self.store.state.data.creatorIds.count
        case .fields:
            return self.store.state.data.fieldIds.count
        case .attachments:
            return self.store.state.data.attachments.count
        case .notes:
            return self.store.state.data.notes.count
        case .tags:
            return self.store.state.data.tags.count
        }
    }

    private func count(in section: Section, isEditing: Bool) -> Int {
        let base = self.baseCount(in: section)
        var additional = 0

        switch section {
        case .abstract, .title: break
        case .creators, .attachments, .notes, .tags:
            // +1 for add button
            additional = isEditing ? 1 : 0
        case .fields:
            // +2 for date added and date modified
            additional = isEditing ? 0 : 2
        }

        return base + additional
    }

    private func cellData(for indexPath: IndexPath, isEditing: Bool) -> (Section, String) {
        let section = self.sections[indexPath.section]
        let cellId: String

        switch section {
        case .fields, .abstract, .title:
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
        return self.count(in: self.sections[section], isEditing: self.store.state.isEditing)
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
        let (section, cellId) = self.cellData(for: indexPath, isEditing: self.store.state.isEditing)
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)

        cell.separatorInset = UIEdgeInsets(top: 0, left: cell.layoutMargins.left, bottom: 0, right: 0)

        switch section {
        case .abstract:
            if let cell = cell as? ItemDetailAbstractCell {
                cell.setup(with: (self.store.state.data.abstract ?? ""), isEditing: self.store.state.isEditing)
            }

        case .title:
            if let cell = cell as? ItemDetailTitleCell {
                cell.setup(with: self.store.state.data.title, isEditing: self.store.state.isEditing)
            }

        case .attachments:
                if let cell = cell as? ItemDetailAttachmentCell {
                    let attachment = self.store.state.data.attachments[indexPath.row]
                    cell.setup(with: attachment,
                               progress: self.store.state.downloadProgress[attachment.key],
                               error: self.store.state.downloadError[attachment.key])
                } else if let cell = cell as? ItemDetailAddCell {
                    cell.setup(with: "Add attachment")
                }

        case .creators:
            if let cell = cell as? ItemDetailCreatorEditingCell {
                let creatorId = self.store.state.data.creatorIds[indexPath.row]
                if let creator = self.store.state.data.creators[creatorId] {
                    cell.setup(with: creator)
                }
            } else if let cell = cell as? ItemDetailFieldCell {
                let creatorId = self.store.state.data.creatorIds[indexPath.row]
                if let creator = self.store.state.data.creators[creatorId] {
                    cell.setup(with: creator)
                }
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: "Add creator")
            }
            cell.separatorInset = UIEdgeInsets(top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0)

        case .fields:
            if let cell = cell as? ItemDetailFieldCell {
                let baseCount = self.baseCount(in: .fields)
                if indexPath.row < baseCount {
                    let fieldId = self.store.state.data.fieldIds[indexPath.row]
                    if let field = self.store.state.data.fields[fieldId] {
                        cell.setup(with: field, isEditing: self.store.state.isEditing)
                    }
                } else {
                    let index = indexPath.row - baseCount
                    switch index {
                    case 0:
                        let date = ItemDetailViewController.dateFormatter.string(from: self.store.state.data.dateAdded)
                        cell.setup(with: date, title: "Date Added")
                    case 1:
                        let date = ItemDetailViewController.dateFormatter.string(from: self.store.state.data.dateModified)
                        cell.setup(with: date, title: "Date Modified")
                    default: break
                    }
                }
            }
            cell.separatorInset = UIEdgeInsets(top: 0, left: .greatestFiniteMagnitude, bottom: 0, right: 0)

        case .notes:
            if let cell = cell as? ItemDetailNoteCell {
                cell.setup(with: self.store.state.data.notes[indexPath.row])
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: "Add note")
            }

        case .tags:
            if let cell = cell as? ItemDetailTagCell {
                cell.setup(with: self.store.state.data.tags[indexPath.row])
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: "Add tag")
            }
        }

        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let section = self.sections[indexPath.section]
        let rows = self.baseCount(in: section)
        switch section {
        case .creators, .attachments, .notes, .tags:
            return indexPath.row < rows
        case .title, .abstract, .fields:
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
        // TODO: - move creators
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }

        switch self.sections[indexPath.section] {
        case .creators: break
            // TODO: - delete creator
        case .tags: break
            // TODO: - delete tag
        case .attachments: break
            // TODO: - delete attachment
        case .notes: break
            // TODO: - delete note
        case .title, .abstract, .fields: break
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var animated = false

        switch self.sections[indexPath.section] {
        case .attachments:
            if self.store.state.isEditing {
                if indexPath.row == self.store.state.data.attachments.count {
                    // TODO: - Add attachment
                    animated = true
                }
            } else {
                // TODO: - Open attachment
                animated = true
            }
        case .notes:
            if self.store.state.isEditing {
                // TODO: - Add note
                animated = true
            } else {
                // TODO: - Open note
                animated = true
            }
        case .tags:
            if self.store.state.isEditing && indexPath.row == self.store.state.data.tags.count {
                // TODO: - Add tag
                animated = true
            }
        case .creators:
            if self.store.state.isEditing && indexPath.row == self.store.state.data.creators.count {
                // TODO: - Add creator
                animated = true
            }
        case .title, .abstract, .fields: break
        }

        tableView.deselectRow(at: indexPath, animated: animated)
    }
}
