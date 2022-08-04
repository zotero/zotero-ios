//
//  ItemDetailCollectionViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

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
        case note(note: Note, isSaving: Bool)
        case tag(Tag)
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
    weak var delegate: ItemDetailTableViewHandlerDelegate?

    var attachmentSectionIndex: Int? {
        return self.dataSource?.snapshot().sectionIdentifiers.firstIndex(where: { $0.section == .attachments })
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

        self.collectionView.isEditing = state.isEditing
        self.dataSource.apply(snapshot, animatingDifferences: animated, completion: nil)
    }

    /// Recalculates title width for current data.
    /// - parameter data: New data that change the title width.
    func recalculateTitleWidth(from data: ItemDetailState.Data) {
        let (titleWidth, nonEmptyTitleWidth) = self.calculateTitleWidths(for: data)
        self.maxTitleWidth = titleWidth
        self.maxNonemptyTitleWidth = nonEmptyTitleWidth
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
            let attachments: [Row] = state.attachments.map({ attachment in
                if self.delegate?.isDownloadingFromNavigationBar(for: attachment.key) == true {
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

    private func cellLayoutData(for section: Section, isFirstRow: Bool, isLastRow: Bool, isAddCell: Bool, isEditing: Bool)
                                                                                                       -> (separatorInsets: UIEdgeInsets, layoutMargins: UIEdgeInsets, accessories: [UICellAccessory]) {
        var hasSeparator = true
        var accessories: [UICellAccessory] = []

        switch section {
        case .title, .notes: break
        case .abstract:
            hasSeparator = false
        case .attachments: break
            // TODO: implement attachment metadata screen
//            if !isAddCell {
//                accessoryType = .detailButton
//            }
        case .tags, .type, .fields:
            if !isAddCell {
                hasSeparator = isEditing
            }
        case .creators:
            if !isAddCell {
                if isEditing {
                    accessories = [.disclosureIndicator()]
                }
                hasSeparator = isEditing
            }
        case .dates:
            hasSeparator = isEditing && !isLastRow
        }

        let layoutMargins = ItemDetailLayout.insets(for: section, isEditing: isEditing, isFirstRow: isFirstRow, isLastRow: isLastRow)
        let leftSeparatorInset: CGFloat = hasSeparator ? self.separatorLeftInset(for: section, isEditing: isEditing, leftMargin: layoutMargins.left) :
                                                         max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let separatorInsets = UIEdgeInsets(top: 0, left: leftSeparatorInset, bottom: 0, right: 0)
        return (separatorInsets, layoutMargins, accessories)
    }

    private func separatorLeftInset(for section: Section, isEditing: Bool, leftMargin: CGFloat) -> CGFloat {
        switch section {
        case .notes, .attachments, .tags:
            return ItemDetailLayout.iconWidth + (isEditing ? 40 : 0) + leftMargin
        case .abstract, .creators, .dates, .fields, .title, .type:
            return 0
        }
    }

    // MARK: - Cells

    private lazy var titleRegistration: UICollectionView.CellRegistration<ItemDetailTitleCell, (String, Bool)> = {
        return UICollectionView.CellRegistration { cell, indexPath, data in
            cell.contentConfiguration = ItemDetailTitleCell.ContentConfiguration(title: data.0, isEditing: data.1)
            self.setup(cell: cell, at: indexPath, isAdd: false)
        }
    }()

    private lazy var fieldRegistration: UICollectionView.CellRegistration<ItemDetailFieldCell, (ItemDetailFieldCell.CellType, CGFloat)> = {
        return UICollectionView.CellRegistration { cell, indexPath, data in
            cell.contentConfiguration = ItemDetailFieldCell.ContentConfiguration(type: data.0, titleWidth: data.1)
            self.setup(cell: cell, at: indexPath, isAdd: false)
        }
    }()

    private lazy var fieldEditRegistration: UICollectionView.CellRegistration<ItemDetailFieldEditCell, (ItemDetailState.Field, CGFloat)> = {
        return UICollectionView.CellRegistration { cell, indexPath, data in
            cell.contentConfiguration = ItemDetailFieldEditCell.ContentConfiguration(field: data.0, titleWidth: data.1)
            self.setup(cell: cell, at: indexPath, isAdd: false)

            guard let observable = cell.textObservable else { return }

            observable.subscribe(onNext: { [weak self] value in
                self?.viewModel.process(action: .setFieldValue(id: data.0.key, value: value))
            }).disposed(by: cell.newDisposeBag)
        }
    }()

    private lazy var fieldMultilineEditRegistration: UICollectionView.CellRegistration<ItemDetailFieldMultilineEditCell, (ItemDetailState.Field, CGFloat)> = {
        return UICollectionView.CellRegistration { cell, indexPath, data in
            cell.contentConfiguration = ItemDetailFieldMultilineEditCell.ContentConfiguration(field: data.0, titleWidth: data.1)
            self.setup(cell: cell, at: indexPath, isAdd: false)

            guard let observable = cell.textObservable else { return }

            observable.subscribe(onNext: { [weak self] value in
                self?.viewModel.process(action: .setFieldValue(id: data.0.key, value: value))
            }).disposed(by: cell.newDisposeBag)
        }
    }()

    private lazy var addRegistration: UICollectionView.CellRegistration<ItemDetailAddCell, String> = {
        return UICollectionView.CellRegistration { cell, indexPath, title in
            cell.contentConfiguration = ItemDetailAddCell.ContentConfiguration(title: title)
            self.setup(cell: cell, at: indexPath, isAdd: true)
        }
    }()

    private lazy var abstractRegistration: UICollectionView.CellRegistration<ItemDetailAbstractCell, (String, Bool)> = {
        return UICollectionView.CellRegistration { cell, indexPath, data in
            cell.contentConfiguration = ItemDetailAbstractCell.ContentConfiguration(text: data.0, isCollapsed: data.1)
            self.setup(cell: cell, at: indexPath, isAdd: false)
        }
    }()

    private lazy var abstractEditRegistration: UICollectionView.CellRegistration<ItemDetailAbstractEditCell, String> = {
        return UICollectionView.CellRegistration { cell, indexPath, text in
            cell.contentConfiguration = ItemDetailAbstractEditCell.ContentConfiguration(text: text)
            self.setup(cell: cell, at: indexPath, isAdd: false)

            guard let observable = cell.textObservable else { return }

            observable.subscribe(onNext: { [weak self] abstract in
                self?.viewModel.process(action: .setAbstract(abstract))
            }).disposed(by: cell.newDisposeBag)
        }
    }()

    private lazy var noteRegistration: UICollectionView.CellRegistration<ItemDetailNoteCell, (Note, Bool)> = {
        return UICollectionView.CellRegistration { cell, indexPath, data in
            cell.contentConfiguration = ItemDetailNoteCell.ContentConfiguration(note: data.0, isSaving: data.1)
            self.setup(cell: cell, at: indexPath, isAdd: false)
        }
    }()

    private lazy var tagRegistration: UICollectionView.CellRegistration<ItemDetailTagCell, (Tag, Bool)> = {
        return UICollectionView.CellRegistration { cell, indexPath, data in
            cell.contentConfiguration = ItemDetailTagCell.ContentConfiguration(tag: data.0, isEditing: data.1)
            self.setup(cell: cell, at: indexPath, isAdd: false)
        }
    }()

    private lazy var attachmentRegistration: UICollectionView.CellRegistration<ItemDetailAttachmentCell, (Attachment, ItemDetailAttachmentCell.Kind)> = {
        return UICollectionView.CellRegistration { cell, indexPath, data in
            cell.contentConfiguration = ItemDetailAttachmentCell.ContentConfiguration(attachment: data.0, type: data.1)
            self.setup(cell: cell, at: indexPath, isAdd: false)
        }
    }()

    private lazy var emptyRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, ()> = {
        return UICollectionView.CellRegistration { cell, indexPath, _ in }
    }()

    // MARK: - Layout

    private func createCollectionViewLayout() -> UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { [unowned self] index, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false

            let section = self.dataSource.snapshot().sectionIdentifiers[index].section
            var supplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] = []

            switch section {
            case .attachments, .tags, .notes:
                configuration.headerMode = .supplementary
                let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
                                                                         elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
                supplementaryItems.append(header)

            default: break
            }

            let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            layoutSection.boundarySupplementaryItems = supplementaryItems
            return layoutSection
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
        self.collectionView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none
        self.collectionView.register(UINib(nibName: "ItemDetailSectionView", bundle: nil), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "Header")

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
            guard let `self` = self else { return collectionView.dequeueConfiguredReusableCell(using: emptyRegistration, for: indexPath, item: ()) }

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

                if !isEditing {
                    return collectionView.dequeueConfiguredReusableCell(using: fieldRegistration, for: indexPath, item: (.field(field), titleWidth))
                }

                if multiline {
                    return collectionView.dequeueConfiguredReusableCell(using: fieldMultilineEditRegistration, for: indexPath, item: (field, titleWidth))
                }

                return collectionView.dequeueConfiguredReusableCell(using: fieldEditRegistration, for: indexPath, item: (field, titleWidth))

            case .note(let note, let isSaving):
                return collectionView.dequeueConfiguredReusableCell(using: noteRegistration, for: indexPath, item: (note, isSaving))

            case .tag(let tag):
                return collectionView.dequeueConfiguredReusableCell(using: tagRegistration, for: indexPath, item: (tag, isEditing))

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

        self.dataSource.reorderingHandlers.canReorderItem = { [weak self] row -> Bool in
            switch row {
            case .creator: return true
            default: return false
            }
        }

        self.dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
        }
    }

    private func setup(cell: UICollectionViewListCell, at indexPath: IndexPath, isAdd: Bool) {
        let snapshot = self.dataSource.snapshot()

        guard indexPath.section < snapshot.numberOfSections else { return }

        let section = snapshot.sectionIdentifiers[indexPath.section].section
        let isEditing = self.viewModel.state.isEditing
        let isFirst = indexPath.row == 0
        let isLast = indexPath.row == (self.dataSource.collectionView(self.collectionView, numberOfItemsInSection: indexPath.section) - 1)
        let (separatorInsets, layoutMargins, accessories) = self.cellLayoutData(for: section, isFirstRow: isFirst, isLastRow: isLast, isAddCell: isAdd, isEditing: isEditing)

        // TODO: - Add separator insets
//        cell.separatorInset = separatorInsets
        cell.layoutMargins = layoutMargins
        cell.contentView.layoutMargins = layoutMargins
        cell.accessories = accessories
        cell.accessibilityTraits = []
    }

    private func setupCollectionView(with keyboardData: KeyboardData) {
        var insets = self.collectionView.contentInset
        insets.bottom = keyboardData.endFrame.height
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

}
