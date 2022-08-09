//
//  ItemDetailTableViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

protocol ItemDetailTableViewHandlerDelegate: AnyObject {
    func isDownloadingFromNavigationBar(for key: String) -> Bool
}

/// Class for handling the `UITableView` of `ItemDetailViewController`. It takes care of showing appropriate data in the `tableView`, keeping track
/// of visible sections and reports actions that need to take place after user interaction with the `tableView`.
final class ItemDetailTableViewHandler: NSObject {
    /// Actions that need to take place when user taps on some cells
    enum Action {
        case openCreatorCreation
        case openCreatorEditor(ItemDetailState.Creator)
        case openNoteEditor(Note?)
        case openTagPicker
        case openTypePicker
        case openFilePicker
        case openUrl(String)
        case openDoi(String)
        case trashAttachment(Attachment)
    }

    /// Sections that are shown in `tableView`.
    enum Section: Equatable, Hashable {
        case abstract
        case attachments
        case creators
        case dates
        case fields
        case notes
        case tags
        case title
        case type
    }

    /// `UITableViewDiffableDataSource` has a bug where it doesn't reload sections which are in `reloadSections` of its snapshot, but if sections are actually different, the snapshot will reload them.
    /// So we'll use `String` identifiers for all sections so that we can reload them manually.
    fileprivate struct SectionType: Equatable, Hashable {
        let identifier: String
        let section: Section
    }

    enum Row: Hashable, Equatable {
        case addNote
        case addAttachment
        case addCreator
        case addTag
        case abstract
        case attachment(attachment: Attachment, progress: CGFloat?, error: Error?, enabled: Bool)
        case creator(ItemDetailState.Creator)
        case dateAdded(Date)
        case dateModified(Date)
        case field(key: String, multiline: Bool)
        case note(note: Note, isSaving: Bool)
        case tag(Tag)
        case title
        case type(String)

        func cellId(isEditing: Bool) -> String {
            switch self {
            case .abstract:
                if isEditing {
                    return "ItemDetailAbstractEditCell"
                } else {
                    return "ItemDetailAbstractCell"
                }
            case .attachment:
                return "ItemDetailAttachmentCell"
            case .note:
                return "ItemDetailNoteCell"
            case .tag:
                return "ItemDetailTagCell"
            case .field(_, let multiline):
                if isEditing {
                    if multiline {
                        return "ItemDetailFieldMultilineEditCell"
                    } else {
                        return "ItemDetailFieldEditCell"
                    }
                } else {
                    return "ItemDetailFieldCell"
                }
            case .type, .dateAdded, .dateModified, .creator:
                return "ItemDetailFieldCell"
            case .title:
                return "ItemDetailTitleCell"
            case .addNote, .addAttachment, .addCreator, .addTag:
                return "ItemDetailAddCell"
            }
        }

        static func == (lhs: ItemDetailTableViewHandler.Row, rhs: ItemDetailTableViewHandler.Row) -> Bool {
            switch (lhs, rhs) {
            case (.addNote, .addNote), (.addCreator, .addCreator), (.addTag, .addTag), (.addAttachment, .addAttachment):
                return true
            case (.abstract, .abstract):
                return true
            case (.attachment(let lAttachment, let lProgress, let lError, let lEnabled), .attachment(let rAttachment, let rProgress, let rError, let rEnabled)):
                return lAttachment == rAttachment && lProgress == rProgress && lError?.localizedDescription == rError?.localizedDescription && lEnabled == rEnabled
            case (.creator(let lCreator), .creator(let rCreator)):
                return lCreator == rCreator
            case (.dateAdded(let lDate), .dateAdded(let rDate)):
                return lDate == rDate
            case (.dateModified(let lDate), .dateModified(let rDate)):
                return lDate == rDate
            case (.field(let lKey, let lMultiline), .field(let rKey, let rMultiline)):
                return lKey == rKey && lMultiline == rMultiline
            case (.note(let lNote, let lIsSaving), .note(let rNote, let rIsSaving)):
                return lNote == rNote && lIsSaving == rIsSaving
            case (.tag(let lTag), .tag(let rTag)):
                return lTag == rTag
            case (.title, .title):
                return true
            case (.type(let lValue), .type(let rValue)):
                return lValue == rValue
            default:
                return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .abstract:
                hasher.combine(1)
            case .attachment(let attachment, let progress, let error, let enabled):
                hasher.combine(2)
                hasher.combine(attachment)
                hasher.combine(progress)
                hasher.combine(error?.localizedDescription)
                hasher.combine(enabled)
            case .creator(let creator):
                hasher.combine(3)
                hasher.combine(creator)
            case .dateAdded(let date):
                hasher.combine(4)
                hasher.combine(date)
            case .dateModified(let date):
                hasher.combine(5)
                hasher.combine(date)
            case .field(let field, let multiline):
                hasher.combine(6)
                hasher.combine(field)
                hasher.combine(multiline)
            case .note(let note, let isSaving):
                hasher.combine(7)
                hasher.combine(note)
                hasher.combine(isSaving)
            case .tag(let tag):
                hasher.combine(8)
                hasher.combine(tag)
            case .title:
                hasher.combine(9)
            case .type(let value):
                hasher.combine(10)
                hasher.combine(value)
            case .addTag:
                hasher.combine(11)
            case .addNote:
                hasher.combine(12)
            case .addCreator:
                hasher.combine(13)
            case .addAttachment:
                hasher.combine(14)
            }
        }

        func isAttachment(withKey key: String) -> Bool {
            switch self {
            case .attachment(let attachment, _, _, _):
                return attachment.key == key
            default:
                return false
            }
        }
    }

    // Identifier for section view
    private static let sectionId = "ItemDetailSectionView"
    private static let cellIds: [String] = ["ItemDetailAddCell", "ItemDetailFieldCell", "ItemDetailFieldEditCell", "ItemDetailFieldMultilineEditCell", "ItemDetailTagCell", "ItemDetailNoteCell",
                                            "ItemDetailAttachmentCell", "ItemDetailAbstractCell", "ItemDetailAbstractEditCell", "ItemDetailTitleCell"]

    private unowned let viewModel: ViewModel<ItemDetailActionHandler>
    private unowned let tableView: UITableView
    private let disposeBag: DisposeBag
    let observer: PublishSubject<Action>

    // Width of title for field cells when editing is enabled (all fields are visible)
    private var maxTitleWidth: CGFloat = 0
    // Width of title for field cells when editing is disabled (only non-empty fields are visible)
    private var maxNonemptyTitleWidth: CGFloat = 0
    private var dataSource: TableViewDiffableDataSource<SectionType, Row>!
    private weak var fileDownloader: AttachmentDownloader?
    weak var delegate: ItemDetailTableViewHandlerDelegate?

    var attachmentSectionIndex: Int? {
        return self.dataSource?.snapshot().sectionIdentifiers.firstIndex(where: { $0.section == .attachments })
    }

    init(tableView: UITableView, containerWidth: CGFloat, viewModel: ViewModel<ItemDetailActionHandler>, fileDownloader: AttachmentDownloader?) {
        self.tableView = tableView
        self.viewModel = viewModel
        self.fileDownloader = fileDownloader
        self.observer = PublishSubject()
        self.disposeBag = DisposeBag()

        super.init()

        let (titleWidth, nonEmptyTitleWidth) = self.calculateTitleWidths(for: viewModel.state.data)
        self.maxTitleWidth = titleWidth
        self.maxNonemptyTitleWidth = nonEmptyTitleWidth
        self.setupTableView()
        self.setupKeyboardObserving()
    }

    deinit {
        DDLogInfo("ItemDetailTableViewHandler deinitialized")
    }

    // MARK: - Actions

    func sourceDataForCell(at indexPath: IndexPath) -> (UIView, CGRect?) {
        return (self.tableView, self.tableView.cellForRow(at: indexPath)?.frame)
    }

    /// Recalculates title width for current data.
    /// - parameter data: New data that change the title width.
    func recalculateTitleWidth(from data: ItemDetailState.Data) {
        let (titleWidth, nonEmptyTitleWidth) = self.calculateTitleWidths(for: data)
        self.maxTitleWidth = titleWidth
        self.maxNonemptyTitleWidth = nonEmptyTitleWidth
    }

    /// Reloads the whole `tableView`. Applies new snapshot based on `state` and reloads remaining items which were not changed between snapshots.
    /// - parameter state: State to which we're reloading the table view.
    /// - parameter animated: `true` if the change is animated, `false` otherwise.
    func reloadAll(to state: ItemDetailState, animated: Bool) {
        // Assign new id to all sections, just reload everything
        let id = UUID().uuidString
        let sections = self.sections(for: state.data, isEditing: state.isEditing).map({ SectionType(identifier: id, section: $0) })
        var snapshot = NSDiffableDataSourceSnapshot<SectionType, Row>()
        snapshot.appendSections(sections)
        for section in sections {
            snapshot.appendItems(self.rows(for: section.section, state: state), toSection: section)
        }

        self.tableView.setEditing(state.isEditing, animated: animated)
        self.dataSource.apply(snapshot, animatingDifferences: animated, completion: nil)
    }

    /// Rows to reload when doing a full reload of table view.
    /// - parameter oldSnapshot: Previous snapshot.
    /// - parameter newSnapshot: New snapshot which will be applied.
    /// - returns: Array of rows to reload.
    private func sectionsToReload(from oldSnapshot: NSDiffableDataSourceSnapshot<Section, Row>, to newSnapshot: NSDiffableDataSourceSnapshot<Section, Row>) -> [Section] {
        var toReload: [Section] = []
        for section in oldSnapshot.sectionIdentifiers {
            if newSnapshot.sectionIdentifiers.contains(section) {
                toReload.append(section)
            }
        }
        return toReload
    }

    /// Reloads specific section based on snapshot diff. In case of special sections (`title`, `abstract` and `fields`) which don't hold their respective values, their item(s) are always reloaded.
    /// - parameter section: Section to reload.
    /// - parameter state: Current item detail state.
    /// - parameter animated: `true` if change is animated, `false` otherwise.
    func reload(section: Section, state: ItemDetailState, animated: Bool) {
        var snapshot = self.dataSource.snapshot()

        guard let sectionType = snapshot.sectionIdentifiers.first(where: { $0.section == section }) else { return }

        let oldRows = snapshot.itemIdentifiers(inSection: sectionType)
        let newRows = self.rows(for: section, state: state)
        snapshot.deleteItems(oldRows)
        snapshot.appendItems(newRows, toSection: sectionType)

        let toReload = self.rowsToReload(from: oldRows, to: newRows, in: section)
        if !toReload.isEmpty {
            snapshot.reloadItems(toReload)
        }

        self.dataSource.apply(snapshot, animatingDifferences: animated, completion: nil)
    }

    /// Returns an array of rows which need to be reloaded manually. Some sections are "special" because their rows don't hold the values which they show in table view, they just hold their
    /// identifiers which don't change. So if the value changes, we have to manually reload these rows.
    /// - parameter oldRows: Rows from previous snapshot.
    /// - parameter newRows: Rows from new snapshot.
    /// - parameter section: Section of given rows.
    /// - returns: Array of rows to reload.
    private func rowsToReload(from oldRows: [Row], to newRows: [Row], in section: Section) -> [Row] {
        switch section {
        case .title:
            // Always reload title, if reload is requested, the value changed.
            return [.title]

        case .abstract:
            // Always reload abstract, if reload is requested, the value changed.
            return [.abstract]

        case .fields:
            // Reload fields which weren't removed.
            var toReload: [Row] = []
            for row in oldRows {
                if newRows.contains(row) {
                    toReload.append(row)
                }
            }
            return toReload

        default:
            // Rows in other sections hold their respective values, so they will reload based on the diff.
            return []
        }
    }

    /// Update height of updated cell and scroll to it. The cell itself doesn't need to be reloaded, since the change took place inside of it (text field or text view).
    func updateHeightAndScrollToUpdated(row: Row, state: ItemDetailState) {
        guard let indexPath = self.dataSource.indexPath(for: row) else { return }
        self.updateCellHeightsAndScroll(to: indexPath)
    }

    func updateAttachment(with attachment: Attachment) {
        var snapshot = self.dataSource.snapshot()

        guard let section = snapshot.sectionIdentifiers.first(where: { $0.section == .attachments }) else { return }

        var rows = snapshot.itemIdentifiers(inSection: section)

        guard let index = rows.firstIndex(where: { $0.isAttachment(withKey: attachment.key) }) else { return }

        let enabled = self.delegate?.isDownloadingFromNavigationBar(for: attachment.key) == false
        var progress: CGFloat?
        var error: Error?
        if enabled {
            (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)
        }

        snapshot.deleteItems(rows)
        rows[index] = Row.attachment(attachment: attachment, progress: progress, error: error, enabled: enabled)
        snapshot.appendItems(rows, toSection: section)

        self.dataSource.apply(snapshot, animatingDifferences: false, completion: nil)
    }

    private func updateCellHeightsAndScroll(to indexPath: IndexPath) {
        UIView.setAnimationsEnabled(false)
        self.tableView.beginUpdates()
        self.tableView.endUpdates()

        let cellFrame =  self.tableView.rectForRow(at: indexPath)
        let cellBottom = cellFrame.maxY - self.tableView.contentOffset.y
        let tableViewBottom = self.tableView.superview!.bounds.maxY - self.tableView.contentInset.bottom
        let safeAreaTop = self.tableView.superview!.safeAreaInsets.top

        // Scroll either when cell bottom is below keyboard or cell top is not visible on screen
        if cellBottom > tableViewBottom || cellFrame.minY < (safeAreaTop + self.tableView.contentOffset.y) {
            // Scroll to top if cell is smaller than visible screen, so that it's fully visible, otherwise scroll to bottom.
            let position: UITableView.ScrollPosition = cellFrame.height + safeAreaTop < tableViewBottom ? .top : .bottom
            self.tableView.scrollToRow(at: indexPath, at: position, animated: false)
        }
        UIView.setAnimationsEnabled(true)
    }

    // MARK: - Data Helpers

    /// Creates array of visible sections for current state data.
    /// - parameter data: New data.
    /// - parameter isEditing: Current editing table view state.
    /// - returns: Array of visible sections.
    private func sections(for data: ItemDetailState.Data, isEditing: Bool) -> [Section] {
        if isEditing {
            if data.isAttachment {
                return [.title, .type, .fields, .dates, .tags, .attachments]
            } else {
                // Each section is visible during editing, except dates section. Dates are filled automatically and the user can't change them manually.
                return [.title, .type, .creators, .fields, .dates, .abstract, .notes, .tags, .attachments]
            }
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
        sections.append(contentsOf: [.notes, .tags, .attachments])

        return sections
    }

    private func rows(for section: Section, state: ItemDetailState) -> [Row] {
        switch section {
        case .abstract:
            return [.abstract]

        case .attachments:
            let attachments: [Row] = state.attachments.map({ attachment in
                let enabled = self.delegate?.isDownloadingFromNavigationBar(for: attachment.key) == false
                var progress: CGFloat?
                var error: Error?

                if enabled {
                    (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)
                }

                return .attachment(attachment: attachment, progress: progress, error: error, enabled: enabled)
            })
            return attachments + [.addAttachment]

        case .creators:
            let creators: [Row] = state.data.creatorIds.compactMap({ creatorId in
                guard let creator = state.data.creators[creatorId] else { return nil }
                return .creator(creator)
            })

            if state.isEditing {
                return creators + [.addCreator]
            }
            return creators

        case .dates:
            return [.dateAdded(state.data.dateAdded), .dateModified(state.data.dateModified)]

        case .fields:
            return state.data.fieldIds.compactMap({ fieldId in
                return .field(key: fieldId, multiline: (fieldId == FieldKeys.Item.extra))
            })

        case .notes:
            let notes: [Row] = state.notes.map({ note in
                let isSaving = state.savingNotes.contains(note.key)
                return .note(note: note, isSaving: isSaving)
            })
            return notes + [.addNote]

        case .tags:
            let tags: [Row] = state.tags.map({ tag in
                return .tag(tag)
            })
            return tags + [.addTag]

        case .title:
            return [.title]

        case .type:
            return [.type(state.data.localizedType)]
        }
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

    // MARK: - Delegate Helpers

    private func createContextMenu(for attachment: Attachment) -> UIMenu? {
        guard !self.viewModel.state.data.isAttachment else { return nil }

        var actions: [UIAction] = []

        if case .file(_, _, let location, _) = attachment.type, location == .local {
            actions.append(UIAction(title: L10n.ItemDetail.deleteAttachmentFile, image: UIImage(systemName: "trash"), attributes: []) { [weak self] action in
                self?.viewModel.process(action: .deleteAttachmentFile(attachment))
            })
        }

        actions.append(UIAction(title: L10n.ItemDetail.trashAttachment, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] action in
            self?.viewModel.process(action: .trashAttachment(attachment))
        })

        return UIMenu(title: "", children: actions)
    }

    private func createContextMenu(for field: ItemDetailState.Field) -> UIMenu? {
        guard ((field.key == FieldKeys.Item.doi || field.baseField == FieldKeys.Item.doi) || (field.key == FieldKeys.Item.url || field.baseField == FieldKeys.Item.url)) else { return nil }
        return UIMenu(title: "", children: [UIAction(title: L10n.copy, handler: { _ in
            UIPasteboard.general.string = field.value
        })])
    }

    // MARK: - DataSource Helpers

    private func setup(cell: UITableViewCell, section: Section, row: Row, indexPath: IndexPath, isAddCell: Bool, isEditing: Bool) {
//        let isFirst = indexPath.row == 0
//        let isLast = indexPath.row == (self.dataSource.tableView(self.tableView, numberOfRowsInSection: indexPath.section) - 1)
//        let titleWidth = isEditing ? self.maxTitleWidth : self.maxNonemptyTitleWidth
//        let (separatorInsets, layoutMargins, accessoryType) = self.cellLayoutData(for: section, isFirstRow: isFirst, isLastRow: isLast, isAddCell: isAddCell, isEditing: isEditing)
//
//        cell.separatorInset = separatorInsets
//        cell.layoutMargins = layoutMargins
//        cell.contentView.layoutMargins = layoutMargins
//        if isEditing {
//            cell.editingAccessoryType = accessoryType
//        } else {
//            cell.accessoryType = accessoryType
//        }
//        cell.accessibilityTraits = []

//        switch row {
//        case .addNote:
//            if let cell = cell as? ItemDetailAddCell {
//                cell.setup(with: L10n.ItemDetail.addNote)
//            }
//
//        case .addTag:
//            if let cell = cell as? ItemDetailAddCell {
//                cell.setup(with: L10n.ItemDetail.addTag)
//            }
//
//        case .addCreator:
//            if let cell = cell as? ItemDetailAddCell {
//                cell.setup(with: L10n.ItemDetail.addCreator)
//            }
//
//        case .addAttachment:
//            if let cell = cell as? ItemDetailAddCell {
//                cell.setup(with: L10n.ItemDetail.addAttachment)
//            }
//
//        case .abstract:
//            let value = self.viewModel.state.data.abstract ?? ""
//            if let cell = cell as? ItemDetailAbstractEditCell {
//                cell.setup(with: value)
//                cell.textObservable.subscribe(onNext: { [weak self] abstract in
//                    guard isEditing else { return }
//                    self?.viewModel.process(action: .setAbstract(abstract))
//                }).disposed(by: cell.newDisposeBag)
//            } else if let cell = cell as? ItemDetailAbstractCell {
//                cell.setup(with: value, isCollapsed: self.viewModel.state.abstractCollapsed)
//            }
//
//        case .attachment(let attachment, let progress, let error, let enabled):
//            if let cell = cell as? ItemDetailAttachmentCell {
//                cell.selectionStyle = self.canTap(attachmentType: attachment.type, isEditing: isEditing) ? .gray : .none
//                cell.setup(with: attachment, progress: progress, error: error, enabled: enabled)
//            }
//
//        case .creator(let creator):
//            if let cell = cell as? ItemDetailFieldCell {
//                cell.setup(with: creator, titleWidth: titleWidth)
//            }
//
//        case .dateAdded(let date):
//            if let cell = cell as? ItemDetailFieldCell {
//                let date = Formatter.dateAndTime.string(from: date)
//                cell.setup(with: date, title: L10n.dateAdded, titleWidth: titleWidth)
//            }
//
//        case .dateModified(let date):
//            if let cell = cell as? ItemDetailFieldCell {
//                let date = Formatter.dateAndTime.string(from: date)
//                cell.setup(with: date, title: L10n.dateModified, titleWidth: titleWidth)
//            }
//
//        case .field(let key, _):
//            guard let field = self.viewModel.state.data.fields[key] else { return }
//            if let cell = cell as? ItemDetailFieldCell {
//                cell.setup(with: field, titleWidth: titleWidth)
//            } else if let cell = cell as? ItemDetailFieldEditCell {
//                cell.setup(with: field, titleWidth: titleWidth)
//                cell.textObservable.subscribe(onNext: { [weak self] value in
//                    self?.viewModel.process(action: .setFieldValue(id: field.key, value: value))
//                }).disposed(by: cell.newDisposeBag)
//            } else if let cell = cell as? ItemDetailFieldMultilineEditCell {
//                cell.setup(with: field, titleWidth: titleWidth)
//                cell.textObservable.subscribe(onNext: { [weak self] value in
//                    self?.viewModel.process(action: .setFieldValue(id: field.key, value: value))
//                }).disposed(by: cell.newDisposeBag)
//            }
//
//        case .note(let note, let isSaving):
//            if let cell = cell as? ItemDetailNoteCell {
//                cell.setup(with: note, isSaving: isSaving)
//            }
//
//        case .tag(let tag):
//            if let cell = cell as? ItemDetailTagCell {
//                cell.setup(tag: tag, isEditing: isEditing)
//            }
//
//        case .title:
//            if let cell = cell as? ItemDetailTitleCell {
//                cell.setup(with: self.viewModel.state.data.title, isEditing: isEditing)
//                cell.textObservable.subscribe(onNext: { [weak self] title in
//                    guard isEditing else { return }
//                    self?.viewModel.process(action: .setTitle(title))
//                }).disposed(by: cell.newDisposeBag)
//            }
//
//        case .type(let type):
//            if let cell = cell as? ItemDetailFieldCell {
//                cell.setup(with: type, title: L10n.itemType, titleWidth: titleWidth)
//                if isEditing {
//                    cell.accessibilityTraits = .button
//                }
//            }
//        }
    }

    private func canTap(attachmentType: Attachment.Kind, isEditing: Bool) -> Bool {
        guard !isEditing else { return false }
        switch attachmentType {
        case .file(_, _, _, let linkType) where linkType == .linkedFile:
            return false
        case .file, .url:
            return true
        }
    }

//    private func cellLayoutData(for section: Section, isFirstRow: Bool, isLastRow: Bool, isAddCell: Bool, isEditing: Bool)
//                                                                                        -> (separatorInsets: UIEdgeInsets, layoutMargins: UIEdgeInsets, accessoryType: UITableViewCell.AccessoryType) {
//        var hasSeparator = true
//        var accessoryType: UITableViewCell.AccessoryType = .none
//
//        switch section {
//        case .title, .notes: break
//        case .abstract:
//            hasSeparator = false
//        case .attachments: break
//            // TODO: implement attachment metadata screen
////            if !isAddCell {
////                accessoryType = .detailButton
////            }
//        case .tags, .type, .fields:
//            if !isAddCell {
//                hasSeparator = isEditing
//            }
//        case .creators:
//            if !isAddCell {
//                if isEditing {
//                    accessoryType = .disclosureIndicator
//                }
//                hasSeparator = isEditing
//            }
//        case .dates:
//            hasSeparator = isEditing && !isLastRow
//        }
//
//        let layoutMargins = ItemDetailLayout.insets(for: section, isEditing: isEditing, isFirstRow: isFirstRow, isLastRow: isLastRow)
//        let leftSeparatorInset: CGFloat = hasSeparator ? self.separatorLeftInset(for: section, isEditing: isEditing, leftMargin: layoutMargins.left) :
//                                                         max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
//        let separatorInsets = UIEdgeInsets(top: 0, left: leftSeparatorInset, bottom: 0, right: 0)
//        return (separatorInsets, layoutMargins, accessoryType)
//    }

    private func separatorLeftInset(for section: Section, isEditing: Bool, leftMargin: CGFloat) -> CGFloat {
        switch section {
        case .notes, .attachments, .tags:
            return ItemDetailLayout.iconWidth + (isEditing ? 40 : 0) + leftMargin
        case .abstract, .creators, .dates, .fields, .title, .type:
            return 0
        }
    }

    // MARK: - Setups

    /// Sets `tableView` dataSource, delegate and registers appropriate cells and sections.
    private func setupTableView() {
        self.dataSource = TableViewDiffableDataSource(tableView: self.tableView, cellProvider: { [weak self] tableView, indexPath, row in
            let isEditing = self?.viewModel.state.isEditing ?? false
            let cellId = row.cellId(isEditing: isEditing)
            let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)

            if let `self` = self, let section = self.dataSource.section(for: indexPath.section) {
                self.setup(cell: cell, section: section.section, row: row, indexPath: indexPath, isAddCell: (cellId == "ItemDetailAddCell"), isEditing: isEditing)
            }

            return cell
        });

        self.dataSource.canEditRow = { [weak self] indexPath in
            guard let `self` = self, let row = self.dataSource.itemIdentifier(for: indexPath) else { return false }

            switch row {
            case .attachment:
                return !self.viewModel.state.data.isAttachment
            case .note, .tag:
                return true
            case .creator:
                return self.viewModel.state.isEditing
            default:
                return false
            }
        }

        self.dataSource.canMoveRow = { [weak self] indexPath in
            guard let row = self?.dataSource.itemIdentifier(for: indexPath), case .creator = row else { return false }
            return true
        }

        self.dataSource.moveRow = { [weak self] sourceIndexPath, destinationIndexPath in
//            guard let `self` = self, let sourceSection = self.dataSource.section(for: sourceIndexPath.section),
//                  let destinationSection = self.dataSource.section(for: destinationIndexPath.section),
//                  sourceSection.section == .creators && destinationSection.section == .creators else { return }
//            self.viewModel.process(action: .moveCreators(from: IndexSet([sourceIndexPath.row]), to: destinationIndexPath.row))
        }

        self.dataSource.commitEditingStyle = { [weak self] editingStyle, indexPath in
            guard editingStyle == .delete, let `self` = self, self.viewModel.state.isEditing, let section = self.dataSource.section(for: indexPath.section) else { return }

            switch section.section {
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

        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none
        self.tableView.tableHeaderView = UIView()
        self.tableView.tableFooterView = UIView()
        self.tableView.separatorInsetReference = .fromAutomaticInsets
        self.tableView.layoutMargins = .zero
        self.tableView.separatorInset = .zero
        if #available(iOS 15.0, *) {
            self.tableView.sectionHeaderTopPadding = 0
        }
        self.tableView.estimatedRowHeight = 44

        ItemDetailTableViewHandler.cellIds.forEach { cellId in
            self.tableView.register(UINib(nibName: cellId, bundle: nil), forCellReuseIdentifier: cellId)
        }
        self.tableView.register(UINib(nibName: ItemDetailTableViewHandler.sectionId, bundle: nil), forHeaderFooterViewReuseIdentifier: ItemDetailTableViewHandler.sectionId)
    }

    private func setupTableView(with keyboardData: KeyboardData) {
        var insets = self.tableView.contentInset
        insets.bottom = keyboardData.endFrame.height
        self.tableView.contentInset = insets
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }
}

extension ItemDetailTableViewHandler: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let section = self.dataSource.section(for: section)?.section else { return 0 }

        switch section {
        case .notes, .attachments, .tags:
            return ItemDetailLayout.sectionHeaderHeight + ItemDetailLayout.separatorHeight
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let section = self.dataSource.section(for: section)?.section else { return nil }

        let title: String
        switch section {
        case .notes:
            title = L10n.ItemDetail.notes
        case .attachments:
            title = L10n.ItemDetail.attachments
        case .tags:
            title = L10n.ItemDetail.tags
        default:
            return nil
        }

        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: ItemDetailTableViewHandler.sectionId) as? ItemDetailSectionView
        view?.setup(with: title)
        return view
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
//        guard let section = self.dataSource.section(for: indexPath.section)?.section else { return }
//        let isLastRow = indexPath.row == (self.dataSource.tableView(tableView, numberOfRowsInSection: indexPath.section) - 1)
//        let layoutMargins = ItemDetailLayout.insets(for: section, isEditing: self.viewModel.state.isEditing, isFirstRow: (indexPath.row == 0), isLastRow: isLastRow)
//        cell.layoutMargins = layoutMargins
//        cell.contentView.layoutMargins = layoutMargins
    }

    func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        let section = self.dataSource.section(for: proposedDestinationIndexPath.section)?.section
        if section != .creators { return sourceIndexPath }
        if let row = self.dataSource.itemIdentifier(for: proposedDestinationIndexPath) {
            switch row {
            case .addCreator:
                return sourceIndexPath
            default: break
            }
        }
        return proposedDestinationIndexPath
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !self.viewModel.state.isEditing, let section = self.dataSource.section(for: indexPath.section)?.section else { return nil }

        switch section {
        case .attachments:
            let attachment = self.viewModel.state.attachments[indexPath.row]
            let trashAction = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completed in
                self?.observer.on(.next(.trashAttachment(attachment)))
                completed(true)
            }
            trashAction.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [trashAction])
        case .title, .abstract, .fields, .type, .dates, .creators, .notes, .tags:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !self.viewModel.state.isEditing, let section = self.dataSource.section(for: indexPath.section)?.section else { return nil }

        switch section {
        case .attachments:
            guard indexPath.row < self.viewModel.state.attachments.count else { return nil }
            let attachment = self.viewModel.state.attachments[indexPath.row]
            return self.createContextMenu(for: attachment).flatMap({ menu in UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in menu }) })

        case .fields:
            guard indexPath.row < self.viewModel.state.data.fields.count else { return nil }
            let fieldId = self.viewModel.state.data.fieldIds[indexPath.row]
            let field = self.viewModel.state.data.fields[fieldId]
            return field.flatMap({ self.createContextMenu(for: $0) }).flatMap({ menu in UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in menu }) })

        case .abstract, .creators, .dates, .notes, .tags, .title, .type:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = self.dataSource.section(for: indexPath.section)?.section else { return }

        switch section {
        case .attachments:
            if indexPath.row == self.viewModel.state.attachments.count {
                self.observer.on(.next(.openFilePicker))
            } else if indexPath.row < self.viewModel.state.attachments.count {
                let key = self.viewModel.state.attachments[indexPath.row].key
                self.viewModel.process(action: .openAttachment(key))
            }
        case .notes:
            if indexPath.row == self.viewModel.state.notes.count {
                self.observer.on(.next(.openNoteEditor(nil)))
            } else {
                let note = self.viewModel.state.notes[indexPath.row]

                guard !self.viewModel.state.savingNotes.contains(note.key) else { return }

                self.observer.on(.next(.openNoteEditor(note)))
            }
        case .tags:
            if indexPath.row == self.viewModel.state.tags.count {
                self.observer.on(.next(.openTagPicker))
            }
        case .creators:
            guard self.viewModel.state.isEditing else { return }

            if indexPath.row == self.viewModel.state.data.creators.count {
                self.observer.on(.next(.openCreatorCreation))
            } else {
                let id = self.viewModel.state.data.creatorIds[indexPath.row]
                if let creator = self.viewModel.state.data.creators[id] {
                    self.observer.on(.next(.openCreatorEditor(creator)))
                }
            }
        case .type:
            if self.viewModel.state.isEditing && !self.viewModel.state.data.isAttachment{
                self.observer.on(.next(.openTypePicker))
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
