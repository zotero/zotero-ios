//
//  TagPickerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class TagPickerViewController: UIViewController {
    private enum Section: Hashable {
        case tags
        case add
    }

    private enum Row: Hashable {
        case tag(Tag)
        case add(String)
    }

    private weak var tableView: UITableView!

    private static let addCellId = "AddCell"
    private static let tagCellId = "TagCell"
    private var dataSource: TableViewDiffableDataSource<Section, Row>!

    private let viewModel: ViewModel<TagPickerActionHandler>
    private let saveAction: ([Tag]) -> Void
    private let disposeBag: DisposeBag

    // MARK: - Lifecycle

    init(viewModel: ViewModel<TagPickerActionHandler>, saveAction: @escaping ([Tag]) -> Void) {
        self.viewModel = viewModel
        self.saveAction = saveAction
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupTableView()
        setupSearchBar()
        setupNavigationBar()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: disposeBag)

        if viewModel.state.tags.isEmpty {
            viewModel.process(action: .load)
        } else {
            updateTags(to: viewModel.state)
        }

        func setupTableView() {
            let tableView = UITableView(frame: .zero, style: .plain)
            tableView.backgroundColor = .systemBackground
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = UITableView.automaticDimension
            tableView.sectionHeaderHeight = 28
            tableView.sectionFooterHeight = 28
            tableView.delegate = self
            dataSource = TableViewDiffableDataSource<Section, Row>(tableView: tableView) { tableView, indexPath, row in
                switch row {
                case .tag(let tag):
                    let cell = tableView.dequeueReusableCell(withIdentifier: Self.tagCellId, for: indexPath)
                    if let cell = cell as? TagPickerCell {
                        cell.setup(with: tag)
                    }
                    return cell

                case .add(let searchTerm):
                    let cell = tableView.dequeueReusableCell(withIdentifier: Self.addCellId, for: indexPath)
                    cell.textLabel?.text = L10n.TagPicker.createTag(searchTerm)
                    return cell
                }
            }
            dataSource.canEditRow = { [weak self] indexPath in
                guard let row = self?.dataSource.itemIdentifier(for: indexPath), case .tag = row else { return false }
                return true
            }
            tableView.allowsMultipleSelectionDuringEditing = true
            tableView.isEditing = true
            tableView.register(UINib(nibName: "TagPickerCell", bundle: nil), forCellReuseIdentifier: Self.tagCellId)
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.addCellId)
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)
            self.tableView = tableView

            NSLayoutConstraint.activate([
                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
                tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
            ])
        }

        func setupSearchBar() {
            let searchController = UISearchController()
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.hidesNavigationBarDuringPresentation = false
            searchController.searchBar.placeholder = L10n.TagPicker.placeholder
            searchController.searchBar.autocapitalizationType = .none

            searchController.searchBar.rx.text.observe(on: MainScheduler.instance)
                .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                .subscribe(onNext: { [weak self] text in
                    self?.viewModel.process(action: .search(text ?? ""))
                })
                .disposed(by: disposeBag)

            searchController.searchBar.rx.searchButtonClicked.observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] in
                    self?.addTagIfNeeded()
                })
                .disposed(by: disposeBag)

            navigationItem.searchController = searchController
            navigationItem.preferredSearchBarPlacement = .stacked
            navigationItem.hidesSearchBarWhenScrolling = false
        }

        func setupNavigationBar() {
            let cancelPrimaryAction = UIAction(title: L10n.cancel) { [weak self] _ in
                self?.dismiss()
            }
            let cancelItem: UIBarButtonItem
            if #available(iOS 26.0.0, *) {
                cancelItem = UIBarButtonItem(systemItem: .cancel, primaryAction: cancelPrimaryAction)
            } else {
                cancelItem = UIBarButtonItem(primaryAction: cancelPrimaryAction)
            }
            navigationItem.leftBarButtonItem = cancelItem

            let savePrimaryAction = UIAction(title: L10n.save) { [weak self] _ in
                guard let self else { return }
                save()
                dismiss()
            }
            let saveItem: UIBarButtonItem
            if #available(iOS 26.0.0, *) {
                saveItem = UIBarButtonItem(systemItem: .save, primaryAction: savePrimaryAction)
                saveItem.tintColor = Asset.Colors.zoteroBlue.color
                saveItem.style = .prominent
            } else {
                saveItem = UIBarButtonItem(primaryAction: savePrimaryAction)
                saveItem.style = .done
            }
            navigationItem.rightBarButtonItem = saveItem
        }
    }

    // MARK: - Actions

    private func update(to state: TagPickerState) {
        if state.changes.contains(.selection) {
            title = L10n.TagPicker.title(state.selectedTags.count)
        }

        if state.changes.contains(.tags) {
            updateTags(to: state)
        }

        if let error = state.error {
            // TODO: - show error
        }
    }

    private func updateTags(to state: TagPickerState) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.tags, .add])
        snapshot.appendItems(state.tags.map({ .tag($0) }), toSection: .tags)
        if state.showAddTagButton {
            snapshot.appendItems([.add(state.searchTerm)], toSection: .add)
        }

        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.selectTags(in: state)
        }
    }

    private func selectTags(in state: TagPickerState) {
        for name in state.selectedTags {
            guard let tag = state.tags.first(where: { $0.name == name }),
                  let indexPath = dataSource.indexPath(for: .tag(tag)) else { continue }
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: (state.addedTagName == name ? .middle : .none))
        }
    }

    private func addTagIfNeeded() {
        guard let searchController = navigationItem.searchController, !viewModel.state.searchTerm.isEmpty, let text = searchController.searchBar.text, !text.isEmpty else { return }
        viewModel.process(action: .add(text))
        searchController.searchBar.text = nil
        searchController.isActive = false
    }

    private func save() {
        let allTags = viewModel.state.snapshot ?? viewModel.state.tags
        let tags = viewModel.state.selectedTags.compactMap { id in
            allTags.first(where: { $0.id == id })
        }.sorted(by: { $0.name < $1.name })
        saveAction(tags)
    }

    private func dismiss() {
        guard let navigationController else {
            presentingViewController?.dismiss(animated: true, completion: nil)
            return
        }

        if navigationController.viewControllers.count == 1 {
            navigationController.dismiss(animated: true, completion: nil)
        } else {
            navigationController.popViewController(animated: true)
        }
    }
}

extension TagPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }

        switch row {
        case .add:
            addTagIfNeeded()

        case .tag(let tag):
            viewModel.process(action: .select(tag.name))
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let row = dataSource.itemIdentifier(for: indexPath), case .tag(let tag) = row else { return }
        viewModel.process(action: .deselect(tag.name))
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return true
    }
}
