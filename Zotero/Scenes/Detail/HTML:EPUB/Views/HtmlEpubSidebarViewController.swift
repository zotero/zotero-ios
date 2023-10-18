//
//  HtmlEpubSidebarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 05.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class HtmlEpubSidebarViewController: UIViewController {
    private static let cellId = "AnnotationCell"
    private let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!
    private var dataSource: TableViewDiffableDataSource<Int, String>!
    weak var coordinatorDelegate: HtmlEpubSidebarCoordinatorDelegate?

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemGray6
        setupViews()
        setupDataSource()
        setupObserving()

        func setupObserving() {
            self.viewModel.stateObservable
                          .observe(on: MainScheduler.instance)
                          .subscribe(with: self, onNext: { `self`, state in
                              self.update(state: state)
                          })
                          .disposed(by: self.disposeBag)
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
            self.view.addSubview(tableView)
            self.tableView = tableView

            NSLayoutConstraint.activate([
                self.view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: tableView.topAnchor),
                self.view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
                self.view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
                self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: tableView.trailingAnchor)
            ])
        }

        func setupDataSource() {
            self.dataSource = TableViewDiffableDataSource(tableView: self.tableView, cellProvider: { [weak self] tableView, indexPath, key in
                let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellId, for: indexPath)

                if let self, let cell = cell as? AnnotationCell, let annotation = self.viewModel.state.annotations[key] {
                    cell.contentView.backgroundColor = self.view.backgroundColor
                    setup(cell: cell, with: annotation, state: self.viewModel.state)
                }

                return cell
            })

            self.dataSource.canEditRow = { _ in
                return true
            }
//            self.dataSource.commitEditingStyle = { [weak self] editingStyle, indexPath in
//                guard let self, let key = self.dataSource.itemIdentifier(for: indexPath) else { return }
//                self.viewModel.process(action: .removeAnnotation(key))
//            }
        }

        func setup(cell: AnnotationCell, with annotation: HtmlEpubAnnotation, state: HtmlEpubReaderState) {
            let selected = annotation.key == state.selectedAnnotationKey
            let comment = AnnotationView.Comment(attributedString: loadAttributedComment(for: annotation), isActive: state.selectedAnnotationCommentActive)

            cell.setup(
                with: annotation,
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
            _ = cell.disposeBag.insert(actionSubscription)
        }
        
        func loadAttributedComment(for annotation: HtmlEpubAnnotation) -> NSAttributedString? {
            let comment = annotation.comment

            guard !comment.isEmpty else { return nil }

            if let attributedComment = self.viewModel.state.comments[annotation.key] {
                return attributedComment
            }

            self.viewModel.process(action: .parseAndCacheComment(key: annotation.key, comment: comment))
            return self.viewModel.state.comments[annotation.key]
        }
    }

    func update(state: HtmlEpubReaderState) {
        reloadIfNeeded(for: state) {
        }

        /// Reloads tableView if needed, based on new state. Calls completion either when reloading finished or when there was no reload.
        /// - parameter state: Current state.
        /// - parameter completion: Called after reload was performed or even if there was no reload.
        func reloadIfNeeded(for state: HtmlEpubReaderState, completion: @escaping () -> Void) {
            if state.changes.contains(.annotations) {
                var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
                snapshot.appendSections([0])
                snapshot.appendItems(state.sortedKeys)
                if let keys = state.updatedAnnotationKeys {
                    snapshot.reloadItems(keys)
                }

                let isVisible = false//self.parentDelegate?.isSidebarVisible ?? false

//                if state.changes.contains(.sidebarEditing) {
//                    self.tableView.setEditing(state.sidebarEditingEnabled, animated: isVisible)
//                }
                self.dataSource.apply(snapshot, animatingDifferences: isVisible, completion: completion)

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
                    var snapshot = self.dataSource.snapshot()
                    snapshot.reloadItems(keys)
                    self.dataSource.apply(snapshot, animatingDifferences: false)
                }

                self.updateCellHeight()
                self.focusSelectedCell()

//                if state.changes.contains(.sidebarEditing) {
//                    self.tableView.setEditing(state.sidebarEditingEnabled, animated: isVisible)
//                }

                completion()

                return
            }

//            if state.changes.contains(.sidebarEditing) {
//                self.tableView.setEditing(state.sidebarEditingEnabled, animated: true)
//            }

            completion()
        }
    }

    func perform(action: AnnotationView.Action, annotation: HtmlEpubAnnotation) {
        let state = self.viewModel.state

        guard state.library.metadataEditable else { return }

        switch action {
        case .tags:
            guard annotation.isAuthor else { return }
            let selected = Set(annotation.tags.map({ $0.name }))
            self.coordinatorDelegate?.showTagPicker(libraryId: state.library.identifier, selected: selected, userInterfaceStyle: .light, picked: { [weak self] tags in
                self?.viewModel.process(action: .setTags(key: annotation.key, tags: tags))
            })

        case .options(let sender):
            break
//            self.coordinatorDelegate?.showCellOptions(
//                for: annotation,
//                userId: self.viewModel.state.userId,
//                library: self.viewModel.state.library,
//                sender: sender,
//                userInterfaceStyle: self.viewModel.state.interfaceStyle,
//                saveAction: { [weak self] key, color, lineWidth, pageLabel, updateSubsequentLabels, highlightText in
//                    self?.viewModel.process(
//                        action: .updateAnnotationProperties(
//                            key: key.key,
//                            color: color,
//                            lineWidth: lineWidth,
//                            pageLabel: pageLabel,
//                            updateSubsequentLabels: updateSubsequentLabels,
//                            highlightText: highlightText
//                        )
//                    )
//                },
//                deleteAction: { [weak self] key in
//                    self?.viewModel.process(action: .removeAnnotation(key))
//                }
//            )

        case .setComment(let comment):
            self.viewModel.process(action: .setComment(key: annotation.key, comment: comment))

        case .reloadHeight:
            self.updateCellHeight()
            self.focusSelectedCell()

        case .setCommentActive(let isActive):
            self.viewModel.process(action: .setCommentActive(isActive))

        case .done:
            break // Done button doesn't appear here
        }
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
//            guard !self.viewModel.state.sidebarEditingEnabled, let indexPath = self.tableView.indexPathForSelectedRow else { return }
        guard let indexPath = self.tableView.indexPathForSelectedRow else { return }

        let cellFrame = self.tableView.rectForRow(at: indexPath)
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
}

extension HtmlEpubSidebarViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let key = self.dataSource.itemIdentifier(for: indexPath) else { return }
//        if self.viewModel.state.sidebarEditingEnabled {
//            self.viewModel.process(action: .selectAnnotationDuringEditing(key))
//        } else {
        self.viewModel.process(action: .selectAnnotation(key))
//        }
    }
//    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
//        guard let annotation = self.dataSource.itemIdentifier(for: indexPath) else { return }
//        self.viewModel.process(action: .deselectAnnotationDuringEditing(annotation.key))
//    }
    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return tableView.isEditing
    }
}
