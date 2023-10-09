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
    private var dataSource: TableViewDiffableDataSource<Int, HtmlEpubAnnotation>!

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
            self.dataSource = TableViewDiffableDataSource(tableView: self.tableView, cellProvider: { [weak self] tableView, indexPath, _ in
                let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellId, for: indexPath)

                if let self, let cell = cell as? AnnotationCell {
                    cell.contentView.backgroundColor = self.view.backgroundColor
//                    self.setup(cell: cell, with: annotation, state: self.viewModel.state)
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
    }

    func update(state: HtmlEpubReaderState) {
        if state.changes.contains(.annotations) {
            updateDataSource()
        }

        func updateDataSource() {
            var snapshot = NSDiffableDataSourceSnapshot<Int, HtmlEpubAnnotation>()
            snapshot.appendSections([0])
            snapshot.appendItems(state.annotations)
            self.dataSource.apply(snapshot, animatingDifferences: true)
        }
    }
}

extension HtmlEpubSidebarViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let annotation = self.dataSource.itemIdentifier(for: indexPath) else { return }
//        if self.viewModel.state.sidebarEditingEnabled {
//            self.viewModel.process(action: .selectAnnotationDuringEditing(key))
//        } else {
//            self.viewModel.process(action: .selectAnnotation(key))
//        }
    }
//    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
//        guard let annotation = self.dataSource.itemIdentifier(for: indexPath) else { return }
//        self.viewModel.process(action: .deselectAnnotationDuringEditing(key))
//    }
    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return tableView.isEditing
    }
}
