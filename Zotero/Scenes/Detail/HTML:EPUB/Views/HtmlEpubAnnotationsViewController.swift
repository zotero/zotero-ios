//
//  HtmlEpubAnnotationsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 05.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class HtmlEpubAnnotationsViewController: UIViewController {
    private static let cellId = "AnnotationCell"
    private let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!
    private weak var toolbarContainer: UIView!
    private weak var toolbar: UIToolbar!
    private weak var deleteBarButton: UIBarButtonItem?
    private var dataSource: TableViewDiffableDataSource<Int, String>!
    private var searchController: UISearchController!
    weak var coordinatorDelegate: ReaderSidebarCoordinatorDelegate?
    weak var parentDelegate: HtmlEpubReaderContainerDelegate?

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        self.viewModel = viewModel
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGray6
        setupViews()
        setupSearchController()
        setupDataSource()
        setupObserving()
        setupToolbar(
            filterEnabled: !viewModel.state.annotations.isEmpty,
            filterOn: (viewModel.state.annotationFilter != nil),
            editingEnabled: viewModel.state.sidebarEditingEnabled,
            deletionEnabled: viewModel.state.deletionEnabled
        )

        if !viewModel.state.annotations.isEmpty {
            reloadAnnotations(for: viewModel.state)
        }

        func setupObserving() {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] state in
                    self?.update(state: state)
                })
                .disposed(by: disposeBag)
        }

        func setupSearchController() {
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

        func setupViews() {
            let tableView = UITableView(frame: self.view.bounds, style: .plain)
            tableView.translatesAutoresizingMaskIntoConstraints = false
            tableView.delegate = self
            tableView.separatorStyle = .none
            tableView.backgroundColor = .systemGray6
            tableView.backgroundView?.backgroundColor = .systemGray6
            tableView.register(AnnotationCell.self, forCellReuseIdentifier: Self.cellId)
            tableView.allowsMultipleSelectionDuringEditing = true
            view.addSubview(tableView)
            self.tableView = tableView

            let toolbarContainer = UIView()
            toolbarContainer.isHidden = !viewModel.state.library.metadataEditable
            toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(toolbarContainer)
            self.toolbarContainer = toolbarContainer

            let toolbar = UIToolbar()
            toolbarContainer.backgroundColor = toolbar.backgroundColor
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            toolbarContainer.addSubview(toolbar)
            self.toolbar = toolbar

            NSLayoutConstraint.activate([
                view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: tableView.topAnchor),
                tableView.bottomAnchor.constraint(equalTo: toolbarContainer.topAnchor),
                view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
                toolbarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                toolbarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                toolbarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                toolbar.topAnchor.constraint(equalTo: toolbarContainer.topAnchor),
                toolbar.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor),
                toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
        }

        func setupDataSource() {
            dataSource = TableViewDiffableDataSource(tableView: tableView, cellProvider: { [weak self] tableView, indexPath, key in
                let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellId, for: indexPath)

                if let self, let cell = cell as? AnnotationCell, let annotation = viewModel.state.annotations[key] {
                    cell.contentView.backgroundColor = self.view.backgroundColor
                    setup(cell: cell, with: annotation, state: viewModel.state)
                }

                return cell
            })

            dataSource.canEditRow = { _ in
                return true
            }
            dataSource.commitEditingStyle = { [weak self] editingStyle, indexPath in
                guard let self, editingStyle == .delete, let key = dataSource.itemIdentifier(for: indexPath) else { return }
                viewModel.process(action: .removeAnnotation(key))
            }
        }

        func setup(cell: AnnotationCell, with annotation: HtmlEpubAnnotation, state: HtmlEpubReaderState) {
            let selected = annotation.key == state.selectedAnnotationKey
            let comment = AnnotationView.Comment(attributedString: loadAttributedComment(for: annotation), isActive: state.selectedAnnotationCommentActive)

            // TODO: - add attributed text
            let text = annotation.text.flatMap({ NSAttributedString(string: $0) })
            cell.setup(
                with: annotation,
                text: text,
                comment: comment,
                selected: selected,
                availableWidth: PDFReaderLayout.sidebarWidth,
                library: state.library,
                isEditing: false,
                currentUserId: state.userId,
                state: state
            )
            let actionSubscription = cell.actionPublisher.subscribe(onNext: { [weak self] action in
                self?.perform(action: action, annotation: annotation)
            })
            _ = cell.disposeBag?.insert(actionSubscription)
        }
        
        func loadAttributedComment(for annotation: HtmlEpubAnnotation) -> NSAttributedString? {
            let comment = annotation.comment

            guard !comment.isEmpty else { return nil }

            if let attributedComment = viewModel.state.comments[annotation.key] {
                return attributedComment
            }

            viewModel.process(action: .parseAndCacheComment(key: annotation.key, comment: comment))
            return viewModel.state.comments[annotation.key]
        }
    }

    func update(state: HtmlEpubReaderState) {
        reloadIfNeeded(for: state) { [weak self] in
            guard let self else { return }

            if state.changes.contains(.filter) || state.changes.contains(.annotations) || state.changes.contains(.sidebarEditing) {
                setupToolbar(
                    filterEnabled: !state.annotations.isEmpty,
                    filterOn: (state.annotationFilter != nil),
                    editingEnabled: state.sidebarEditingEnabled,
                    deletionEnabled: state.deletionEnabled
                )
            }

            if let key = state.focusSidebarKey, let indexPath = dataSource.indexPath(for: key) {
                let isVisible = parentDelegate?.isSidebarVisible ?? false
                tableView.selectRow(at: indexPath, animated: isVisible, scrollPosition: .middle)
            }

            if state.changes.contains(.sidebarEditingSelection) {
                deleteBarButton?.isEnabled = state.deletionEnabled
            }
        }

        /// Reloads tableView if needed, based on new state. Calls completion either when reloading finished or when there was no reload.
        /// - parameter state: Current state.
        /// - parameter completion: Called after reload was performed or even if there was no reload.
        func reloadIfNeeded(for state: HtmlEpubReaderState, completion: @escaping () -> Void) {
            if state.changes.contains(.annotations) {
                reloadAnnotations(for: state, completion: completion)
                return
            }

//            if state.changes.contains(.interfaceStyle) {
//                var snapshot = self.dataSource.snapshot()
//                snapshot.reloadSections([0])
//                self.dataSource.apply(snapshot, animatingDifferences: false, completion: completion)
//                return
//            }

            if state.changes.contains(.selection) || state.changes.contains(.activeComment) {
                if let keys = state.updatedAnnotationKeys {
                    var snapshot = dataSource.snapshot()
                    snapshot.reloadItems(keys)
                    dataSource.apply(snapshot, animatingDifferences: false)
                }

                updateCellHeight()
                focusSelectedCell()

                if state.changes.contains(.sidebarEditing) {
                    let isVisible = parentDelegate?.isSidebarVisible ?? false
                    tableView.setEditing(state.sidebarEditingEnabled, animated: isVisible)
                }

                completion()

                return
            }

            if state.changes.contains(.sidebarEditing) {
                tableView.setEditing(state.sidebarEditingEnabled, animated: true)
            }

            completion()
        }
    }

    private func reloadAnnotations(for state: HtmlEpubReaderState, completion: (() -> Void)? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(state.sortedKeys)
        if let keys = state.updatedAnnotationKeys {
            snapshot.reloadItems(keys)
        }
        let isVisible = parentDelegate?.isSidebarVisible ?? false
        if state.changes.contains(.sidebarEditing) {
            tableView.setEditing(state.sidebarEditingEnabled, animated: isVisible)
        }
        dataSource.apply(snapshot, animatingDifferences: isVisible, completion: completion)
    }

    func perform(action: AnnotationView.Action, annotation: HtmlEpubAnnotation) {
        let state = viewModel.state

        guard state.library.metadataEditable else { return }

        switch action {
        case .tags:
            guard annotation.isAuthor else { return }
            let selected = Set(annotation.tags.map({ $0.name }))
            coordinatorDelegate?.showTagPicker(
                libraryId: state.library.identifier,
                selected: selected,
                userInterfaceStyle: viewModel.state.settings.appearance.userInterfaceStyle,
                picked: { [weak self] tags in
                    self?.viewModel.process(action: .setTags(key: annotation.key, tags: tags))
                }
            )

        case .options(let sender):
            guard let sender else { return }
            let key = annotation.key
            coordinatorDelegate?.showCellOptions(
                for: annotation,
                userId: viewModel.state.userId,
                library: viewModel.state.library,
                highlightFont: viewModel.state.textFont,
                sender: sender,
                userInterfaceStyle: viewModel.state.settings.appearance.userInterfaceStyle,
                saveAction: { [weak self] data, updateSubsequentLabels in
                    self?.viewModel.process(
                        action: .updateAnnotationProperties(
                            key: key,
                            type: data.type,
                            color: data.color,
                            lineWidth: data.lineWidth,
                            pageLabel: data.pageLabel,
                            updateSubsequentLabels: updateSubsequentLabels,
                            highlightText: data.highlightText
                        )
                    )
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

        case .done:
            break // Done button doesn't appear here
        }
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

    private func setupToolbar(filterEnabled: Bool, filterOn: Bool, editingEnabled: Bool, deletionEnabled: Bool) {
        guard !toolbarContainer.isHidden else { return }

        var items: [UIBarButtonItem] = []
        items.append(.flexibleSpace())

        if editingEnabled {
            let delete = UIBarButtonItem(title: L10n.delete)
            delete.tintColor = Asset.Colors.zoteroBlue.color
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

            let filterImageName = filterOn ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle"
            let filter = UIBarButtonItem(image: UIImage(systemName: filterImageName))
            filter.tintColor = Asset.Colors.zoteroBlue.color
            filter.rx.tap
                .subscribe(onNext: { [weak self, weak filter] _ in
                    guard let self, let filter else { return }
                    showFilterPopup(from: filter, viewModel: viewModel, coordinatorDelegate: coordinatorDelegate)
                })
                .disposed(by: disposeBag)
            items.insert(filter, at: 0)
        }

        let select = UIBarButtonItem(title: (editingEnabled ? L10n.done : L10n.select))
        select.tintColor = Asset.Colors.zoteroBlue.color
        select.rx.tap
            .subscribe(onNext: { [weak self] _ in
                self?.viewModel.process(action: .setSidebarEditingEnabled(!editingEnabled))
            })
            .disposed(by: disposeBag)
        items.append(select)

        toolbar.items = items

        func showFilterPopup(from barButton: UIBarButtonItem, viewModel: ViewModel<HtmlEpubReaderActionHandler>, coordinatorDelegate: ReaderSidebarCoordinatorDelegate?) {
            var colors: Set<String> = []
            var tags: Set<Tag> = []

            for (_, annotation) in viewModel.state.annotations {
                colors.insert(annotation.color)
                for tag in annotation.tags {
                    tags.insert(tag)
                }
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
                filter: viewModel.state.annotationFilter,
                availableColors: sortedColors,
                availableTags: sortedTags,
                userInterfaceStyle: viewModel.state.settings.appearance.userInterfaceStyle,
                completed: { [weak self] filter in
                    self?.viewModel.process(action: .changeFilter(filter))
                }
            )
        }
    }
}

extension HtmlEpubAnnotationsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let key = dataSource.itemIdentifier(for: indexPath) else { return }
        if viewModel.state.sidebarEditingEnabled {
            viewModel.process(action: .selectAnnotationDuringEditing(key: key))
        } else {
            viewModel.process(action: .selectAnnotationFromSidebar(key: key))
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let key = dataSource.itemIdentifier(for: indexPath) else { return }
        viewModel.process(action: .deselectAnnotationDuringEditing(key))
    }
    
    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return tableView.isEditing
    }
}
