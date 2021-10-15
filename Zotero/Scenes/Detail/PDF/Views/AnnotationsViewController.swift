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

protocol SidebarParent: AnyObject {
    var isSidebarVisible: Bool { get }
}

typealias AnnotationsViewControllerAction = (AnnotationView.Action, Annotation, UIButton) -> Void

final class AnnotationsViewController: UIViewController {
    private static let cellId = "AnnotationCell"
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!
    private var dataSource: DiffableDataSource<Int, Annotation>!
    private var searchController: UISearchController!
    private var isVisible: Bool

    weak var sidebarParent: SidebarParent?
    weak var coordinatorDelegate: DetailAnnotationsCoordinatorDelegate?

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
        self.view.backgroundColor = .systemGray6
        self.setupTableView()
        self.setupSearchController()
        self.setupKeyboardObserving()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .startObservingAnnotationChanges)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.isVisible = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.isVisible = false
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
            guard annotation.isAuthor else { return }
            let selected = Set(annotation.tags.map({ $0.name }))
            self.coordinatorDelegate?.showTagPicker(libraryId: state.library.identifier, selected: selected, picked: { [weak self] tags in
                self?.viewModel.process(action: .setTags(tags, annotation.key))
            })

        case .options(let sender):
            self.coordinatorDelegate?.showCellOptions(for: annotation, sender: sender,
                                                      saveAction: { [weak self] annotation in
                                                          self?.viewModel.process(action: .updateAnnotationProperties(annotation))
                                                      },
                                                      deleteAction: { [weak self] annotation in
                                                          self?.viewModel.process(action: .removeAnnotation(annotation))
                                                      })

        case .setComment(let comment):
            self.viewModel.process(action: .setComment(key: annotation.key, comment: comment))
            // Since comment is already written in the UITextView, we don't want to reload the cell and therefore the diffable data source is not updated on update of view model. So data source
            // needs to be updated manually so that we keep data consistency.
            if let indexPath = self.dataSource.snapshot.indexPath(where: { $0.key == annotation.key }), let updatedAnnotation = self.viewModel.state.annotations[indexPath.section]?[indexPath.row] {
                self.dataSource.update(object: updatedAnnotation, at: indexPath, withReload: false)
            }

        case .reloadHeight:
            self.updateCellHeight()
            self.focusSelectedCell()

        case .setCommentActive(let isActive):
            self.viewModel.process(action: .setCommentActive(isActive))

        case .done: break // Done button doesn't appear here
        }
    }

    private func update(state: PDFReaderState) {
        self.reloadIfNeeded(for: state) {
            if let keys = state.loadedPreviewImageAnnotationKeys {
                self.updatePreviewsIfVisible(for: keys)
            }

            if let indexPath = state.focusSidebarIndexPath {
                self.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle)
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

        let reloadVisibleCells: ([IndexPath]) -> Void = { [weak self] indexPaths in
            self?.tableView.reloadRows(at: indexPaths, with: .none)
        }

        if !state.changes.contains(.annotations) && (state.changes.contains(.selection) || state.changes.contains(.activeComment)) {
            // Reload updated cells which are visible
            if let indexPaths = state.updatedAnnotationIndexPaths {
                reloadVisibleCells(indexPaths)
            }

            self.updateCellHeight()
            self.focusSelectedCell()

            completion()
            return
        }

        guard state.changes.contains(.annotations) || state.changes.contains(.interfaceStyle) else {
            completion()
            return
        }

        let isVisible = self.sidebarParent?.isSidebarVisible ?? false

        var snapshot = DiffableDataSourceSnapshot<Int, Annotation>(isEditing: false)
        for section in (0..<Int(state.document.pageCount)) {
            snapshot.append(section: section)
        }
        for (page, annotations) in state.annotations {
            guard page < state.document.pageCount else {
                DDLogWarn("AnnotationsViewController: annotations page (\(page)) outside of document bounds (\(state.document.pageCount))")
                continue
            }
            snapshot.append(objects: annotations, for: page)
        }
        let animation: DiffableDataSourceAnimation = !isVisible ? .none : .rows(reload: .fade, insert: .bottom, delete: .bottom)

        self.dataSource.apply(snapshot: snapshot, animation: animation) { finished in
            guard finished else { return }
            if let indexPaths = state.updatedAnnotationIndexPaths {
                reloadVisibleCells(indexPaths)
            }
            completion()
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
        guard let indexPath = self.tableView.indexPathForSelectedRow else { return }

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
        let selected = annotation.key == state.selectedAnnotation?.key

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
            comment = .init(attributedString: state.comments[annotation.key], isActive: state.selectedAnnotationCommentActive)
            preview = loadPreview()

        case .ink:
            comment = nil
            preview = loadPreview()

        case .note, .highlight:
            preview = nil
            comment = .init(attributedString: state.comments[annotation.key], isActive: state.selectedAnnotationCommentActive)
        }

        cell.setup(with: annotation, comment: comment, preview: preview, selected: selected, availableWidth: PDFReaderLayout.sidebarWidth, library: state.library)
        cell.actionPublisher.subscribe(onNext: { [weak self] action in
            self?.perform(action: action, annotation: annotation)
        })
        .disposed(by: cell.disposeBag)
    }

    // MARK: - Setups

    private func setupTableView() {
        let backgroundView = UIView()
        backgroundView.backgroundColor = .systemGray6

        let tableView = UITableView(frame: self.view.bounds, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.prefetchDataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundView = backgroundView
        tableView.register(AnnotationCell.self, forCellReuseIdentifier: AnnotationsViewController.cellId)

        self.view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: self.view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        self.dataSource = DiffableDataSource(tableView: tableView,
                                             dequeueAction: { tableView, indexPath, _, _ in
                                                 return tableView.dequeueReusableCell(withIdentifier: AnnotationsViewController.cellId, for: indexPath)
                                             },
                                             setupAction: { [weak self] cell, _, _, annotation in
                                                 guard let `self` = self, let cell = cell as? AnnotationCell else { return }
                                                 cell.contentView.backgroundColor = self.view.backgroundColor
                                                 self.setup(cell: cell, with: annotation, state: self.viewModel.state)
                                             })
        self.dataSource.dataSource = self

        self.tableView = tableView
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

extension AnnotationsViewController: UITableViewDelegate, UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let keys = indexPaths.compactMap({ self.dataSource.snapshot.object(at: $0) })
                             .filter({
                                 switch $0.type {
                                 case .image, .ink: return true
                                 case .note, .highlight: return false
                                 }
                             })
                             .map({ $0.key })
        self.viewModel.process(action: .requestPreviews(keys: keys, notify: false))
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let annotation = self.dataSource.snapshot.object(at: indexPath) else { return }
        self.viewModel.process(action: .selectAnnotation(annotation))
    }
}

extension AnnotationsViewController: AdditionalDiffableDataSource {
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        guard let annotation = self.dataSource.snapshot.object(at: indexPath) else { return }
        self.viewModel.process(action: .removeAnnotation(annotation))
    }
}

#endif
