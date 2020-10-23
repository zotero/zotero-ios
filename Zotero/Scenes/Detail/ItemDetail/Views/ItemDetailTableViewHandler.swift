//
//  ItemDetailTableViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

/// Class for handling the `UITableView` of `ItemDetailViewController`. It takes care of showing appropriate data in the `tableView`, keeping track
/// of visible sections and reports actions that need to take place after user interaction with the `tableView`.
class ItemDetailTableViewHandler: NSObject {
    /// Actions that need to take place when user taps on some cells
    enum Action {
        case openCreatorTypePicker(ItemDetailState.Creator)
        case openNoteEditor(Note?)
        case openTagPicker
        case openTypePicker
        case openFilePicker
        case openUrl(String)
        case openDoi(String)
    }

    /// Sections that are shown in `tableView`
    enum Section: CaseIterable, Equatable, Hashable {
        case abstract, attachments, creators, dates, fields, notes, tags, title, type

        func cellId(isEditing: Bool) -> String {
            switch self {
            case .abstract:
                if isEditing {
                    return "ItemDetailAbstractEditCell"
                } else {
                    return "ItemDetailAbstractCell"
                }
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

    // Identifier for section view
    private static let sectionId = "ItemDetailSectionView"
    // Identifier for "Add *" cell
    private static let addCellId = "ItemDetailAddCell"
    private static let dateFormatter = createDateFormatter()
    private static let separatorLeftInset: CGFloat = 16
    private unowned let viewModel: ViewModel<ItemDetailActionHandler>
    private unowned let tableView: UITableView
    private let disposeBag: DisposeBag
    let observer: PublishSubject<Action>

    private var sections: [Section] = []
    // Width of title for field cells when editing is enabled (all fields are visible)
    private var maxTitleWidth: CGFloat = 0
    // Width of title for field cells when editing is disabled (only non-empty fields are visible)
    private var maxNonemptyTitleWidth: CGFloat = 0
    // Width of title for current state
    private var titleWidth: CGFloat {
        return self.viewModel.state.isEditing ? self.maxTitleWidth : self.maxNonemptyTitleWidth
    }
    private weak var fileDownloader: FileDownloader?

    var attachmentSection: Int {
        return self.sections.firstIndex(of: .attachments) ?? 0
    }

    init(tableView: UITableView, viewModel: ViewModel<ItemDetailActionHandler>, fileDownloader: FileDownloader?) {
        self.tableView = tableView
        self.viewModel = viewModel
        self.fileDownloader = fileDownloader
        self.observer = PublishSubject()
        self.disposeBag = DisposeBag()

        super.init()

        self.sections = self.sections(for: viewModel.state.data, isEditing: viewModel.state.isEditing)
        let (titleWidth, nonEmptyTitleWidth) = self.calculateTitleWidths(for: viewModel.state.data)
        self.maxTitleWidth = titleWidth
        self.maxNonemptyTitleWidth = nonEmptyTitleWidth
        self.setupTableView()
        self.setupKeyboardObserving()
    }

    private static func createDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy, h:mm:ss a"
        return formatter
    }

    private func createContextMenu(for attachment: Attachment) -> UIMenu? {
        guard attachment.contentType.fileLocation == .local else { return nil }
        let delete = UIAction(title: L10n.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] action in
            self?.viewModel.process(action: .deleteAttachmentFile(attachment)) 
        }
        return UIMenu(title: "", children: [delete])
    }

    func sourceDataForCell(at indexPath: IndexPath) -> (UIView, CGRect?) {
        return (self.tableView, self.tableView.cellForRow(at: indexPath)?.frame)
    }

    func updateAttachmentCell(with attachment: Attachment, at index: Int) {
        guard let section = self.sections.firstIndex(of: .attachments) else { return }
        let indexPath = IndexPath(row: index, section: section)

        if let cell = self.tableView.cellForRow(at: indexPath) as? ItemDetailAttachmentCell {
            let (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)
            cell.setup(with: attachment, progress: progress, error: error)
        }
    }

    /// Recalculates title width for current data.
    /// - parameter data: New data that change the title width.
    func reloadTitleWidth(from data: ItemDetailState.Data) {
        let (titleWidth, nonEmptyTitleWidth) = self.calculateTitleWidths(for: data)
        self.maxTitleWidth = titleWidth
        self.maxNonemptyTitleWidth = nonEmptyTitleWidth
    }

    /// Reloads given section (without header or footer) in `tableView`.
    /// - parameter section: Section to reload.
    func reload(section: Section) {
        guard let section = self.sections.firstIndex(of: section) else { return }
        let rows = self.tableView(self.tableView, numberOfRowsInSection: section)
        let indexPaths = (0..<rows).map({ IndexPath(row: $0, section: section) })
        self.tableView.reloadRows(at: indexPaths, with: .none)
    }

    /// Reloads all sections based on given state.
    /// - parameter state: New state that changes sections.
    func reloadSections(to state: ItemDetailState) {
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

    /// Reloads `tableView` based on diff.
    /// - parameter diff: Diff that changes the `tableView`.
    func reload(with diff: ItemDetailState.Diff) {
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

    /// Creates array of visible sections for current state data.
    /// - parameter data: New data.
    /// - parameter isEditing: Current editing table view state.
    /// - returns: Array of visible sections.
    private func sections(for data: ItemDetailState.Data, isEditing: Bool) -> [Section] {
        if isEditing {
            // Each section is visible during editing, except dates section. Dates are filled automatically and the user can't change them manually.
            return [.title, .type, .creators, .fields, .dates, .abstract, .notes, .tags, .attachments]
        }

        var sections: [Section] = [.title]
        // Item type is always visible
        sections.append(.type)
        if !data.creators.isEmpty {
            sections.append(.creators)
        }
        if !data.fieldIds.isEmpty {
            sections.append(.fields)
        }
        sections.append(.dates)
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

    /// Returns width of title for field cells for both editing and non-editing states.
    /// - parameter data: New data.
    /// - returns: Max field title width for editing and non-editing state.
    private func calculateTitleWidths(for data: ItemDetailState.Data) -> (CGFloat, CGFloat) {
        var maxTitle = ""
        var maxNonEmptyTitle = ""

        data.fields.values.forEach { field in
            if field.name.count > maxTitle.count {
                maxTitle = field.name
            }

            if !field.value.isEmpty && field.name.count > maxNonEmptyTitle.count {
                maxNonEmptyTitle = field.name
            }
        }

        let extraFields = [L10n.itemType, L10n.dateModified, L10n.dateAdded, L10n.abstract] + data.creators.values.map({ $0.localizedType })
        extraFields.forEach { name in
            if name.count > maxTitle.count {
                maxTitle = name
            }
            if name.count > maxNonEmptyTitle.count {
                maxNonEmptyTitle = name
            }
        }

        let maxTitleWidth = ceil(maxTitle.size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .headline)]).width)
        let maxNonemptyTitleWidth = ceil(maxNonEmptyTitle.size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .headline)]).width)
        return (maxTitleWidth, maxNonemptyTitleWidth)
    }

    /// Sets `tableView` dataSource, delegate and registers appropriate cells and sections.
    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none
        self.tableView.tableFooterView = UIView()
        self.tableView.layoutMargins = UIEdgeInsets()
        self.tableView.separatorInsetReference = .fromAutomaticInsets
        self.tableView.separatorInset = UIEdgeInsets(top: 0,
                                                     left: ItemDetailTableViewHandler.separatorLeftInset,
                                                     bottom: 0, right: 0)

        Section.allCases.forEach { section in
            let cellId = section.cellId(isEditing: false)
            self.tableView.register(UINib(nibName: cellId, bundle: nil), forCellReuseIdentifier: cellId)
            let cellIdEditing = section.cellId(isEditing: true)
            if cellId != cellIdEditing {
                self.tableView.register(UINib(nibName: cellIdEditing, bundle: nil), forCellReuseIdentifier: cellIdEditing)
            }
        }
        self.tableView.register(UINib(nibName: ItemDetailTableViewHandler.addCellId, bundle: nil),
                                forCellReuseIdentifier: ItemDetailTableViewHandler.addCellId)
        self.tableView.register(UINib(nibName: ItemDetailTableViewHandler.sectionId, bundle: nil),
                                forHeaderFooterViewReuseIdentifier: ItemDetailTableViewHandler.sectionId)
    }

    private func setupTableView(with keyboardData: KeyboardData) {
        var insets = self.tableView.contentInset
        insets.bottom = keyboardData.endFrame.height
        self.tableView.contentInset = insets
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
                          .keyboardWillShow
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }
}

extension ItemDetailTableViewHandler: UITableViewDataSource {
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
                cellId = ItemDetailTableViewHandler.addCellId
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
        let separatorHeight = 1 / UIScreen.main.scale
        switch self.sections[section] {
        case .notes, .attachments:
            return 44 + separatorHeight
        case .tags:
            return 54 // header height + 10 tag offset
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch self.sections[section] {
        case .notes:
            let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: ItemDetailTableViewHandler.sectionId) as? ItemDetailSectionView
            view?.setup(with: L10n.ItemDetail.notes)
            return view
        case .attachments:
            let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: ItemDetailTableViewHandler.sectionId) as? ItemDetailSectionView
            view?.setup(with: L10n.ItemDetail.attachments)
            return view
        case .tags:
            let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: ItemDetailTableViewHandler.sectionId) as? ItemDetailSectionView
            view?.setup(with: L10n.ItemDetail.tags)
            return view
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        switch self.sections[section] {
        case .title:
            return 10 - (1 / UIScreen.main.scale) // - separator height
        case .abstract:
            return 8
        case .dates, .tags:
            return 10 + (1 / UIScreen.main.scale) // + separator height
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        switch self.sections[section] {
        case .abstract, .title, .dates, .tags:
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
            if let cell = cell as? ItemDetailAbstractEditCell {
                cell.setup(with: (self.viewModel.state.data.abstract ?? ""))
                cell.textObservable.subscribe(onNext: { [weak self] abstract in
                    if isEditing {
                        self?.viewModel.process(action: .setAbstract(abstract))
                    }
                }).disposed(by: cell.newDisposeBag)
            } else if let cell = cell as? ItemDetailAbstractCell {
                cell.setup(with: (self.viewModel.state.data.abstract ?? ""), isCollapsed: self.viewModel.state.abstractCollapsed)
            }
            hasSeparator = false

        case .title:
            if let cell = cell as? ItemDetailTitleCell {
                cell.setup(with: self.viewModel.state.data.title, isEditing: isEditing, placeholder: L10n.ItemDetail.untitled)
                cell.textObservable.subscribe(onNext: { [weak self] title in
                    if isEditing {
                        self?.viewModel.process(action: .setTitle(title))
                    }
                }).disposed(by: cell.newDisposeBag)
            }

        case .attachments:
                if let cell = cell as? ItemDetailAttachmentCell {
                    let attachment = self.viewModel.state.data.attachments[indexPath.row]
                    let (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)
                    cell.setup(with: attachment, progress: progress, error: error)
                } else if let cell = cell as? ItemDetailAddCell {
                    cell.setup(with: L10n.ItemDetail.addAttachment)
                }

        case .notes:
            if let cell = cell as? ItemDetailNoteCell {
                cell.setup(with: self.viewModel.state.data.notes[indexPath.row])
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: L10n.ItemDetail.addNote)
            }

        case .tags:
            if let cell = cell as? ItemDetailTagCell {
                cell.setup(with: self.viewModel.state.data.tags[indexPath.row])
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: L10n.ItemDetail.addTag)
            }
            hasSeparator = isEditing

        case .type:
            if let cell = cell as? ItemDetailFieldCell {
                cell.setup(with: self.viewModel.state.data.localizedType, title: L10n.itemType, titleWidth: self.titleWidth)
            }
            hasSeparator = isEditing

        case .fields:
            if let cell = cell as? ItemDetailFieldCell {
                let fieldId = self.viewModel.state.data.fieldIds[indexPath.row]
                if let field = self.viewModel.state.data.fields[fieldId] {
                    cell.setup(with: field, isEditing: isEditing, titleWidth: self.titleWidth)
                    cell.textObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .setFieldValue(id: fieldId, value: value))
                    }).disposed(by: cell.newDisposeBag)
                }
            }
            hasSeparator = isEditing

        case .creators:
            if let cell = cell as? ItemDetailCreatorEditingCell {
                let creatorId = self.viewModel.state.data.creatorIds[indexPath.row]
                if let creator = self.viewModel.state.data.creators[creatorId] {
                    cell.setup(with: creator)
                    cell.typeObservable.subscribe(onNext: { [weak self] _ in
                        self?.observer.on(.next(.openCreatorTypePicker(creator)))
                    }).disposed(by: cell.newDisposeBag)
                    cell.namePresentationObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .updateCreator(creatorId, .namePresentation(value)))
                    }).disposed(by: cell.disposeBag)
                    cell.fullNameObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .updateCreator(creatorId, .fullName(value)))
                    }).disposed(by: cell.disposeBag)
                    cell.firstNameObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .updateCreator(creatorId, .firstName(value)))
                    }).disposed(by: cell.disposeBag)
                    cell.lastNameObservable.subscribe(onNext: { [weak self] value in
                        self?.viewModel.process(action: .updateCreator(creatorId, .lastName(value)))
                    }).disposed(by: cell.disposeBag)
                }
            } else if let cell = cell as? ItemDetailFieldCell {
                let creatorId = self.viewModel.state.data.creatorIds[indexPath.row]
                if let creator = self.viewModel.state.data.creators[creatorId] {
                    cell.setup(with: creator, titleWidth: self.titleWidth)
                }
            } else if let cell = cell as? ItemDetailAddCell {
                cell.setup(with: L10n.ItemDetail.addCreator)
            }
            hasSeparator = isEditing

        case .dates:
            if let cell = cell as? ItemDetailFieldCell {
                switch indexPath.row {
                case 0:
                    let date = ItemDetailTableViewHandler.dateFormatter.string(from: self.viewModel.state.data.dateAdded)
                    cell.setup(with: date, title: L10n.dateAdded, titleWidth: self.titleWidth)
                case 1:
                    let date = ItemDetailTableViewHandler.dateFormatter.string(from: self.viewModel.state.data.dateModified)
                    cell.setup(with: date, title: L10n.dateModified, titleWidth: self.titleWidth)
                default: break
                }
            }
            hasSeparator = isEditing || indexPath.row == self.count(in: .dates, isEditing: isEditing) - 1
        }

        let left: CGFloat = hasSeparator ? 0 : .greatestFiniteMagnitude
        cell.separatorInset = UIEdgeInsets(top: 0, left: left, bottom: 0, right: 0)

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

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard self.sections[indexPath.section] == .attachments else { return nil }

        let attachment = self.viewModel.state.data.attachments[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ -> UIMenu? in
            return self?.createContextMenu(for: attachment)
        }
    }
}

extension ItemDetailTableViewHandler: UITableViewDelegate {
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
                    self.observer.on(.next(.openFilePicker))
                }
            } else {
                self.viewModel.process(action: .openAttachment(indexPath.row))
            }
        case .notes:
            if self.viewModel.state.isEditing && indexPath.row == self.viewModel.state.data.notes.count {
                self.observer.on(.next(.openNoteEditor(nil)))
            } else {
                let note = self.viewModel.state.data.notes[indexPath.row]
                self.observer.on(.next(.openNoteEditor(note)))
            }
        case .tags:
            if self.viewModel.state.isEditing && indexPath.row == self.viewModel.state.data.tags.count {
                self.observer.on(.next(.openTagPicker))
            }
        case .creators:
            if self.viewModel.state.isEditing && indexPath.row == self.viewModel.state.data.creators.count {
                self.viewModel.process(action: .addCreator)
            }
        case .type:
            if self.viewModel.state.isEditing {
                if self.viewModel.state.data.type != ItemTypes.attachment {
                    self.observer.on(.next(.openTypePicker))
                }
            }
        case .fields:
            let fieldId = self.viewModel.state.data.fieldIds[indexPath.row]
            if let field = self.viewModel.state.data.fields[fieldId] {
                guard field.isTappable else { return }
                switch field.key {
                case FieldKeys.Item.Attachment.url:
                    self.observer.on(.next(.openUrl(field.value)))
                case FieldKeys.Item.doi:
                    self.observer.on(.next(.openDoi(field.value)))
                default: break
                }
            }
        case .abstract:
            if !self.viewModel.state.isEditing {
                self.viewModel.process(action: .toggleAbstractDetailCollapsed)
            }
        case .title, .dates: break
        }
    }
}
