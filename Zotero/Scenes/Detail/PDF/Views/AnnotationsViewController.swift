//
//  AnnotationsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RxSwift

typealias AnnotationsViewControllerAction = (AnnotationView.Action, Annotation, UIButton) -> Void

final class AnnotationsViewController: UIViewController {
    private static let cellId = "AnnotationCell"
    private unowned let viewModel: ViewModel<PDFReaderActionHandler>
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
    private var isVisible: Bool

    weak var sidebarDelegate: SidebarDelegate?
    weak var coordinatorDelegate: DetailAnnotationsCoordinatorDelegate?
    weak var boundingBoxConverter: AnnotationBoundingBoxConverter?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>) {
        self.viewModel = viewModel
        self.isVisible = false
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.definesPresentationContext = true
        self.setupViews()
        self.setupToolbar(to: self.viewModel.state)
        self.setupDataSource()
        self.setupSearchController()
        self.setupKeyboardObserving()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .startObservingAnnotationPreviewChanges)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.isVisible = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.isVisible = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !self.isVisible else { return }

        if let key = self.viewModel.state.focusSidebarKey, let indexPath = self.dataSource.indexPath(for: key) {
            self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .middle)
        }
    }

    deinit {
        DDLogInfo("AnnotationsViewController deinitialized")
    }

    // MARK: - Actions

    private func perform(action: AnnotationView.Action, annotation: Annotation) {
        let state = self.viewModel.state

        guard state.library.metadataEditable else { return }

        switch action {
        case .tags:
            guard annotation.isAuthor(currentUserId: self.viewModel.state.userId) else { return }
            let selected = Set(annotation.tags.map({ $0.name }))
            self.coordinatorDelegate?.showTagPicker(libraryId: state.library.identifier, selected: selected, picked: { [weak self] tags in
                self?.viewModel.process(action: .setTags(key: annotation.key, tags: tags))
            })

        case .options(let sender):
            self.coordinatorDelegate?.showCellOptions(for: annotation, userId: self.viewModel.state.userId, library: self.viewModel.state.library, sender: sender,
                                                      saveAction: { [weak self] key, color, lineWidth, pageLabel, updateSubsequentLabels, highlightText in
                                                          self?.viewModel.process(action: .updateAnnotationProperties(key: key.key, color: color, lineWidth: lineWidth, pageLabel: pageLabel,
                                                                                                                      updateSubsequentLabels: updateSubsequentLabels, highlightText: highlightText))
                                                      },
                                                      deleteAction: { [weak self] key in
                                                          self?.viewModel.process(action: .removeAnnotation(key))
                                                      })

        case .setComment(let comment):
            self.viewModel.process(action: .setComment(key: annotation.key, comment: comment))

        case .reloadHeight:
            self.updateCellHeight()
            self.focusSelectedCell()

        case .setCommentActive(let isActive):
            self.viewModel.process(action: .setCommentActive(isActive))

        case .done: break // Done button doesn't appear here
        }
    }

    private func update(state: PDFReaderState) {
        if state.changes.contains(.annotations) {
            self.tableView.isHidden = (state.snapshotKeys ?? state.sortedKeys).isEmpty
            self.toolbarContainer.isHidden = self.tableView.isHidden
            self.emptyLabel.isHidden = !self.tableView.isHidden
        }

        self.reloadIfNeeded(for: state) {
            if let keys = state.loadedPreviewImageAnnotationKeys {
                self.updatePreviewsIfVisible(for: keys)
            }

            if let key = state.focusSidebarKey, let indexPath = self.dataSource.indexPath(for: key) {
                self.tableView.selectRow(at: indexPath, animated: self.isVisible, scrollPosition: .middle)
            }

            if state.changes.contains(.sidebarEditingSelection) {
                self.deleteBarButton?.isEnabled = state.deletionEnabled
                self.mergeBarButton?.isEnabled = state.mergingEnabled
            }

            if state.changes.contains(.filter) || state.changes.contains(.annotations) || state.changes.contains(.sidebarEditing) {
                self.setupToolbar(to: state)
            }
        }
    }

    /// Updates `UIImage` of `SquareAnnotation` preview if the cell is currently on screen.
    /// - parameter keys: Set of keys to update.
    private func updatePreviewsIfVisible(for keys: Set<String>) {
        let cells = self.tableView.visibleCells.compactMap({ $0 as? AnnotationCell }).filter({ keys.contains($0.key) })

        for cell in cells {
            let image = self.viewModel.state.previewCache.object(forKey: (cell.key as NSString))
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

        if state.changes.contains(.annotations) || state.changes.contains(.interfaceStyle) {
            var snapshot = NSDiffableDataSourceSnapshot<Int, PDFReaderState.AnnotationKey>()
            snapshot.appendSections([0])
            snapshot.appendItems(state.sortedKeys)
            if let keys = state.updatedAnnotationKeys {
                snapshot.reloadItems(keys)
            }

            let isVisible = self.sidebarDelegate?.isSidebarVisible ?? false

            if state.changes.contains(.sidebarEditing) {
                self.tableView.setEditing(state.sidebarEditingEnabled, animated: isVisible)
            }
            self.dataSource.apply(snapshot, animatingDifferences: isVisible, completion: completion)

            return
        }

        if state.changes.contains(.selection) || state.changes.contains(.activeComment) {
            if let keys = state.updatedAnnotationKeys {
                var snapshot = self.dataSource.snapshot()
                snapshot.reloadItems(keys)
                self.dataSource.apply(snapshot, animatingDifferences: false)
            }

            self.updateCellHeight()
            self.focusSelectedCell()

            if state.changes.contains(.sidebarEditing) {
                self.tableView.setEditing(state.sidebarEditingEnabled, animated: isVisible)
            }

            completion()

            return
        }

        if state.changes.contains(.sidebarEditing) {
            self.tableView.setEditing(state.sidebarEditingEnabled, animated: true)
        }

        completion()
    }

    /// Updates tableView layout in case any cell changed height.
    private func updateCellHeight() {
        UIView.setAnimationsEnabled(false)
        self.tableView.beginUpdates()
        self.tableView.endUpdates()
        UIView.setAnimationsEnabled(true)
    }

    /// Scrolls to selected cell if it's not visible.
    private func focusSelectedCell() {
        guard !self.viewModel.state.sidebarEditingEnabled, let indexPath = self.tableView.indexPathForSelectedRow else { return }

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
    }

    private func setup(cell: AnnotationCell, with annotation: Annotation, state: PDFReaderState) {
        let selected = annotation.key == state.selectedAnnotationKey?.key

        let loadPreview: () -> UIImage? = {
            let preview = state.previewCache.object(forKey: (annotation.key as NSString))
            if preview == nil {
                self.viewModel.process(action: .requestPreviews(keys: [annotation.key], notify: true))
            }
            return preview
        }

        let preview: UIImage?
        let comment: AnnotationView.Comment?

        switch annotation.type {
        case .image:
            comment = .init(attributedString: self.loadAttributedComment(for: annotation), isActive: state.selectedAnnotationCommentActive)
            preview = loadPreview()

        case .ink:
            comment = nil
            preview = loadPreview()

        case .note, .highlight:
            preview = nil
            comment = .init(attributedString: self.loadAttributedComment(for: annotation), isActive: state.selectedAnnotationCommentActive)
        }

        if let boundingBoxConverter = self.boundingBoxConverter {
            cell.setup(with: annotation, comment: comment, preview: preview, selected: selected, availableWidth: PDFReaderLayout.sidebarWidth, library: state.library,
                       isEditing: state.sidebarEditingEnabled, currentUserId: self.viewModel.state.userId, displayName: self.viewModel.state.displayName, username: self.viewModel.state.username,
                       boundingBoxConverter: boundingBoxConverter)
        }
        cell.actionPublisher.subscribe(onNext: { [weak self] action in
            self?.perform(action: action, annotation: annotation)
        })
        .disposed(by: cell.disposeBag)
    }

    private func loadAttributedComment(for annotation: Annotation) -> NSAttributedString? {
        let comment = annotation.comment

        guard !comment.isEmpty else { return nil }

        if let attributedComment = self.viewModel.state.comments[annotation.key] {
            return attributedComment
        }

        self.viewModel.process(action: .parseAndCacheComment(key: annotation.key, comment: comment))
        return self.viewModel.state.comments[annotation.key]
    }

    private func showFilterPopup(from barButton: UIBarButtonItem) {
        var colors: Set<String> = []
        var tags: Set<Tag> = []

        let processAnnotation: (Annotation) -> Void = { annotation in
            colors.insert(annotation.color)
            for tag in annotation.tags {
                tags.insert(tag)
            }
        }

        for annotation in self.viewModel.state.databaseAnnotations {
            processAnnotation(DatabaseAnnotation(item: annotation))
        }
        for annotation in self.viewModel.state.documentAnnotations.values {
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
        AnnotationsConfig.colors.forEach { color in
            if colors.contains(color) {
                sortedColors.append(color)
            }
        }

        self.coordinatorDelegate?.showFilterPopup(from: barButton, filter: self.viewModel.state.filter, availableColors: sortedColors, availableTags: sortedTags, completed: { [weak self] filter in
            guard let `self` = self else { return }
            self.viewModel.process(action: .changeFilter(filter))
        })
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
        self.view.addSubview(label)

        let tableView = UITableView(frame: self.view.bounds, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.prefetchDataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemGray6
        tableView.backgroundView?.backgroundColor = .systemGray6
        tableView.register(AnnotationCell.self, forCellReuseIdentifier: AnnotationsViewController.cellId)
        tableView.setEditing(self.viewModel.state.sidebarEditingEnabled, animated: false)
        tableView.allowsMultipleSelectionDuringEditing = true
        self.view.addSubview(tableView)

        let toolbarContainer = UIView()
        toolbarContainer.isHidden = !self.viewModel.state.library.metadataEditable
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(toolbarContainer)

        let toolbar = UIToolbar()
        toolbarContainer.backgroundColor = toolbar.backgroundColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.addSubview(toolbar)

        let tableViewToToolbar = tableView.bottomAnchor.constraint(equalTo: toolbarContainer.topAnchor)
        let tableViewToBottom = tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: self.view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: toolbarContainer.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            toolbarContainer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            toolbarContainer.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            toolbar.topAnchor.constraint(equalTo: toolbarContainer.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            label.topAnchor.constraint(equalTo: self.view.topAnchor),
            label.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        if self.viewModel.state.library.metadataEditable {
            tableViewToToolbar.isActive = true
        } else {
            tableViewToBottom.isActive = true
        }

        self.toolbar = toolbar
        self.toolbarContainer = toolbarContainer
        self.tableView = tableView
        self.tableViewToBottom = tableViewToBottom
        self.tableViewToToolbar = tableViewToToolbar
        self.emptyLabel = label
    }

    private func setupDataSource() {
        self.dataSource = TableViewDiffableDataSource(tableView: self.tableView, cellProvider: { [weak self] tableView, indexPath, key in
            let cell = tableView.dequeueReusableCell(withIdentifier: AnnotationsViewController.cellId, for: indexPath)

            if let `self` = self, let cell = cell as? AnnotationCell, let annotation = self.viewModel.state.annotation(for: key) {
                cell.contentView.backgroundColor = self.view.backgroundColor
                self.setup(cell: cell, with: annotation, state: self.viewModel.state)
            }

            return cell
        })


        self.dataSource.canEditRow = { indexPath in
            guard let key = self.dataSource.itemIdentifier(for: indexPath) else { return false }
            switch key.type {
            case .database: return true
            case .document: return false
            }
        }

        self.dataSource.commitEditingStyle = { [weak self] editingStyle, indexPath in
            guard let `self` = self, !self.viewModel.state.sidebarEditingEnabled && editingStyle == .delete,
                  let key = self.dataSource.itemIdentifier(for: indexPath), key.type == .database else { return }
            self.viewModel.process(action: .removeAnnotation(key))
        }
    }

    private func setupSearchController() {
        let insets = UIEdgeInsets(top: PDFReaderLayout.searchBarVerticalInset,
                                  left: PDFReaderLayout.annotationLayout.horizontalInset,
                                  bottom: PDFReaderLayout.searchBarVerticalInset - PDFReaderLayout.cellSelectionLineWidth,
                                  right: PDFReaderLayout.annotationLayout.horizontalInset)

        var frame = self.tableView.frame
        frame.size.height = 65

        let searchBar = SearchBar(frame: frame, insets: insets, cornerRadius: 10)
        searchBar.text.observe(on: MainScheduler.instance)
                                .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                                .subscribe(onNext: { [weak self] text in
                                    self?.viewModel.process(action: .searchAnnotations(text))
                                })
                                .disposed(by: self.disposeBag)
        self.tableView.tableHeaderView = searchBar
    }

    private func setupTableView(with keyboardData: KeyboardData) {
        var insets = self.tableView.contentInset
        insets.bottom = keyboardData.visibleHeight
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

    private func setupToolbar(to state: PDFReaderState) {
        self.setupToolbar(filterEnabled: (state.databaseAnnotations?.count ?? 0) > 1, filterOn: (state.filter != nil), editingEnabled: state.sidebarEditingEnabled,
                          deletionEnabled: state.deletionEnabled, mergingEnabled: state.mergingEnabled)
    }

    private func setupToolbar(filterEnabled: Bool, filterOn: Bool, editingEnabled: Bool, deletionEnabled: Bool, mergingEnabled: Bool) {
        guard !self.toolbarContainer.isHidden else { return }

        var items: [UIBarButtonItem] = []

        if #available(iOS 14.0, *) {
            items.append(UIBarButtonItem(systemItem: .flexibleSpace, primaryAction: nil, menu: nil))
        } else {
            items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        }

        if editingEnabled {
            let merge = UIBarButtonItem(title: L10n.Pdf.AnnotationsSidebar.merge, style: .plain, target: nil, action: nil)
            merge.isEnabled = mergingEnabled
            merge.rx.tap
                 .subscribe(onNext: { [weak self] _ in
                     guard let `self` = self, self.viewModel.state.sidebarEditingEnabled else { return }
                     self.viewModel.process(action: .mergeSelectedAnnotations)
                 })
                 .disposed(by: self.disposeBag)
            items.append(merge)
            self.mergeBarButton = merge

            let delete = UIBarButtonItem(title: L10n.delete, style: .plain, target: nil, action: nil)
            delete.isEnabled = deletionEnabled
            delete.rx.tap
                  .subscribe(onNext: { [weak self] _ in
                      guard let `self` = self, self.viewModel.state.sidebarEditingEnabled else { return }
                      self.viewModel.process(action: .removeSelectedAnnotations)
                  })
                  .disposed(by: self.disposeBag)
            items.append(delete)
            self.deleteBarButton = delete
        } else if filterEnabled {
            self.deleteBarButton = nil
            self.mergeBarButton = nil

            let filterImageName = filterOn ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle"
            let filter = UIBarButtonItem(image: UIImage(systemName: filterImageName), style: .plain, target: nil, action: nil)
            filter.rx.tap
                  .subscribe(onNext: { [weak self] _ in
                      guard let `self` = self else { return }
                      self.showFilterPopup(from: filter)
                  })
                  .disposed(by: self.disposeBag)
            items.insert(filter, at: 0)
        }

        let select = UIBarButtonItem(title: (editingEnabled ? L10n.done : L10n.select), style: .plain, target: nil, action: nil)
        select.rx.tap
              .subscribe(onNext: { [weak self] _ in
                  self?.viewModel.process(action: .setSidebarEditingEnabled(!editingEnabled))
              })
              .disposed(by: self.disposeBag)
        items.append(select)
        
        self.toolbar.items = items
    }
}

extension AnnotationsViewController: UITableViewDelegate, UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let keys = indexPaths.compactMap({ self.dataSource.itemIdentifier(for: $0) })
                             .filter({ key in
                                 guard let annotation = self.viewModel.state.annotation(for: key) else { return false }
                                 switch annotation.type {
                                 case .image, .ink: return true
                                 case .note, .highlight: return false
                                 }
                             })
                             .map({ $0.key })
        self.viewModel.process(action: .requestPreviews(keys: keys, notify: false))
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let key = self.dataSource.itemIdentifier(for: indexPath) else { return }

        if self.viewModel.state.sidebarEditingEnabled {
            self.viewModel.process(action: .selectAnnotationDuringEditing(key))
        } else {
            self.viewModel.process(action: .selectAnnotation(key))
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard self.viewModel.state.sidebarEditingEnabled, let key = self.dataSource.itemIdentifier(for: indexPath) else { return }
        self.viewModel.process(action: .deselectAnnotationDuringEditing(key))
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return tableView.isEditing
    }
}

#endif
