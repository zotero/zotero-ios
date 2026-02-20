//
//  ItemDetailCollectionViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

protocol ItemDetailCollectionViewHandlerDelegate: AnyObject {
    func isDownloadingFromNavigationBar(for key: String) -> Bool
}

protocol FocusableCell: UICollectionViewCell {
    func focus()
}

/// Class for handling the `UICollectionView` of `ItemDetailViewController`. It takes care of showing appropriate data in the `collectionView`, keeping track
/// of visible sections and reports actions that need to take place after user interaction with the `collectionView`.
final class ItemDetailCollectionViewHandler: NSObject {
    /// Actions that need to take place when user taps on some cells
    enum Action {
        case openCreatorCreation
        case openCreatorEditor(ItemDetailState.Creator)
        case openNoteEditor(key: String?)
        case openTagPicker
        case openTypePicker
        case openFilePicker
        case openUrl(String)
        case openDoi(String)
        case openCollection(Collection)
        case openLibrary(Library)
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
        case collections
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
        case collection(Collection)
        case creator(ItemDetailState.Creator)
        case dateAdded(Date)
        case dateModified(Date)
        case field(key: String, multiline: Bool)
        case library(Library)
        case note(key: String, title: String, isProcessing: Bool)
        case tag(id: UUID, tag: Tag, isProcessing: Bool)
        case title
        case type(String)

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
            case .addTag, .addNote, .addCreator, .addAttachment:
                return true

            default:
                return false
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
    private let updateQueue: DispatchQueue
    private weak var fileDownloader: AttachmentDownloader?
    weak var delegate: ItemDetailCollectionViewHandlerDelegate?

    var attachmentSectionIndex: Int? {
        return dataSource?.snapshot().sectionIdentifiers.firstIndex(where: { $0.section == .attachments })
    }

    var hasRows: Bool {
        return !dataSource.snapshot().itemIdentifiers.isEmpty
    }

    // MARK: - Lifecycle

    init(collectionView: UICollectionView, containerWidth: CGFloat, viewModel: ViewModel<ItemDetailActionHandler>, fileDownloader: AttachmentDownloader?) {
        self.collectionView = collectionView
        self.viewModel = viewModel
        self.fileDownloader = fileDownloader
        observer = PublishSubject()
        disposeBag = DisposeBag()
        updateQueue = DispatchQueue(label: "org.zotero.ItemDetailCollectionViewHandler.UpdateQueue")

        super.init()

        let (titleWidth, nonEmptyTitleWidth) = calculateTitleWidths(for: viewModel.state.data)
        maxTitleWidth = titleWidth
        maxNonemptyTitleWidth = nonEmptyTitleWidth
        setupCollectionView()
        setupKeyboardObserving()

        func setupKeyboardObserving() {
            NotificationCenter.default
                .keyboardWillShow
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] notification in
                    guard let self, let data = notification.keyboardData else { return }
                    setupCollectionView(with: data, self: self)
                })
                .disposed(by: disposeBag)

            NotificationCenter.default
                .keyboardWillHide
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] notification in
                    guard let self, let data = notification.keyboardData else { return }
                    setupCollectionView(with: data, self: self)
                })
                .disposed(by: disposeBag)

            func setupCollectionView(with keyboardData: KeyboardData, self: ItemDetailCollectionViewHandler) {
                var insets = self.collectionView.contentInset
                insets.bottom = keyboardData.visibleHeight
                self.collectionView.contentInset = insets
            }
        }

        func setupCollectionView() {
            collectionView.collectionViewLayout = createCollectionViewLayout()
            collectionView.delegate = self
            // keyboardDismissMode is device based, regardless of horizontal size class.
            collectionView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none
            collectionView.register(UINib(nibName: "ItemDetailSectionView", bundle: nil), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "Header")

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
            let libraryRegistration = self.libraryRegistration
            let collectionRegistration = self.collectionRegistration

            dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView, cellProvider: { [weak self] collectionView, indexPath, row in
                guard let self else { return collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: ()) }

                let isEditing = viewModel.state.isEditing
                let titleWidth = isEditing ? maxTitleWidth : maxNonemptyTitleWidth

                switch row {
                case .title:
                    let attributedTitle = viewModel.state.attributedTitle
                    return collectionView.dequeueConfiguredReusableCell(using: titleRegistration, for: indexPath, item: (attributedTitle, isEditing))

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
                    let value = viewModel.state.data.abstract ?? ""
                    if isEditing {
                        return collectionView.dequeueConfiguredReusableCell(using: abstractEditRegistration, for: indexPath, item: value)
                    }
                    let isCollapsed = viewModel.state.abstractCollapsed
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
                    guard let field = viewModel.state.data.fields[key] else { return collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: ()) }
                    if !isEditing || !field.isEditable {
                        return collectionView.dequeueConfiguredReusableCell(using: fieldRegistration, for: indexPath, item: (.field(field), titleWidth))
                    }
                    if multiline {
                        return collectionView.dequeueConfiguredReusableCell(using: fieldMultilineEditRegistration, for: indexPath, item: (field, titleWidth))
                    }
                    return collectionView.dequeueConfiguredReusableCell(using: fieldEditRegistration, for: indexPath, item: (field, titleWidth))

                case .note(let key, let title, let isProcessing):
                    return collectionView.dequeueConfiguredReusableCell(using: noteRegistration, for: indexPath, item: (key, title, isProcessing))

                case .tag(_, let tag, let isProcessing):
                    return collectionView.dequeueConfiguredReusableCell(using: tagRegistration, for: indexPath, item: (tag, isProcessing))

                case .type(let type):
                    return collectionView.dequeueConfiguredReusableCell(using: fieldRegistration, for: indexPath, item: (.value(value: type, title: L10n.itemType), titleWidth))
                    
                case .collection(let collection):
                    return collectionView.dequeueConfiguredReusableCell(using: collectionRegistration, for: indexPath, item: collection)
                    
                case .library(let library):
                    return collectionView.dequeueConfiguredReusableCell(using: libraryRegistration, for: indexPath, item: library)
                }
            })

            dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
                switch kind {
                case UICollectionView.elementKindSectionHeader:
                    let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath)
                    if let self {
                        setup(headerView: view, indexPath: indexPath, self: self)
                    }
                    return view

                default:
                    return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath)
                }
            }

            dataSource.reorderingHandlers.canReorderItem = { row -> Bool in
                switch row {
                case .creator:
                    return true

                default:
                    return false
                }
            }

            dataSource.reorderingHandlers.didReorder = { [weak viewModel] transaction in
                guard let viewModel, let difference = transaction.sectionTransactions.first?.difference else { return }

                let changes = difference.compactMap({ change -> CollectionDifference<String>.Change? in
                    switch change {
                    case .insert(let offset, let element, let associatedWith):
                        switch element {
                        case .creator(let creator):
                            return .insert(offset: offset, element: creator.id, associatedWith: associatedWith)

                        default:
                            return nil
                        }

                    case .remove(let offset, let element, let associatedWith):
                        switch element {
                        case .creator(let creator):
                            return .remove(offset: offset, element: creator.id, associatedWith: associatedWith)

                        default:
                            return nil
                        }
                    }
                })

                guard let difference = CollectionDifference(changes) else { return }
                viewModel.process(action: .moveCreators(difference))
            }

            func setup(headerView: UIView, indexPath: IndexPath, self: ItemDetailCollectionViewHandler) {
                guard let view = headerView as? ItemDetailSectionView else { return }

                let section = self.dataSource.snapshot().sectionIdentifiers[indexPath.section].section

                switch section {
                case .notes:
                    view.setup(with: L10n.ItemDetail.notes)

                case .attachments:
                    view.setup(with: L10n.ItemDetail.attachments)

                case .tags:
                    view.setup(with: L10n.ItemDetail.tags)

                case .collections:
                    view.setup(with: L10n.ItemDetail.librariesAndCollections)

                default: break
                }
            }

            func createCollectionViewLayout() -> UICollectionViewLayout {
                return UICollectionViewCompositionalLayout { [weak self] index, environment in
                    guard let self else {
                        return NSCollectionLayoutSection.list(using: UICollectionLayoutListConfiguration(appearance: .plain), layoutEnvironment: environment)
                    }

                    var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                    var supplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []

                    if let section = dataSource.sectionIdentifier(for: index) {
                        setupSeparators(in: &configuration, section: section, self: self)
                        setupSwipeActions(in: &configuration, self: self)
                        if let header = createHeader(for: section.section) {
                            supplementaryItems.append(header)
                        }
                    }

                    let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
                    layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                    layoutSection.boundarySupplementaryItems = supplementaryItems
                    return layoutSection
                }

                func createHeader(for section: Section) -> NSCollectionLayoutBoundarySupplementaryItem? {
                    switch section {
                    case .attachments, .tags, .notes, .collections:
                        let height = ItemDetailLayout.sectionHeaderHeight - ItemDetailLayout.separatorHeight
                        return NSCollectionLayoutBoundarySupplementaryItem(
                            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)),
                            elementKind: UICollectionView.elementKindSectionHeader,
                            alignment: .top
                        )

                    default:
                        return nil
                    }
                }

                func setupSwipeActions(in configuration: inout UICollectionLayoutListConfiguration, self: ItemDetailCollectionViewHandler) {
                    configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                        guard let self, self.viewModel.state.library.metadataEditable, let row = self.dataSource.itemIdentifier(for: indexPath) else { return nil }

                        let title: String
                        switch row {
                        case .attachment(_, let type) where type != .disabled:
                            title = L10n.moveToTrash

                        case .note(_, _, let isProcessing) where !isProcessing:
                            title = L10n.moveToTrash

                        case .tag(_, _, let isProcessing) where !isProcessing:
                            title = L10n.delete

                        case .creator where self.viewModel.state.isEditing:
                            title = L10n.delete
                            
                        case .collection(let collection) where collection.isAvailable:
                            title = L10n.delete

                        default:
                            return nil
                        }

                        let delete = UIContextualAction(style: .destructive, title: title) { [weak self] _, _, completion in
                            if let self {
                                delete(row: row, self: self)
                            }
                            completion(true)
                        }
                        return UISwipeActionsConfiguration(actions: [delete])
                    }

                    func delete(row: Row, self: ItemDetailCollectionViewHandler) {
                        switch row {
                        case .creator(let creator):
                            self.viewModel.process(action: .deleteCreator(creator.id))

                        case .tag(_, let tag, _):
                            self.viewModel.process(action: .deleteTag(tag))

                        case .attachment(let attachment, _):
                            self.viewModel.process(action: .deleteAttachment(attachment))

                        case .note(let key, _, _):
                            self.viewModel.process(action: .deleteNote(key: key))
                            
                        case .collection(let collection):
                            self.viewModel.process(action: .deleteCollection(collection.identifier))

                        case .title, .abstract, .addAttachment, .addCreator, .addNote, .addTag, .dateAdded, .dateModified, .type, .field, .library:
                            break
                        }
                    }
                }

                func setupSeparators(in configuration: inout UICollectionLayoutListConfiguration, section: SectionType, self: ItemDetailCollectionViewHandler) {
                    configuration.itemSeparatorHandler = { [weak self] indexPath, configuration in
                        guard let self else { return configuration }
                        var newConfiguration = configuration
                        let isLastRow = indexPath.row == self.dataSource.snapshot(for: section).items.count - 1
                        newConfiguration.bottomSeparatorVisibility = sectionHasSeparator(section.section, isEditing: self.viewModel.state.isEditing, isLastRow: isLastRow) ? .visible : .hidden
                        if newConfiguration.bottomSeparatorVisibility == .visible {
                            newConfiguration.bottomSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: separatorLeftInset(for: section.section), bottom: 0, trailing: 0)
                        }
                        return newConfiguration
                    }
                }

                func sectionHasSeparator(_ section: Section, isEditing: Bool, isLastRow: Bool) -> Bool {
                    switch section {
                    case .title:
                        return true

                    case .abstract:
                        return false

                    case .type, .fields, .creators:
                        return isEditing

                    case .attachments, .notes, .tags, .collections:
                        return !isLastRow

                    case .dates:
                        return isEditing || isLastRow
                    }
                }

                func separatorLeftInset(for section: Section) -> CGFloat {
                    switch section {
                    case .notes, .attachments, .tags, .collections:
                        return ItemDetailLayout.iconWidth + ItemDetailLayout.horizontalInset + 17

                    case .abstract, .creators, .dates, .fields, .title, .type:
                        return ItemDetailLayout.horizontalInset
                    }
                }
            }
        }
    }

    // MARK: - Actions

    func sourceItemForCell(at indexPath: IndexPath) -> UIPopoverPresentationControllerSourceItem {
        return collectionView.cellForItem(at: indexPath) ?? collectionView
    }

    /// Reloads the whole `collectionView`. Applies new snapshot based on `state` and reloads remaining items which were not changed between snapshots.
    /// - parameter state: State to which we're reloading the table view.
    /// - parameter animated: `true` if the change is animated, `false` otherwise.
    func reloadAll(to state: ItemDetailState, animated: Bool, completion: (() -> Void)? = nil) {
        updateQueue.async { [weak self] in
            guard let self else { return }
            // Assign new id to all sections, just reload everything
            let id = UUID().uuidString
            let sections = sections(for: state.data, hasVisibleFields: !state.visibleFieldIds.isEmpty, isEditing: state.isEditing, library: state.library)
                .map({ SectionType(identifier: id, section: $0) })
            var snapshot = NSDiffableDataSourceSnapshot<SectionType, Row>()
            snapshot.appendSections(sections)
            if #available(iOS 26.0, *) {
                snapshot.reloadSections(sections)
            }
            var collectionsSection: SectionType?
            for section in sections {
                if section.section == .collections {
                    collectionsSection = section
                } else {
                    snapshot.appendItems(rows(for: section.section, state: state), toSection: section)
                }
            }
            let reloadCompletion: () -> Void = { [weak self] in
                // Setting isEditing will trigger reconfiguration of cells, before the new snapshot has been applied, so it is done afterwards to avoid e.g. flickering the old text in a text view.
                self?.collectionView.isEditing = state.isEditing
                completion?()
            }
            dataSource.apply(snapshot, animatingDifferences: animated) {
                guard collectionsSection == nil else { return }
                reloadCompletion()
            }
            if let collectionsSection {
                if let snapshot = state.data.collections?.createSnapshot(parent: .library(state.library), resultTransformer: { Row.collection($0) }) {
                    dataSource.apply(snapshot, to: collectionsSection, animatingDifferences: true, completion: reloadCompletion)
                } else {
                    reloadCompletion()
                }
            }
        }

        /// Creates array of visible sections for current state data.
        /// - parameter data: New data.
        /// - parameter isEditing: Current editing table view state.
        /// - returns: Array of visible sections.
        func sections(for data: ItemDetailState.Data, hasVisibleFields: Bool, isEditing: Bool, library: Library) -> [Section] {
            // Title and item type are always visible.
            var sections: [Section] = [.title, .type]

            if isEditing {
                // Only "metadata" sections are visible during editing.
                if !data.isAttachment {
                    sections.append(.creators)
                }
                if hasVisibleFields {
                    sections.append(.fields)
                }
                sections.append(.dates)
                if !data.isAttachment {
                    sections.append(.abstract)
                }
                return sections
            }

            if !data.creators.isEmpty {
                sections.append(.creators)
            }
            if hasVisibleFields {
                sections.append(.fields)
            }
            sections.append(.dates)
            if let abstract = data.abstract, !abstract.isEmpty {
                sections.append(.abstract)
            }
            if !data.isAttachment && (library.metadataEditable || !state.notes.isEmpty) {
                sections.append(.notes)
            }
            if library.metadataEditable || !state.tags.isEmpty {
                sections.append(.tags)
            }
            if library.metadataAndFilesEditable || !state.attachments.isEmpty {
                sections.append(.attachments)
            }
            sections.append(.collections)

            return sections
        }
    }

    /// Recalculates title width for current data.
    /// - parameter data: New data that change the title width.
    func recalculateTitleWidth(from data: ItemDetailState.Data) {
        let (titleWidth, nonEmptyTitleWidth) = calculateTitleWidths(for: data)
        maxTitleWidth = titleWidth
        maxNonemptyTitleWidth = nonEmptyTitleWidth
    }

    /// Reloads specific section based on snapshot diff. In case of special sections (`title`, `abstract` and `fields`) which don't hold their respective values, their item(s) are always reloaded.
    /// - parameter section: Section to reload.
    /// - parameter state: Current item detail state.
    /// - parameter animated: `true` if change is animated, `false` otherwise.
    func reload(section: Section, state: ItemDetailState, animated: Bool) {
        updateQueue.async { [weak self] in
            guard let self else { return }
            var snapshot = dataSource.snapshot()
            guard let sectionType = snapshot.sectionIdentifiers.first(where: { $0.section == section }) else { return }
            
            if case .collections = section {
                // Collections section is nested, requires separate handling
                if let subSnapshot = state.data.collections?.createSnapshot(parent: .library(state.library), resultTransformer: { Row.collection($0) }) {
                    dataSource.apply(subSnapshot, to: sectionType, animatingDifferences: true)
                }
            } else {
                // Only handle rows for sections which are not nested
                let oldRows = snapshot.itemIdentifiers(inSection: sectionType)
                let newRows = rows(for: section, state: state)
                snapshot.deleteItems(oldRows)
                snapshot.appendItems(newRows, toSection: sectionType)
                let toReload = rowsToReload(from: oldRows, to: newRows, in: section)
                if !toReload.isEmpty {
                    snapshot.reconfigureItems(toReload)
                }
                dataSource.apply(snapshot, animatingDifferences: animated)
            }
        }

        /// Returns an array of rows which need to be reloaded manually. Some sections are "special" because their rows don't hold the values which they show in collection view, they just hold their
        /// identifiers which don't change. So if the value changes, we have to manually reload these rows.
        /// - parameter oldRows: Rows from previous snapshot.
        /// - parameter newRows: Rows from new snapshot.
        /// - parameter section: Section of given rows.
        /// - returns: Array of rows to reload.
        func rowsToReload(from oldRows: [Row], to newRows: [Row], in section: Section) -> [Row] {
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
    }

    /// Update height of updated cell and scroll to it. The cell itself doesn't need to be reloaded, since the change took place inside of it (text field or text view).
    func updateHeightAndScrollToUpdated(row: Row, state: ItemDetailState) {
        guard let indexPath = dataSource.indexPath(for: row), let cellFrame = collectionView.cellForItem(at: indexPath)?.frame else { return }
        updateQueue.async { [weak self] in
            guard let self else { return }
            var snapshot = dataSource.snapshot()
            // Reconfigure the item, otherwise the collection view will use the previously cached cells, if it needs to layout again.
            // E.g. if you press the command key in an external keyboard, while editing, you'll see edited fields revert to their initial value,
            // but only visually, view model hasn't changed!
            snapshot.reconfigureItems([row])
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                let cellBottom = cellFrame.maxY - collectionView.contentOffset.y
                let tableViewBottom = collectionView.superview!.bounds.maxY - collectionView.contentInset.bottom
                let safeAreaTop = collectionView.superview!.safeAreaInsets.top

                // Scroll either when cell bottom is below keyboard or cell top is not visible on screen
                if cellBottom > tableViewBottom || cellFrame.minY < (safeAreaTop + collectionView.contentOffset.y) {
                    // Scroll to top if cell is smaller than visible screen, so that it's fully visible, otherwise scroll to bottom.
                    let position: UICollectionView.ScrollPosition = cellFrame.height + safeAreaTop < tableViewBottom ? .top : .bottom
                    collectionView.scrollToItem(at: indexPath, at: position, animated: false)
                }
            }
        }
    }

    func updateRows(rows: [Row], state: ItemDetailState) {
        updateQueue.async { [weak self] in
            guard let self else { return }
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(rows)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    func updateAttachment(with attachment: Attachment, isProcessing: Bool) {
        updateQueue.async { [weak self] in
            guard let self else { return }
            var snapshot = dataSource.snapshot()

            guard let section = snapshot.sectionIdentifiers.first(where: { $0.section == .attachments }) else { return }

            var rows = snapshot.itemIdentifiers(inSection: section)

            guard let index = rows.firstIndex(where: { $0.isAttachment(withKey: attachment.key) }) else { return }

            snapshot.deleteItems(rows)
            rows[index] = attachmentRow(for: attachment, isProcessing: isProcessing)
            snapshot.appendItems(rows, toSection: section)

            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    func scrollTo(itemKey: String, animated: Bool) {
        var row: Row?

        for _row in dataSource.snapshot().itemIdentifiers {
            switch _row {
            case .note(let key, _, _) where key == itemKey:
                row = _row

            case .attachment(let attachment, _) where attachment.key == itemKey:
                row = _row

            default:
                continue
            }
        }

        guard let row = row, let indexPath = dataSource.indexPath(for: row) else { return }

        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
    }
    
    func focus(row: Row) {
        guard let section = dataSource.snapshot().sectionIdentifier(containingItem: row),
              let sectionId = dataSource.snapshot().indexOfSection(section),
              let rowId = dataSource.snapshot().indexOfItem(row),
              let cell = collectionView.cellForItem(at: IndexPath(row: rowId, section: sectionId)) as? FocusableCell
        else { return }
        cell.focus()
    }

    // MARK: - Helpers

    func rows(for section: Section, state: ItemDetailState) -> [Row] {
        switch section {
        case .abstract:
            return [.abstract]

        case .attachments:
            var attachments = state.attachments.map({ attachment in
                let isProcessing = state.backgroundProcessedItems.contains(attachment.key)
                return attachmentRow(for: attachment, isProcessing: isProcessing)
            })
            if !viewModel.state.data.isAttachment && state.library.metadataAndFilesEditable {
                attachments += [.addAttachment]
            }
            return attachments

        case .creators:
            let creators: [Row] = state.data.creators.values.map({ .creator($0) })
            if state.isEditing {
                return creators + [.addCreator]
            }
            return creators

        case .dates:
            return [.dateAdded(state.data.dateAdded), .dateModified(state.data.dateModified)]

        case .fields:
            return state.visibleFieldIds.compactMap({ fieldId in
                return .field(key: fieldId, multiline: (fieldId == FieldKeys.Item.extra))
            })

        case .notes:
            let notes: [Row] = state.notes.map({ note in
                let isProcessing = state.backgroundProcessedItems.contains(note.key)
                return .note(key: note.key, title: note.title, isProcessing: isProcessing)
            })
            if state.library.metadataEditable {
                return notes + [.addNote]
            }
            return notes

        case .tags:
            let tags: [Row] = state.tags.map({ tag in
                let isProcessing = state.backgroundProcessedItems.contains(tag.name)
                if tag.name.isEmpty {
                    DDLogError("ItemDetailCollectionViewHandler: item \(state.key); \(state.library.identifier); has empty tag")
                }
                return .tag(id: UUID(), tag: tag, isProcessing: isProcessing)
            })
            if state.library.metadataEditable {
                return tags + [.addTag]
            }
            return tags

        case .title:
            return [.title]

        case .type:
            return [.type(state.data.localizedType)]
            
        case .collections:
            // This section is handled separately
            return []
        }
    }

    private func attachmentRow(for attachment: Attachment, isProcessing: Bool) -> Row {
        if isProcessing || delegate?.isDownloadingFromNavigationBar(for: attachment.key) == true {
            return .attachment(attachment: attachment, type: .disabled)
        }

        let (progress, error) = fileDownloader?.data(for: attachment.key, parentKey: viewModel.state.key, libraryId: attachment.libraryId) ?? (nil, nil)

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

    // MARK: - Cells
    
    private lazy var libraryRegistration: UICollectionView.CellRegistration<CollectionCell, Library> = {
        return UICollectionView.CellRegistration<CollectionCell, Library> { [weak self] cell, _, library in
            var configuration = CollectionCell.LibraryContentConfiguration(name: library.name, accessories: [])
            cell.contentConfiguration = configuration
            cell.backgroundConfiguration = .listPlainCell()
        }
    }()
    
    private lazy var collectionRegistration: UICollectionView.CellRegistration<CollectionCell, Collection> = {
        return UICollectionView.CellRegistration<CollectionCell, Collection> { [weak self] cell, _, collection in
            guard let self, let sectionType = self.dataSource.snapshot().sectionIdentifiers.first(where: { $0.section == .collections }) else { return }
            
            let snapshot = self.dataSource.snapshot(for: sectionType)
            let hasChildren = snapshot.contains(.collection(collection)) && !snapshot.snapshot(of: .collection(collection), includingParent: false).items.isEmpty
            var configuration = CollectionCell.ContentConfiguration(collection: collection, hasChildren: hasChildren, accessories: [])
            configuration.isCollapsedProvider = { false }

            cell.contentConfiguration = configuration
            cell.backgroundConfiguration = .listPlainCell()
        }
    }()

    private lazy var titleRegistration: UICollectionView.CellRegistration<ItemDetailTitleCell, (NSAttributedString, Bool)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self else { return }
            let configuration = ItemDetailTitleCell.ContentConfiguration(
                title: data.0,
                isEditing: data.1,
                layoutMargins: layoutMargins(for: indexPath, self: self),
                attributedTextChanged: { [weak self] attributedText in
                    self?.viewModel.process(action: .setTitle(attributedText))
                }
            )
            cell.contentConfiguration = configuration
        }
    }()

    private lazy var fieldRegistration: UICollectionView.CellRegistration<ItemDetailFieldCell, (ItemDetailFieldCell.CellType, CGFloat)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self else { return }
            cell.contentConfiguration = ItemDetailFieldCell.ContentConfiguration(type: data.0, titleWidth: data.1, layoutMargins: layoutMargins(for: indexPath, self: self))

            switch data.0 {
            case .creator:
                cell.accessories = viewModel.state.isEditing ? [.disclosureIndicator(), .delete(), .reorder()] : []

            default:
                cell.accessories = []
            }
        }
    }()

    private lazy var fieldEditRegistration: UICollectionView.CellRegistration<ItemDetailFieldEditCell, (ItemDetailState.Field, CGFloat)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self else { return }
            let configuration = ItemDetailFieldEditCell.ContentConfiguration(field: data.0, titleWidth: data.1, layoutMargins: layoutMargins(for: indexPath, self: self)) { [weak self] text in
                self?.viewModel.process(action: .setFieldValue(id: data.0.key, value: text))
            }
            cell.contentConfiguration = configuration
        }
    }()

    private lazy var fieldMultilineEditRegistration: UICollectionView.CellRegistration<ItemDetailFieldMultilineEditCell, (ItemDetailState.Field, CGFloat)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self else { return }
            let configuration = ItemDetailFieldMultilineEditCell.ContentConfiguration(field: data.0, titleWidth: data.1, layoutMargins: layoutMargins(for: indexPath, self: self)) { [weak self] text in
                self?.viewModel.process(action: .setFieldValue(id: data.0.key, value: text))
            }
            cell.contentConfiguration = configuration
        }
    }()

    private lazy var addRegistration: UICollectionView.CellRegistration<ItemDetailAddCell, String> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, title in
            guard let self else { return }
            cell.contentConfiguration = ItemDetailAddCell.ContentConfiguration(title: title, layoutMargins: layoutMargins(for: indexPath, self: self))
        }
    }()

    private lazy var abstractRegistration: UICollectionView.CellRegistration<ItemDetailAbstractCell, (String, Bool)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self else { return }
            let width = floor(collectionView.frame.width) - (ItemDetailLayout.horizontalInset * 2)
            cell.contentConfiguration = ItemDetailAbstractCell.ContentConfiguration(text: data.0, isCollapsed: data.1, layoutMargins: layoutMargins(for: indexPath, self: self), maxWidth: width)
        }
    }()

    private lazy var abstractEditRegistration: UICollectionView.CellRegistration<ItemDetailAbstractEditCell, String> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, text in
            guard let self else { return }
            cell.contentConfiguration = ItemDetailAbstractEditCell.ContentConfiguration(text: text, layoutMargins: layoutMargins(for: indexPath, self: self), textChanged: { [weak self] text in
                self?.viewModel.process(action: .setAbstract(text))
            })
        }
    }()

    private lazy var noteRegistration: UICollectionView.CellRegistration<ItemDetailNoteCell, (key: String, title: String, isProcessing: Bool)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self else { return }
            cell.contentConfiguration = ItemDetailNoteCell.ContentConfiguration(title: data.title, isProcessing: data.isProcessing, layoutMargins: layoutMargins(for: indexPath, self: self))
        }
    }()

    private lazy var tagRegistration: UICollectionView.CellRegistration<ItemDetailTagCell, (Tag, Bool)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self else { return }
            cell.contentConfiguration = ItemDetailTagCell.ContentConfiguration(tag: data.0, isProcessing: data.1, layoutMargins: layoutMargins(for: indexPath, self: self))
        }
    }()

    private lazy var attachmentRegistration: UICollectionView.CellRegistration<ItemDetailAttachmentCell, (Attachment, ItemDetailAttachmentCell.Kind)> = {
        return UICollectionView.CellRegistration { [weak self] cell, indexPath, data in
            guard let self else { return }
            cell.contentConfiguration = ItemDetailAttachmentCell.ContentConfiguration(attachment: data.0, type: data.1, layoutMargins: layoutMargins(for: indexPath, self: self))
        }
    }()

    private lazy var emptyRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, ()> = {
        return UICollectionView.CellRegistration { _, _, _ in }
    }()

    private func layoutMargins(for indexPath: IndexPath, self: ItemDetailCollectionViewHandler) -> UIEdgeInsets {
        guard let section = self.dataSource.sectionIdentifier(for: indexPath.section)?.section else { return UIEdgeInsets() }
        let isEditing = self.viewModel.state.isEditing
        let isFirstRow = indexPath.row == 0
        let isLastRow = indexPath.row == (self.dataSource.collectionView(self.collectionView, numberOfItemsInSection: indexPath.section) - 1)
        return ItemDetailLayout.insets(for: section, isEditing: isEditing, isFirstRow: isFirstRow, isLastRow: isLastRow)
    }
}

extension ItemDetailCollectionViewHandler: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }

        switch row {
        case .addNote:
            observer.on(.next(.openNoteEditor(key: nil)))

        case .addAttachment:
            observer.on(.next(.openFilePicker))

        case .addCreator:
            observer.on(.next(.openCreatorCreation))

        case .addTag:
            observer.on(.next(.openTagPicker))

        case .abstract:
            guard !viewModel.state.isEditing else { return }
            viewModel.process(action: .toggleAbstractDetailCollapsed)

        case .attachment(let attachment, let type):
            guard type != .disabled else { return }
            viewModel.process(action: .openAttachment(attachment.key))

        case .creator(let creator):
            guard viewModel.state.isEditing else { return }
            observer.on(.next(.openCreatorEditor(creator)))

        case .note(let key, _, let isProcessing):
            guard !isProcessing else { return }
            observer.on(.next(.openNoteEditor(key: key)))

        case .type:
            guard viewModel.state.isEditing && !viewModel.state.data.isAttachment else { return }
            observer.on(.next(.openTypePicker))

        case .field(let fieldId, _):
            // Tappable fields should be only tappable when not in editing mode, or field is not editable. E.g. in case of attachment, URL is not editable, so keep it tappable even while editing.
            guard let field = viewModel.state.data.fields[fieldId], field.isTappable, !viewModel.state.isEditing || !field.isEditable else { return }
            switch field.key {
            case FieldKeys.Item.Attachment.url:
                observer.on(.next(.openUrl(field.value)))

            case FieldKeys.Item.doi:
                observer.on(.next(.openDoi(field.value)))

            default:
                break
            }

        case .collection(let collection):
            guard !viewModel.state.isEditing else { return }
            observer.on(.next(.openCollection(collection)))
            
        case .library(let library):
            guard !viewModel.state.isEditing else { return }
            observer.on(.next(.openLibrary(library)))

        case .title, .dateAdded, .dateModified, .tag:
            break
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        targetIndexPathForMoveOfItemFromOriginalIndexPath originalIndexPath: IndexPath,
        atCurrentIndexPath currentIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        let section = dataSource.sectionIdentifier(for: proposedIndexPath.section)?.section
        if section != .creators { return originalIndexPath }
        if let row = dataSource.itemIdentifier(for: proposedIndexPath) {
            switch row {
            case .addCreator:
                return originalIndexPath

            default:
                break
            }
        }
        return proposedIndexPath
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !viewModel.state.isEditing, let row = dataSource.itemIdentifier(for: indexPath) else { return nil }

        let menu: UIMenu?

        switch row {
        case .field(let fieldId, _):
            guard let field = viewModel.state.data.fields[fieldId] else { return nil }
            menu = createContextMenu(for: field)

        case .attachment(let attachment, _):
            menu = createContextMenu(for: attachment)

        case .tag(_, let tag, _):
            menu = createContextMenu(for: tag)

        case .note(let key, _, _):
            menu = createContextMenuForNote(key: key)
            
        case .collection(let collection) where collection.isAvailable:
            menu = createContextMenu(for: collection)

        default:
            return nil
        }

        return menu.flatMap({ menu in UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in menu }) })

        func createContextMenu(for attachment: Attachment) -> UIMenu? {
            var actions: [UIAction] = []

            if case .file(_, _, let location, _, _) = attachment.type, location == .local {
                actions.append(UIAction(title: L10n.ItemDetail.deleteAttachmentFile, image: UIImage(systemName: "trash"), attributes: []) { [weak self] _ in
                    self?.viewModel.process(action: .deleteAttachmentFile(attachment))
                })
            }

            if viewModel.state.library.metadataEditable, !viewModel.state.data.isAttachment, !viewModel.state.isTrash {
                if case .file = attachment.type {
                    actions.append(UIAction(title: L10n.ItemDetail.moveToStandaloneAttachment, image: UIImage(systemName: "arrow.up.to.line"), attributes: []) { [weak self] _ in
                        self?.viewModel.process(action: .moveAttachmentToStandalone(attachment))
                    })
                }

                actions.append(UIAction(title: L10n.moveToTrash, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.viewModel.process(action: .deleteAttachment(attachment))
                })
            }

            return UIMenu(title: "", children: actions)
        }

        func createContextMenuForNote(key: String) -> UIMenu? {
            guard viewModel.state.library.metadataEditable else { return nil }
            var actions: [UIAction] = []
            actions.append(UIAction(title: L10n.moveToTrash, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.viewModel.process(action: .deleteNote(key: key))
            })
            return UIMenu(title: "", children: actions)
        }

        func createContextMenu(for tag: Tag) -> UIMenu? {
            guard viewModel.state.library.metadataEditable else { return nil }
            var actions: [UIAction] = []
            actions.append(UIAction(title: L10n.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.viewModel.process(action: .deleteTag(tag))
            })
            return UIMenu(title: "", children: actions)
        }

        func createContextMenu(for field: ItemDetailState.Field) -> UIMenu? {
            guard (field.key == FieldKeys.Item.doi || field.baseField == FieldKeys.Item.doi) || (field.key == FieldKeys.Item.url || field.baseField == FieldKeys.Item.url) else { return nil }
            return UIMenu(title: "", children: [UIAction(title: L10n.copy, handler: { _ in
                UIPasteboard.general.string = field.value
            })])
        }
        
        func createContextMenu(for collection: Collection) -> UIMenu? {
            guard viewModel.state.library.metadataEditable else { return nil }
            var actions: [UIAction] = []
            actions.append(UIAction(title: L10n.delete, image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.viewModel.process(action: .deleteCollection(collection.id))
            })
            return UIMenu(title: "", children: actions)
        }
    }
}
