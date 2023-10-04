//
//  ItemDetailCollectionViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol ItemDetailCollectionViewHandlerDelegate: AnyObject {
    func isDownloadingFromNavigationBar(for key: String) -> Bool
}

/// Class for handling the `UITableView` of `ItemDetailViewController`. It takes care of showing appropriate data in the `tableView`, keeping track
/// of visible sections and reports actions that need to take place after user interaction with the `tableView`.
final class ItemDetailCollectionViewHandler: NSObject {
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

    /// `UICollectionViewDiffableDataSource` has a bug where it doesn't reload sections which are in `reloadSections` of its snapshot, but if sections are actually different, the snapshot will reload them.
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
        case attachment(attachment: Attachment, type: ItemDetailAttachmentCell.Kind)
        case creator(ItemDetailState.Creator)
        case dateAdded(Date)
        case dateModified(Date)
        case field(key: String, multiline: Bool)
        case note(note: Note, isProcessing: Bool)
        case tag(tag: Tag, isProcessing: Bool)
        case title
        case type(String)

        static func == (lhs: Row, rhs: Row) -> Bool {
            switch (lhs, rhs) {
            case (.addNote, .addNote), (.addCreator, .addCreator), (.addTag, .addTag), (.addAttachment, .addAttachment):
                return true

            case (.abstract, .abstract):
                return true

            case (.attachment(let lAttachment, let lType), .attachment(let rAttachment, let rType)):
                return lAttachment == rAttachment && lType == rType

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

            case (.tag(let lTag, let lIsProcessing), .tag(let rTag, let rIsProcessing)):
                return lTag == rTag && lIsProcessing == rIsProcessing

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

            case .attachment(let attachment, let type):
                hasher.combine(2)
                hasher.combine(attachment)
                hasher.combine(type)

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

            case .tag(let tag, let isSaving):
                hasher.combine(8)
                hasher.combine(tag)
                hasher.combine(isSaving)

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
            case .attachment(let attachment, _):
                return attachment.key == key

            default:
                return false
            }
        }

        var isAdd: Bool {
            switch self {
            case .addTag, .addNote, .addCreator, .addAttachment: return true
            default: return false
            }
        }
    }

    private unowned let viewModel: ViewModel<ItemDetailActionHandler>
    private unowned let collectionView: UICollectionView
    private let disposeBag: DisposeBag
    let observer: PublishSubject<Action>

    // Width of title for field cells when editing is enabled (all fields are visible)
    private var maxTitleWidth: CGFloat = 0
    // Width of title for field cells when editing is disabled (only non-empty fields are visible)
    private var maxNonemptyTitleWidth: CGFloat = 0
    private var dataSource: UICollectionViewDiffableDataSource<SectionType, Row>!
    private weak var fileDownloader: AttachmentDownloader?
    weak var delegate: ItemDetailCollectionViewHandlerDelegate?

    var attachmentSectionIndex: Int? {
        return self.dataSource?.snapshot().sectionIdentifiers.firstIndex(where: { $0.section == .attachments })
    }

    var hasRows: Bool {
        return !self.dataSource.snapshot().itemIdentifiers.isEmpty
    }

    // MARK: - Lifecycle

    init(collectionView: UICollectionView, containerWidth: CGFloat, viewModel: ViewModel<ItemDetailActionHandler>, fileDownloader: AttachmentDownloader?) {
        self.collectionView = collectionView
        self.viewModel = viewModel
        self.fileDownloader = fileDownloader
        self.observer = PublishSubject()
        self.disposeBag = DisposeBag()

        super.init()

        let (titleWidth, nonEmptyTitleWidth) = self.calculateTitleWidths(for: viewModel.state.data)
        self.maxTitleWidth = titleWidth
        self.maxNonemptyTitleWidth = nonEmptyTitleWidth
        self.setupCollectionView()
        self.setupKeyboardObserving()
    }

    // MARK: - Actions

    func sourceDataForCell(at indexPath: IndexPath) -> (UIView, CGRect?) {
        return (self.collectionView, self.collectionView.cellForItem(at: indexPath)?.frame)
    }

    /// Reloads the whole `collectionView`. Applies new snapshot based on `state` and reloads remaining items which were not changed between snapshots.
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

        self.dataSource.apply(snapshot, animatingDifferences: animated, completion: nil)
    }

    /// Recalculates title width for current data.
    /// - parameter data: New data that change the title width.
    func recalculateTitleWidth(from data: ItemDetailState.Data) {
        let (titleWidth, nonEmptyTitleWidth) = self.calculateTitleWidths(for: data)
        self.maxTitleWidth = titleWidth
        self.maxNonemptyTitleWidth = nonEmptyTitleWidth
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

    /// Returns an array of rows which need to be reloaded manually. Some sections are "special" because their rows don't hold the values which they show in collection view, they just hold their
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
        guard let indexPath = self.dataSource.indexPath(for: row), let cellFrame = self.collectionView.cellForItem(at: indexPath)?.frame else { return }

        let snapshot = self.dataSource.snapshot()
        self.dataSource.apply(snapshot, animatingDifferences: false)

        let cellBottom = cellFrame.maxY - self.collectionView.contentOffset.y
        let tableViewBottom = self.collectionView.superview!.bounds.maxY - self.collectionView.contentInset.bottom
        let safeAreaTop = self.collectionView.superview!.safeAreaInsets.top

        // Scroll either when cell bottom is below keyboard or cell top is not visible on screen
        if cellBottom > tableViewBottom || cellFrame.minY < (safeAreaTop + self.collectionView.contentOffset.y) {
            // Scroll to top if cell is smaller than visible screen, so that it's fully visible, otherwise scroll to bottom.
            let position: UICollectionView.ScrollPosition = cellFrame.height + safeAreaTop < tableViewBottom ? .top : .bottom
            self.collectionView.scrollToItem(at: indexPath, at: position, animated: false)
        }
    }

    func updateAttachment(with attachment: Attachment, isProcessing: Bool) {
        var snapshot = self.dataSource.snapshot()

        guard let section = snapshot.sectionIdentifiers.first(where: { $0.section == .attachments }) else { return }

        var rows = snapshot.itemIdentifiers(inSection: section)

        guard let index = rows.firstIndex(where: { $0.isAttachment(withKey: attachment.key) }) else { return }

        snapshot.deleteItems(rows)
        rows[index] = self.attachmentRow(for: attachment, isProcessing: isProcessing)
        snapshot.appendItems(rows, toSection: section)

        self.dataSource.apply(snapshot, animatingDifferences: false, completion: nil)
    }

    private func delete(row: Row) {
        switch row {
        case .creator(let creator):
            self.viewModel.process(action: .deleteCreator(creator.id))

        case .tag(let tag, _):
            self.viewModel.process(action: .deleteTag(tag))

        case .attachment(let attachment, _):
            self.viewModel.process(action: .deleteAttachment(attachment))

        case .note(let note, _):
            self.viewModel.process(action: .deleteNote(note))

        case .title, .abstract, .addAttachment, .addCreator, .addNote, .addTag, .dateAdded, .dateModified, .type, .field: break
        }
    }

    func scrollTo(itemKey: String, animated: Bool) {
        var row: Row?

        for _row in self.dataSource.snapshot().itemIdentifiers {
            switch _row {
            case .note(let note, _) where note.key == itemKey:
                row = _row

            case .attachment(let attachment, _) where attachment.key == itemKey:
                row = _row

            default:
                continue
            }
        }

        guard let row = row, let indexPath = self.dataSource.indexPath(for: row) else { return }

        self.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
    }

    // MARK: - Helpers

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
        if !data.isAttachment {
            sections.append(.notes)
        }
        sections.append(contentsOf: [.tags, .attachments])

        return sections
    }

    private func rows(for section: Section, state: ItemDetailState) -> [Row] {
        switch section {
        case .abstract:
            return [.abstract]

        case .attachments:
            var attachments = state.attachments.map({ attachment in
                let isProcessing = state.backgroundProcessedItems.contains(attachment.key)
                return self.attachmentRow(for: attachment, isProcessing: isProcessing)
            })

            if !self.viewModel.state.data.isAttachment {
                attachments += [.addAttachment]
            }

            return attachments

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
                let isProcessing = state.backgroundProcessedItems.contains(note.key)
                return .note(note: note, isProcessing: isProcessing)
            })
            return notes + [.addNote]

        case .tags:
            let tags: [Row] = state.tags.map({ tag in
                let isProcessing = state.backgroundProcessedItems.contains(tag.name)
                return .tag(tag: tag, isProcessing: isProcessing)
            })
            return tags + [.addTag]

        case .title:
            return [.title]

        case .type:
            return [.type(state.data.localizedType)]
        }
    }

    private func attachmentRow(for attachment: Attachment, isProcessing: Bool) -> Row {
        if isProcessing || self.delegate?.isDownloadingFromNavigationBar(for: attachment.key) == true {
            return .attachment(attachment: attachment, type: .disabled)
        }

        let (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)

        if let error = error {
            return .attachment(attachment: attachment, type: .failed(error))
        }

        if let progress = progress {
            return .attachment(attachment: attachment, type: .inProgress(progress))
        }

        return .attachment(attachment: attachment, type: .default)
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

    private func createContextMenu(for attachment: Attachment) -> UIMenu? {
        var actions: [UIAction] = []

        if case .file(_, _, let location, _) = attachment.type, location == .local {
            actions.append(UIAction(title: L10n.ItemDetail.deleteAttachmentFile, image: UIImage(systemName: "trash"), attributes: []) { [weak self] _ in
                self?.viewModel.process(action: .deleteAttachmentFile(attachment))
            })
        }

        if !self.viewModel.state.data.isAttachment {
            actions.append(UIAction(title: L10n.ItemDetail.moveToStandaloneAttachment, image: UIImage(systemName: "arrow.up.to.line"), attributes: []) { [weak self] _ in
                self?.viewModel.process(action: .moveAttachmentToStandalone(attachment))
            })

            actions.append(UIAction(title: L10n.moveToTrash, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.viewModel.process(action: .deleteAttachment(attachment))
            })
        }

        return UIMenu(title: "", children: actions)
    }

    private func createContextMenu(for note: Note) -> UIMenu? {
        var actions: [UIAction] = []

        actions.append(UIAction(title: L10n.moveToTrash, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.viewModel.process(action: .deleteNote(note))
        })

        return UIMenu(title: "", children: actions)
    }

    private func createContextMenu(for tag: Tag) -> UIMenu? {
        var actions: [UIAction] = []

        actions.append(UIAction(title: L10n.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.viewModel.process(action: .deleteTag(tag))
        })

        return UIMenu(title: "", children: actions)
    }

    private func createContextMenu(for creator: ItemDetailState.Creator) -> UIMenu? {
        var actions: [UIAction] = []

        actions.append(UIAction(title: L10n.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.viewModel.process(action: .deleteCreator(creator.id))
        })

        return UIMenu(title: "", children: actions)
    }

    private func createContextMenu(for field: ItemDetailState.Field) -> UIMenu? {
        guard (field.key == FieldKeys.Item.doi || field.baseField == FieldKeys.Item.doi) || (field.key == FieldKeys.Item.url || field.baseField == FieldKeys.Item.url) else { return nil }
        return UIMenu(title: "", children: [UIAction(title: L10n.copy, handler: { _ in
            UIPasteboard.general.string = field.value
        })])
    }

    // MARK: - Cells

    private lazy var titleRegistration: UICollectionView.CellRegistration<ItemDetailTitleCell, (String, Bool)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self = self else { return }
            cell.contentConfiguration = ItemDetailTitleCell.ContentConfiguration(title: data.0, isEditing: data.1, layoutMargins: self.layoutMargins(for: indexPath), textChanged: { [weak self] text in
                self?.viewModel.process(action: .setTitle(text))
            })
        }
    }()

    private lazy var fieldRegistration: UICollectionView.CellRegistration<ItemDetailFieldCell, (ItemDetailFieldCell.CellType, CGFloat)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self = self else { return }

            cell.contentConfiguration = ItemDetailFieldCell.ContentConfiguration(type: data.0, titleWidth: data.1, layoutMargins: self.layoutMargins(for: indexPath))

            switch data.0 {
            case .creator:
                cell.accessories = self.viewModel.state.isEditing ? [.disclosureIndicator(), .delete(), .reorder()] : []

            default:
                cell.accessories = []
            }
        }
    }()

    private lazy var fieldEditRegistration: UICollectionView.CellRegistration<ItemDetailFieldEditCell, (ItemDetailState.Field, CGFloat)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self = self else { return }

            cell.contentConfiguration = ItemDetailFieldEditCell.ContentConfiguration(field: data.0, titleWidth: data.1, layoutMargins: self.layoutMargins(for: indexPath),
                                                                                     textChanged: { [weak self] text in
                                                                                         self?.viewModel.process(action: .setFieldValue(id: data.0.key, value: text))
                                                                                     })
        }
    }()

    private lazy var fieldMultilineEditRegistration: UICollectionView.CellRegistration<ItemDetailFieldMultilineEditCell, (ItemDetailState.Field, CGFloat)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self = self else { return }

            cell.contentConfiguration = ItemDetailFieldMultilineEditCell.ContentConfiguration(field: data.0, titleWidth: data.1, layoutMargins: self.layoutMargins(for: indexPath),
                                                                                              textChanged: { [weak self] text in
                                                                                                  self?.viewModel.process(action: .setFieldValue(id: data.0.key, value: text))
                                                                                              })
        }
    }()

    private lazy var addRegistration: UICollectionView.CellRegistration<ItemDetailAddCell, String> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, title in
            guard let self = self else { return }
            cell.contentConfiguration = ItemDetailAddCell.ContentConfiguration(title: title, layoutMargins: self.layoutMargins(for: indexPath))
        }
    }()

    private lazy var abstractRegistration: UICollectionView.CellRegistration<ItemDetailAbstractCell, (String, Bool)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self = self else { return }
            let width = floor(self.collectionView.frame.width) - (ItemDetailLayout.horizontalInset * 2)
            cell.contentConfiguration = ItemDetailAbstractCell.ContentConfiguration(text: data.0, isCollapsed: data.1, layoutMargins: self.layoutMargins(for: indexPath), maxWidth: width)
        }
    }()

    private lazy var abstractEditRegistration: UICollectionView.CellRegistration<ItemDetailAbstractEditCell, String> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, text in
            guard let self = self else { return }

            cell.contentConfiguration = ItemDetailAbstractEditCell.ContentConfiguration(text: text, layoutMargins: self.layoutMargins(for: indexPath), textChanged: { [weak self] text in
                self?.viewModel.process(action: .setAbstract(text))
            })
        }
    }()

    private lazy var noteRegistration: UICollectionView.CellRegistration<ItemDetailNoteCell, (Note, Bool)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self = self else { return }
            cell.contentConfiguration = ItemDetailNoteCell.ContentConfiguration(note: data.0, isProcessing: data.1, layoutMargins: self.layoutMargins(for: indexPath))
        }
    }()

    private lazy var tagRegistration: UICollectionView.CellRegistration<ItemDetailTagCell, (Tag, Bool)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self = self else { return }
            cell.contentConfiguration = ItemDetailTagCell.ContentConfiguration(tag: data.0, isProcessing: data.1, layoutMargins: self.layoutMargins(for: indexPath))
        }
    }()

    private lazy var attachmentRegistration: UICollectionView.CellRegistration<ItemDetailAttachmentCell, (Attachment, ItemDetailAttachmentCell.Kind)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self = self else { return }
            cell.contentConfiguration = ItemDetailAttachmentCell.ContentConfiguration(attachment: data.0, type: data.1, layoutMargins: self.layoutMargins(for: indexPath))
        }
    }()

    private lazy var emptyRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, ()> = {
        return UICollectionView.CellRegistration { _, _, _ in }
    }()

    // MARK: - Layout

    private func layoutMargins(for indexPath: IndexPath) -> UIEdgeInsets {
        guard let section = self.dataSource.section(for: indexPath.section)?.section else { return UIEdgeInsets() }

        let isEditing = self.viewModel.state.isEditing
        let isFirstRow = indexPath.row == 0
        let isLastRow = indexPath.row == (self.dataSource.collectionView(self.collectionView, numberOfItemsInSection: indexPath.section) - 1)

        return ItemDetailLayout.insets(for: section, isEditing: isEditing, isFirstRow: isFirstRow, isLastRow: isLastRow)
    }

    private func createCollectionViewLayout() -> UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { [unowned self] index, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)

            var supplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []

            if let section = self.dataSource.section(for: index) {
                self.setupSeparators(in: &configuration, section: section)
                self.setupSwipeActions(in: &configuration)
                if let header = self.createHeader(for: section.section) {
                    supplementaryItems.append(header)
                }
            }

            let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            layoutSection.boundarySupplementaryItems = supplementaryItems
            return layoutSection
        }
    }

    private func createHeader(for section: Section) -> NSCollectionLayoutBoundarySupplementaryItem? {
        switch section {
        case .attachments, .tags, .notes:
            let height = ItemDetailLayout.sectionHeaderHeight - ItemDetailLayout.separatorHeight
            return NSCollectionLayoutBoundarySupplementaryItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)),
                                                               elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)

        default:
            return nil
        }
    }

    private func setupSwipeActions(in configuration: inout UICollectionLayoutListConfiguration) {
        configuration.trailingSwipeActionsConfigurationProvider = { [unowned self] indexPath in
            guard let row = self.dataSource.itemIdentifier(for: indexPath) else { return nil }

            switch row {
            case .attachment(_, let type) where type != .disabled: break
            case .note(_, let isProcessing) where !isProcessing: break
            case .tag(_, let isProcessing) where !isProcessing: break
            case .creator where self.viewModel.state.isEditing: break
            default: return nil
            }

            let delete = UIContextualAction(style: .destructive, title: L10n.delete) { _, _, completion in
                self.delete(row: row)
                completion(true)
            }
            return UISwipeActionsConfiguration(actions: [delete])
        }
    }

    private func setupSeparators(in configuration: inout UICollectionLayoutListConfiguration, section: SectionType) {
        configuration.itemSeparatorHandler = { [unowned self] indexPath, _configuration in
            var configuration = _configuration
            let isLastRow = indexPath.row == self.dataSource.snapshot(for: section).items.count - 1
            configuration.bottomSeparatorVisibility = self.sectionHasSeparator(section.section, isEditing: self.viewModel.state.isEditing, isLastRow: isLastRow) ? .visible : .hidden
            if configuration.bottomSeparatorVisibility == .visible {
                configuration.bottomSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: self.separatorLeftInset(for: section.section), bottom: 0, trailing: 0)
            }
            return configuration
        }
    }

    private func sectionHasSeparator(_ section: Section, isEditing: Bool, isLastRow: Bool) -> Bool {
        switch section {
        case .title:
            return true

        case .abstract:
            return false

        case .type, .fields, .creators:
            return isEditing

        case .attachments, .notes, .tags:
            return !isLastRow

        case .dates:
            return isEditing || isLastRow
        }
    }

    private func separatorLeftInset(for section: Section) -> CGFloat {
        switch section {
        case .notes, .attachments, .tags:
            return ItemDetailLayout.iconWidth + ItemDetailLayout.horizontalInset + 17

        case .abstract, .creators, .dates, .fields, .title, .type:
            return ItemDetailLayout.horizontalInset
        }
    }

    // MARK: - Setups

    private func setup(headerView: UIView, indexPath: IndexPath) {
        guard let view = headerView as? ItemDetailSectionView else { return }

        let section = self.dataSource.snapshot().sectionIdentifiers[indexPath.section].section

        switch section {
        case .notes:
            view.setup(with: L10n.ItemDetail.notes)

        case .attachments:
            view.setup(with: L10n.ItemDetail.attachments)

        case .tags:
            view.setup(with: L10n.ItemDetail.tags)
        default: break
        }
    }

    /// Sets `collectionView` dataSource, delegate and registers appropriate cells and sections.
    private func setupCollectionView() {
        self.collectionView.collectionViewLayout = self.createCollectionViewLayout()
        self.collectionView.delegate = self
        // keyboardDismissMode is device based, regardless of horizontal size class.
        self.collectionView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none
        self.collectionView.register(UINib(nibName: "ItemDetailSectionView", bundle: nil), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "Header")
        self.collectionView.isEditing = true

        let titleRegistration = self.titleRegistration
        let fieldRegistration = self.fieldRegistration
        let fieldEditRegistration = self.fieldEditRegistration
        let fieldMultilineEditRegistration = self.fieldMultilineEditRegistration
        let emptyRegistration = self.emptyRegistration
        let addRegistration = self.addRegistration
        let abstractRegistration = self.abstractRegistration
        let abstractEditRegistration = self.abstractEditRegistration
        let noteRegistration = self.noteRegistration
        let tagRegistration = self.tagRegistration
        let attachmentRegistration = self.attachmentRegistration

        self.dataSource = UICollectionViewDiffableDataSource(collectionView: self.collectionView, cellProvider: { [weak self] collectionView, indexPath, row in
            guard let self = self else { return collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: ()) }

            let isEditing = self.viewModel.state.isEditing
            let titleWidth = isEditing ? self.maxTitleWidth : self.maxNonemptyTitleWidth

            switch row {
            case .title:
                let title = self.viewModel.state.data.title
                return collectionView.dequeueConfiguredReusableCell(using: titleRegistration, for: indexPath, item: (title, isEditing))

            case .creator(let creator):
                return collectionView.dequeueConfiguredReusableCell(using: fieldRegistration, for: indexPath, item: (.creator(creator), titleWidth))

            case .addNote:
                return collectionView.dequeueConfiguredReusableCell(using: addRegistration, for: indexPath, item: L10n.ItemDetail.addNote)

            case .addAttachment:
                return collectionView.dequeueConfiguredReusableCell(using: addRegistration, for: indexPath, item: L10n.ItemDetail.addAttachment)

            case .addCreator:
                return collectionView.dequeueConfiguredReusableCell(using: addRegistration, for: indexPath, item: L10n.ItemDetail.addCreator)

            case .addTag:
                return collectionView.dequeueConfiguredReusableCell(using: addRegistration, for: indexPath, item: L10n.ItemDetail.addTag)

            case .abstract:
                let value = self.viewModel.state.data.abstract ?? ""

                if isEditing {
                    return collectionView.dequeueConfiguredReusableCell(using: abstractEditRegistration, for: indexPath, item: value)
                }

                let isCollapsed = self.viewModel.state.abstractCollapsed
                return collectionView.dequeueConfiguredReusableCell(using: abstractRegistration, for: indexPath, item: (value, isCollapsed))

            case .attachment(let attachment, let type):
                return collectionView.dequeueConfiguredReusableCell(using: attachmentRegistration, for: indexPath, item: (attachment, type))

            case .dateAdded(let date):
                let date = Formatter.dateAndTime.string(from: date)
                return collectionView.dequeueConfiguredReusableCell(using: fieldRegistration, for: indexPath, item: (.value(value: date, title: L10n.dateAdded), titleWidth))

            case .dateModified(let date):
                let date = Formatter.dateAndTime.string(from: date)
                return collectionView.dequeueConfiguredReusableCell(using: fieldRegistration, for: indexPath, item: (.value(value: date, title: L10n.dateModified), titleWidth))

            case .field(let key, let multiline):
                guard let field = self.viewModel.state.data.fields[key] else { return collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: ()) }

                if !isEditing || self.viewModel.state.data.isAttachment {
                    return collectionView.dequeueConfiguredReusableCell(using: fieldRegistration, for: indexPath, item: (.field(field), titleWidth))
                }

                if multiline {
                    return collectionView.dequeueConfiguredReusableCell(using: fieldMultilineEditRegistration, for: indexPath, item: (field, titleWidth))
                }

                return collectionView.dequeueConfiguredReusableCell(using: fieldEditRegistration, for: indexPath, item: (field, titleWidth))

            case .note(let note, let isProcessing):
                return collectionView.dequeueConfiguredReusableCell(using: noteRegistration, for: indexPath, item: (note, isProcessing))

            case .tag(let tag, let isProcessing):
                return collectionView.dequeueConfiguredReusableCell(using: tagRegistration, for: indexPath, item: (tag, isProcessing))

            case .type(let type):
                return collectionView.dequeueConfiguredReusableCell(using: fieldRegistration, for: indexPath, item: (.value(value: type, title: L10n.itemType), titleWidth))
            }
        })

        self.dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            switch kind {
            case UICollectionView.elementKindSectionHeader:
                let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath)
                self?.setup(headerView: view, indexPath: indexPath)
                return view

            default: fatalError("unknown section")
            }
        }

        self.dataSource.reorderingHandlers.canReorderItem = { row -> Bool in
            switch row {
            case .creator: return true
            default: return false
            }
        }

        self.dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            guard let self = self, let difference = transaction.sectionTransactions.first?.difference else { return }

            let changes = difference.compactMap({ change -> CollectionDifference<UUID>.Change? in
                switch change {
                case .insert(let offset, let element, let associatedWith):
                    switch element {
                    case .creator(let creator):
                        return .insert(offset: offset, element: creator.id, associatedWith: associatedWith)
                    default: return nil
                    }

                case .remove(let offset, let element, let associatedWith):
                    switch element {
                    case .creator(let creator):
                        return .remove(offset: offset, element: creator.id, associatedWith: associatedWith)
                    default: return nil
                    }
                }
            })

            guard let difference = CollectionDifference(changes) else { return }

            self.viewModel.process(action: .moveCreators(difference))
        }
    }

    private func setupCollectionView(with keyboardData: KeyboardData) {
        var insets = self.collectionView.contentInset
        insets.bottom = keyboardData.visibleHeight
        self.collectionView.contentInset = insets
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupCollectionView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupCollectionView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }
}

extension ItemDetailCollectionViewHandler: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let row = self.dataSource.itemIdentifier(for: indexPath) else { return }

        switch row {
        case .addNote:
            self.observer.on(.next(.openNoteEditor(nil)))

        case .addAttachment:
            self.observer.on(.next(.openFilePicker))

        case .addCreator:
            self.observer.on(.next(.openCreatorCreation))

        case .addTag:
            self.observer.on(.next(.openTagPicker))

        case .abstract:
            guard !self.viewModel.state.isEditing else { return }
            self.viewModel.process(action: .toggleAbstractDetailCollapsed)

        case .attachment(let attachment, let type):
            guard type != .disabled else { return }
            self.viewModel.process(action: .openAttachment(attachment.key))

        case .creator(let creator):
            guard self.viewModel.state.isEditing else { return }
            self.observer.on(.next(.openCreatorEditor(creator)))

        case .note(let note, let isProcessing):
            guard !isProcessing else { return }
            self.observer.on(.next(.openNoteEditor(note)))

        case .type:
            guard self.viewModel.state.isEditing && !self.viewModel.state.data.isAttachment else { return }
            self.observer.on(.next(.openTypePicker))

        case .field(let fieldId, _):
            // Tappable fields should be only tappable when not in editing mode, in case of attachment, URL is not editable, so keep it tappable even while editing.
            guard !self.viewModel.state.isEditing || (self.viewModel.state.data.type == ItemTypes.attachment), let field = self.viewModel.state.data.fields[fieldId], field.isTappable else { return }
            switch field.key {
            case FieldKeys.Item.Attachment.url:
                self.observer.on(.next(.openUrl(field.value)))

            case FieldKeys.Item.doi:
                self.observer.on(.next(.openDoi(field.value)))
            default: break
            }

        case .title, .dateAdded, .dateModified, .tag: break
        }
    }

    func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveOfItemFromOriginalIndexPath originalIndexPath: IndexPath, atCurrentIndexPath currentIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        let section = self.dataSource.section(for: proposedIndexPath.section)?.section
        if section != .creators { return originalIndexPath }
        if let row = self.dataSource.itemIdentifier(for: proposedIndexPath) {
            switch row {
            case .addCreator:
                return originalIndexPath
            default: break
            }
        }
        return proposedIndexPath
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !self.viewModel.state.isEditing, let row = self.dataSource.itemIdentifier(for: indexPath) else { return nil }

        let menu: UIMenu?

        switch row {
        case .field(let fieldId, _):
            guard let field = self.viewModel.state.data.fields[fieldId] else { return nil }
            menu = self.createContextMenu(for: field)

        case .attachment(let attachment, _):
            menu = self.createContextMenu(for: attachment)

        case .tag(let tag, _):
            menu = self.createContextMenu(for: tag)

        case .note(let note, _):
            menu = self.createContextMenu(for: note)

        case .creator(let creator):
            menu = self.createContextMenu(for: creator)

        default:
            return nil
        }

        return menu.flatMap({ menu in UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in menu }) })
    }
}
