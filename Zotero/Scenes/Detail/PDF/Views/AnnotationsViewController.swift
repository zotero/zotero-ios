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

class AnnotationsViewController: UIViewController {
    private static let cellId = "AnnotationCell"
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!
    private var searchController: UISearchController!

    weak var coordinatorDelegate: DetailAnnotationsCoordinatorDelegate?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>) {
        self.viewModel = viewModel
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
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .startObservingAnnotationChanges)
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

        case .reloadHeight:
            self.updateCellHeight()
            self.focusSelectedCell()

        case .setCommentActive(let isActive):
            self.viewModel.process(action: .setCommentActive(isActive))
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
        if state.changes.contains(.selection) || state.changes.contains(.activeComment) {
            // Reload updated cells which are visible
            if let indexPaths = state.updatedAnnotationIndexPaths {
                for indexPath in indexPaths {
                    guard let cell = self.tableView.cellForRow(at: indexPath) as? AnnotationCell else { continue }
                    self.setup(cell: cell, at: indexPath, state: state)
                }
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

        if state.insertedAnnotationIndexPaths == nil && state.removedAnnotationIndexPaths == nil && state.updatedAnnotationIndexPaths == nil {
            self.tableView.reloadData()
            completion()
            return
        }

        self.reload(insertions: state.insertedAnnotationIndexPaths, deletions: state.removedAnnotationIndexPaths, updates: state.updatedAnnotationIndexPaths, completion: completion)
    }

    /// Updates tableView layout in case any cell changed height.
    private func updateCellHeight() {
        self.tableView.beginUpdates()
        self.tableView.endUpdates()
    }

    /// Scrolls to selected cell if it's not visible.
    private func focusSelectedCell() {
        guard let indexPath = self.tableView.indexPathForSelectedRow else { return }

        let cellBottom = self.tableView.rectForRow(at: indexPath).maxY - self.tableView.contentOffset.y
        let tableViewBottom = self.tableView.superview!.bounds.maxY - self.tableView.contentInset.bottom

        guard cellBottom > tableViewBottom else { return }

        self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
    }

    private func reload(insertions: [IndexPath]?, deletions: [IndexPath]?, updates: [IndexPath]?, completion: @escaping () -> Void) {
        self.tableView.performBatchUpdates {
            if let indexPaths = insertions {
                self.tableView.insertRows(at: indexPaths, with: .automatic)
            }
            if let indexPaths = deletions {
                let animation: UITableView.RowAnimation = insertions == nil ? .left : .automatic
                self.tableView.deleteRows(at: indexPaths, with: animation)
            }
            if let indexPaths = updates {
                self.tableView.reloadRows(at: indexPaths, with: .none)
            }
        } completion: { _ in
            completion()
        }
    }

    private func setup(cell: AnnotationCell, at indexPath: IndexPath, state: PDFReaderState) {
        guard let annotation = state.annotations[indexPath.section]?[indexPath.row] else { return }

        let hasWritePermission = state.library.metadataEditable
        let comment = state.comments[annotation.key]
        let selected = annotation.key == state.selectedAnnotation?.key
        let preview: UIImage?

        if annotation.type != .image {
            preview = nil
        } else {
            preview = state.previewCache.object(forKey: (annotation.key as NSString))

            if preview == nil {
                self.viewModel.process(action: .requestPreviews(keys: [annotation.key], notify: true))
            }
        }

        cell.setup(with: annotation, attributedComment: comment, preview: preview, selected: selected, commentActive: state.selectedAnnotationCommentActive,
                   availableWidth: PDFReaderLayout.sidebarWidth, hasWritePermission: hasWritePermission)
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
        tableView.dataSource = self
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

        self.tableView = tableView
    }

    private func setupSearchController() {
//        let controller = UISearchController(searchResultsController: nil)
//        controller.searchBar.searchBarStyle = .minimal
//        controller.searchBar.placeholder = L10n.Pdf.AnnotationsSidebar.searchTitle
//        controller.searchBar.barTintColor = .systemGray6
//        controller.obscuresBackgroundDuringPresentation = false
//        controller.hidesNavigationBarDuringPresentation = false
//
//        var frame = controller.searchBar.frame
//        frame.size.height = 52
//        controller.searchBar.frame = frame

//        self.tableView.tableHeaderView = controller.searchBar
//        self.searchController = controller

//        controller.searchBar.rx

        let insets = UIEdgeInsets(top: PDFReaderLayout.searchBarVerticalInset,
                                  left: PDFReaderLayout.annotationLayout.horizontalInset,
                                  bottom: PDFReaderLayout.searchBarVerticalInset - PDFReaderLayout.cellSelectionLineWidth,
                                  right: PDFReaderLayout.annotationLayout.horizontalInset)

        var frame = self.tableView.frame
        frame.size.height = 65

        let searchBar = SearchBar(frame: frame, insets: insets, cornerRadius: 10)
        searchBar.text.observeOn(MainScheduler.instance)
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

extension AnnotationsViewController: UITableViewDelegate, UITableViewDataSource, UITableViewDataSourcePrefetching {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Int(self.viewModel.state.document.pageCount)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.viewModel.state.annotations[section]?.count ?? 0
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let keys = indexPaths.compactMap({ self.viewModel.state.annotations[$0.section]?[$0.row] }).map({ $0.key })
        self.viewModel.process(action: .requestPreviews(keys: keys, notify: false))
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AnnotationsViewController.cellId, for: indexPath)
        cell.contentView.backgroundColor = self.view.backgroundColor
        if let cell = cell as? AnnotationCell {
            self.setup(cell: cell, at: indexPath, state: self.viewModel.state)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let annotation = self.viewModel.state.annotations[indexPath.section]?[indexPath.row] {
            self.viewModel.process(action: .selectAnnotation(annotation))
        }
    }
}

#endif
