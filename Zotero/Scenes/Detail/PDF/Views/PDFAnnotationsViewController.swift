//
//  PDFAnnotationsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RxSwift

typealias AnnotationsViewControllerAction = (AnnotationView.Action, Annotation, UIButton) -> Void

protocol AnnotationsDelegate: AnyObject {
    func parseAndCacheIfNeededAttributedText(for annotation: PDFAnnotation, with font: UIFont) -> NSAttributedString?
    func parseAndCacheIfNeededAttributedComment(for annotation: PDFAnnotation) -> NSAttributedString?
}

final class PDFAnnotationsViewController: UIViewController {
    private static let cellId = "AnnotationCell"
    private unowned let viewModel: ViewModel<PDFReaderActionHandler>
    private let updateQueue: DispatchQueue
    private let disposeBag: DisposeBag

    private weak var emptyLabel: UILabel!
    private weak var tableView: UITableView!
    private weak var toolbarContainer: UIView!
    private weak var toolbar: UIToolbar!
    private var tableViewToToolbar: NSLayoutConstraint!
    private var tableViewToBottom: NSLayoutConstraint!
    private weak var deleteBarButton: UIBarButtonItem?
    private weak var mergeBarButton: UIBarButtonItem?
    private var dataSource: TableViewDiffableDataSource<Int, PDFReaderState.AnnotationKey>!
    private var searchController: UISearchController!

    weak var parentDelegate: (PDFReaderContainerDelegate & SidebarDelegate & AnnotationsDelegate)?
    weak var coordinatorDelegate: PdfAnnotationsCoordinatorDelegate?
    weak var boundingBoxConverter: AnnotationBoundingBoxConverter?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>) {
        self.viewModel = viewModel
        disposeBag = DisposeBag()
        updateQueue = DispatchQueue(label: "org.zotero.PDFAnnotationsViewController.UpdateQueue")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        definesPresentationContext = true
        setupViews()
        setupToolbar(to: viewModel.state)
        setupDataSource()
        setupSearchController()
        setupKeyboardObserving()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        tableView.setEditing(viewModel.state.sidebarEditingEnabled, animated: false)
        updateQueue.async { [weak self] in
            guard let self else { return }
            var snapshot = NSDiffableDataSourceSnapshot<Int, PDFReaderState.AnnotationKey>()
            snapshot.appendSections([0])
            snapshot.appendItems(viewModel.state.sortedKeys)
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self, let key = viewModel.state.focusSidebarKey, let indexPath = dataSource.indexPath(for: key) else { return }
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .middle)
            }
        }

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)
        viewModel.process(action: .startObservingAnnotationPreviewChanges)
    }

    deinit {
        DDLogInfo("AnnotationsViewController deinitialized")
    }

    // MARK: - Actions

    private func perform(action: AnnotationView.Action, annotation: PDFAnnotation) {
        guard viewModel.state.library.metadataEditable else { return }

        switch action {
        case .tags:
            guard annotation.isAuthor(currentUserId: viewModel.state.userId) else { return }
            let selected = Set(annotation.tags.map({ $0.name }))
            coordinatorDelegate?.showTagPicker(
                libraryId: viewModel.state.library.identifier,
                selected: selected,
                userInterfaceStyle: viewModel.state.settings.appearanceMode.userInterfaceStyle,
                picked: { [weak self] tags in
                    self?.viewModel.process(action: .setTags(key: annotation.key, tags: tags))
                }
            )

        case .options(let sender):
            guard let sender else { return }
            let key = annotation.readerKey
            coordinatorDelegate?.showCellOptions(
                for: annotation,
                highlightFont: viewModel.state.textEditorFont,
                userId: viewModel.state.userId,
                library: viewModel.state.library,
                sender: sender,
                userInterfaceStyle: viewModel.state.interfaceStyle,
                saveAction: { [weak viewModel] data, updateSubsequentLabels in
                    guard let viewModel else { return }
                    viewModel.process(action: .updateAnnotationProperties(
                        key: key.key,
                        color: data.color,
                        lineWidth: data.lineWidth,
                        fontSize: data.fontSize ?? 0,
                        pageLabel: data.pageLabel,
                        updateSubsequentLabels: updateSubsequentLabels,
                        highlightText: data.highlightText,
                        higlightFont: data.highlightFont
                    ))
                },
                deleteAction: { [weak self] in
                    self?.viewModel.process(action: .removeAnnotation(key))
                }
            )

        case .setComment(let comment):
            viewModel.process(action: .setComment(key: annotation.key, comment: comment))

        case .reloadHeight:
            updateCellHeight()
            focusSelectedCell()

        case .setCommentActive(let isActive):
            viewModel.process(action: .setCommentActive(isActive))

        case .done: break // Done button doesn't appear here
        }
    }

    private func update(state: PDFReaderState) {
        if state.changes.contains(.annotations) {
            tableView.isHidden = (state.snapshotKeys ?? state.sortedKeys).isEmpty
            toolbarContainer.isHidden = tableView.isHidden
            emptyLabel.isHidden = !tableView.isHidden
        }

        reloadIfNeeded(for: state) { [weak self] in
            guard let self else { return }

            if let keys = state.loadedPreviewImageAnnotationKeys {
                updatePreviewsIfVisible(for: keys)
            }

            if let key = state.focusSidebarKey, let indexPath = dataSource.indexPath(for: key) {
                let isVisible = parentDelegate?.isSidebarVisible ?? false
                tableView.selectRow(at: indexPath, animated: isVisible, scrollPosition: .middle)
            }

            if state.changes.contains(.sidebarEditingSelection) {
                deleteBarButton?.isEnabled = state.deletionEnabled
                mergeBarButton?.isEnabled = state.mergingEnabled
            }

            if state.changes.contains(.filter) || state.changes.contains(.annotations) || state.changes.contains(.sidebarEditing) {
                setupToolbar(to: state)
            }
        }
    }

    /// Updates `UIImage` of `SquareAnnotation` preview if the cell is currently on screen.
    /// - parameter keys: Set of keys to update.
    private func updatePreviewsIfVisible(for keys: Set<String>) {
        let cells = tableView.visibleCells.compactMap({ $0 as? AnnotationCell }).filter({ keys.contains($0.key) })

        for cell in cells {
            let image = viewModel.state.previewCache.object(forKey: (cell.key as NSString))
            cell.updatePreview(image: image)
        }
    }

    /// Reloads tableView if needed, based on new state. Calls completion either when reloading finished or when there was no reload.
    /// - parameter state: Current state.
    /// - parameter completion: Called after reload was performed or even if there was no reload.
    private func reloadIfNeeded(for state: PDFReaderState, completion: @escaping () -> Void) {
        if state.document.pageCount == 0 {
            DDLogWarn("AnnotationsViewController: trying to reload empty document")
            completion()
            return
        }

        let isVisible = parentDelegate?.isSidebarVisible ?? false

        if state.changes.contains(.annotations) {
            if state.changes.contains(.sidebarEditing) {
                tableView.setEditing(state.sidebarEditingEnabled, animated: false)
            }
            updateQueue.async { [weak self] in
                guard let self else { return }
                var snapshot = NSDiffableDataSourceSnapshot<Int, PDFReaderState.AnnotationKey>()
                snapshot.appendSections([0])
                snapshot.appendItems(state.sortedKeys)
                if let keys = state.updatedAnnotationKeys {
                    snapshot.reloadItems(keys)
                }
                dataSource.apply(snapshot, animatingDifferences: isVisible, completion: completion)
            }
            return
        }

        if state.changes.contains(.interfaceStyle) {
            updateQueue.async { [weak self] in
                guard let self else { return }
                var snapshot = dataSource.snapshot()
                guard !snapshot.sectionIdentifiers.isEmpty else { return }
                snapshot.reloadSections([0])
                dataSource.apply(snapshot, animatingDifferences: false, completion: completion)
            }
            return
        }

        if state.changes.contains(.selection) || state.changes.contains(.activeComment) {
            if let keys = state.updatedAnnotationKeys {
                updateQueue.sync { [unowned self] in
                    var snapshot = dataSource.snapshot()
                    snapshot.reloadItems(keys)
                    dataSource.apply(snapshot, animatingDifferences: false)
                }
            }

            updateCellHeight()
            focusSelectedCell()

            if state.changes.contains(.sidebarEditing) {
                tableView.setEditing(state.sidebarEditingEnabled, animated: isVisible)
            }

            completion()
            return
        }

        if state.changes.contains(.library) {
            tableView.reloadData()
        }

        if state.changes.contains(.sidebarEditing) {
            tableView.setEditing(state.sidebarEditingEnabled, animated: true)
        }

        completion()
    }

    /// Updates tableView layout in case any cell changed height.
    private func updateCellHeight() {
        UIView.setAnimationsEnabled(false)
        tableView.beginUpdates()
        tableView.endUpdates()
        UIView.setAnimationsEnabled(true)
    }

    /// Scrolls to selected cell if it's not visible.
    private func focusSelectedCell() {
        guard !viewModel.state.sidebarEditingEnabled, let indexPath = tableView.indexPathForSelectedRow else { return }

        let cellFrame = tableView.rectForRow(at: indexPath)
        let cellBottom = cellFrame.maxY - tableView.contentOffset.y
        let tableViewBottom = tableView.superview!.bounds.maxY - tableView.contentInset.bottom
        let safeAreaTop = tableView.superview!.safeAreaInsets.top

        // Scroll either when cell bottom is below keyboard or cell top is not visible on screen
        if cellBottom > tableViewBottom || cellFrame.minY < (safeAreaTop + tableView.contentOffset.y) {
            // Scroll to top if cell is smaller than visible screen, so that it's fully visible, otherwise scroll to bottom.
            let position: UITableView.ScrollPosition = cellFrame.height + safeAreaTop < tableViewBottom ? .top : .bottom
            tableView.scrollToRow(at: indexPath, at: position, animated: false)
        }
    }

    private func setup(cell: AnnotationCell, with annotation: PDFAnnotation, state: PDFReaderState) {
        let selected = annotation.key == state.selectedAnnotationKey?.key
        let preview: UIImage?
        let text: NSAttributedString?
        let comment: AnnotationView.Comment?

        // Annotation text
        switch annotation.type {
        case .highlight, .underline:
            text = parentDelegate?.parseAndCacheIfNeededAttributedText(for: annotation, with: state.textFont)

        case .note, .image, .ink, .freeText:
            text = nil
        }
        // Annotation comment
        switch annotation.type {
        case .note, .highlight, .image, .underline:
            let attributedString = parentDelegate?.parseAndCacheIfNeededAttributedComment(for: annotation) ?? NSAttributedString()
            comment = .init(attributedString: attributedString, isActive: state.selectedAnnotationCommentActive)

        case .ink, .freeText:
            comment = nil
        }
        // Annotation preview
        switch annotation.type {
        case .image, .ink, .freeText:
            preview = loadPreview(for: annotation, state: state)

        case .note, .highlight, .underline:
            preview = nil
        }

        guard let boundingBoxConverter, let pdfAnnotationsCoordinatorDelegate = coordinatorDelegate else { return }
        cell.setup(
            with: annotation,
            text: text,
            comment: comment,
            preview: preview,
            selected: selected,
            availableWidth: PDFReaderLayout.sidebarWidth,
            library: state.library,
            isEditing: state.sidebarEditingEnabled,
            currentUserId: viewModel.state.userId,
            displayName: viewModel.state.displayName,
            username: viewModel.state.username,
            boundingBoxConverter: boundingBoxConverter,
            pdfAnnotationsCoordinatorDelegate: pdfAnnotationsCoordinatorDelegate,
            state: state
        )
        let actionSubscription = cell.actionPublisher.subscribe(onNext: { [weak self] action in
            self?.perform(action: action, annotation: annotation)
        })
        _ = cell.disposeBag?.insert(actionSubscription)

        func loadPreview(for annotation: PDFAnnotation, state: PDFReaderState) -> UIImage? {
            let preview = state.previewCache.object(forKey: (annotation.key as NSString))
            if preview == nil {
                viewModel.process(action: .requestPreviews(keys: [annotation.key], notify: true))
            }
            return preview
        }
    }

    private func showFilterPopup(from barButton: UIBarButtonItem) {
        var colors: Set<String> = []
        var tags: Set<Tag> = []

        let processAnnotation: (PDFAnnotation) -> Void = { annotation in
            colors.insert(annotation.color)
            for tag in annotation.tags {
                tags.insert(tag)
            }
        }

        for dbAnnotation in viewModel.state.databaseAnnotations {
            guard let annotation = PDFDatabaseAnnotation(item: dbAnnotation) else { continue }
            processAnnotation(annotation)
        }
        for annotation in viewModel.state.documentAnnotations.values {
            processAnnotation(annotation)
        }

        let sortedTags = tags.sorted(by: { lTag, rTag -> Bool in
            if lTag.color.isEmpty == rTag.color.isEmpty {
                return lTag.name.localizedCaseInsensitiveCompare(rTag.name) == .orderedAscending
            }
            if !lTag.color.isEmpty && rTag.color.isEmpty {
                return true
            }
            return false
        })
        var sortedColors: [String] = []
        AnnotationsConfig.allColors.forEach { color in
            if colors.contains(color) {
                sortedColors.append(color)
            }
        }

        coordinatorDelegate?.showFilterPopup(
            from: barButton,
            filter: viewModel.state.filter,
            availableColors: sortedColors,
            availableTags: sortedTags,
            userInterfaceStyle: viewModel.state.settings.appearanceMode.userInterfaceStyle,
            completed: { [weak self] filter in
                self?.viewModel.process(action: .changeFilter(filter))
            }
        )
    }

    // MARK: - Setups

    private func setupViews() {
        self.view.backgroundColor = .systemGray6

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontForContentSizeCategory = true
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .systemGray
        label.text = L10n.Pdf.Sidebar.noAnnotations
        label.setContentHuggingPriority(.defaultLow, for: .vertical)
        label.textAlignment = .center
        view.addSubview(label)

        let tableView = UITableView(frame: self.view.bounds, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.prefetchDataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemGray6
        tableView.backgroundView?.backgroundColor = .systemGray6
        tableView.register(AnnotationCell.self, forCellReuseIdentifier: Self.cellId)
        tableView.setEditing(viewModel.state.sidebarEditingEnabled, animated: false)
        tableView.allowsMultipleSelectionDuringEditing = true
        view.addSubview(tableView)

        let toolbarContainer = UIView()
        toolbarContainer.isHidden = !self.viewModel.state.library.metadataEditable
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbarContainer)

        let toolbar = UIToolbar()
        toolbarContainer.backgroundColor = toolbar.backgroundColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.addSubview(toolbar)

        let tableViewToToolbar = tableView.bottomAnchor.constraint(equalTo: toolbarContainer.topAnchor)
        let tableViewToBottom = tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: toolbarContainer.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbar.topAnchor.constraint(equalTo: toolbarContainer.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        if viewModel.state.library.metadataEditable {
            tableViewToToolbar.isActive = true
        } else {
            tableViewToBottom.isActive = true
        }

        self.toolbar = toolbar
        self.toolbarContainer = toolbarContainer
        self.tableView = tableView
        self.tableViewToBottom = tableViewToBottom
        self.tableViewToToolbar = tableViewToToolbar
        emptyLabel = label
    }

    private func setupDataSource() {
        dataSource = TableViewDiffableDataSource(tableView: tableView, cellProvider: { [weak self] tableView, indexPath, key in
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellId, for: indexPath)

            if let self, let cell = cell as? AnnotationCell, let annotation = viewModel.state.annotation(for: key) {
                cell.contentView.backgroundColor = view.backgroundColor
                setup(cell: cell, with: annotation, state: viewModel.state)
            }

            return cell
        })

        dataSource.canEditRow = { [weak self] indexPath in
            guard let self = self, let key = dataSource.itemIdentifier(for: indexPath) else { return false }
            switch key.type {
            case .database:
                return true

            case .document:
                return false
            }
        }

        dataSource.commitEditingStyle = { [weak self] editingStyle, indexPath in
            guard let self, !viewModel.state.sidebarEditingEnabled && editingStyle == .delete, let key = dataSource.itemIdentifier(for: indexPath), key.type == .database else { return }
            viewModel.process(action: .removeAnnotation(key))
        }
    }

    private func setupSearchController() {
        let insets = UIEdgeInsets(
            top: PDFReaderLayout.searchBarVerticalInset,
            left: PDFReaderLayout.annotationLayout.horizontalInset,
            bottom: PDFReaderLayout.searchBarVerticalInset - PDFReaderLayout.cellSelectionLineWidth,
            right: PDFReaderLayout.annotationLayout.horizontalInset
        )

        var frame = tableView.frame
        frame.size.height = 65

        let searchBar = SearchBar(frame: frame, insets: insets, cornerRadius: 10)
        searchBar.text
            .observe(on: MainScheduler.instance)
            .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
            .subscribe(onNext: { [weak self] text in
                self?.viewModel.process(action: .searchAnnotations(text))
            })
            .disposed(by: disposeBag)
        tableView.tableHeaderView = searchBar
    }

    private func setupTableView(with keyboardData: KeyboardData) {
        var insets = tableView.contentInset
        insets.bottom = keyboardData.visibleHeight
        tableView.contentInset = insets
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
            .disposed(by: disposeBag)

        NotificationCenter.default
            .keyboardWillHide
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] notification in
                if let data = notification.keyboardData {
                    self?.setupTableView(with: data)
                }
            })
            .disposed(by: disposeBag)
    }

    private func setupToolbar(to state: PDFReaderState) {
        setupToolbar(
            filterEnabled: (state.databaseAnnotations?.count ?? 0) > 1,
            filterOn: (state.filter != nil),
            editingEnabled: state.sidebarEditingEnabled,
            deletionEnabled: state.deletionEnabled,
            mergingEnabled: state.mergingEnabled
        )
    }

    private func setupToolbar(filterEnabled: Bool, filterOn: Bool, editingEnabled: Bool, deletionEnabled: Bool, mergingEnabled: Bool) {
        guard !toolbarContainer.isHidden else { return }

        var items: [UIBarButtonItem] = []
        items.append(UIBarButtonItem(systemItem: .flexibleSpace, primaryAction: nil, menu: nil))

        if editingEnabled {
            let merge = UIBarButtonItem(title: L10n.Pdf.AnnotationsSidebar.merge, style: .plain, target: nil, action: nil)
            merge.isEnabled = mergingEnabled
            merge.rx.tap
                .subscribe(onNext: { [weak self] _ in
                     guard let self, viewModel.state.sidebarEditingEnabled else { return }
                     viewModel.process(action: .mergeSelectedAnnotations)
                 })
                 .disposed(by: disposeBag)
            items.append(merge)
            mergeBarButton = merge

            let delete = UIBarButtonItem(title: L10n.delete, style: .plain, target: nil, action: nil)
            delete.isEnabled = deletionEnabled
            delete.rx.tap
                .subscribe(onNext: { [weak self] _ in
                    guard let self, viewModel.state.sidebarEditingEnabled else { return }
                    viewModel.process(action: .removeSelectedAnnotations)
                })
                .disposed(by: disposeBag)
            items.append(delete)
            deleteBarButton = delete
        } else if filterEnabled {
            deleteBarButton = nil
            mergeBarButton = nil

            let filterImageName = filterOn ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle"
            let filter = UIBarButtonItem(image: UIImage(systemName: filterImageName), style: .plain, target: nil, action: nil)
            filter.rx.tap
                .subscribe(onNext: { [weak self, weak filter]  _ in
                    guard let self, let filter else { return }
                    showFilterPopup(from: filter)
                })
                .disposed(by: disposeBag)
            items.insert(filter, at: 0)
        }

        let select = UIBarButtonItem(title: (editingEnabled ? L10n.done : L10n.select), style: .plain, target: nil, action: nil)
        select.rx.tap
            .subscribe(onNext: { [weak self] _ in
                self?.viewModel.process(action: .setSidebarEditingEnabled(!editingEnabled))
            })
            .disposed(by: disposeBag)
        items.append(select)
        
        self.toolbar.items = items
    }
}

extension PDFAnnotationsViewController: UITableViewDelegate, UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let keys = indexPaths.compactMap({ dataSource.itemIdentifier(for: $0) })
            .filter({ key in
                guard let annotation = viewModel.state.annotation(for: key) else { return false }
                switch annotation.type {
                case .image, .ink, .freeText:
                    return true

                case .note, .highlight, .underline:
                    return false
                }
            })
            .map({ $0.key })
        viewModel.process(action: .requestPreviews(keys: keys, notify: false))
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let key = dataSource.itemIdentifier(for: indexPath) else { return }
        if viewModel.state.sidebarEditingEnabled {
            viewModel.process(action: .selectAnnotationDuringEditing(key))
        } else {
            viewModel.process(action: .selectAnnotation(key))
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard viewModel.state.sidebarEditingEnabled, let key = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.process(action: .deselectAnnotationDuringEditing(key))
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return tableView.isEditing
    }
}
