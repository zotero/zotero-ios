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
    private weak var tableView: UITableView!

    private static let addCellId = "AddCell"
    private static let tagCellId = "TagCell"
    private static let addSection = 1
    private static let tagsSection = 0
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
            tableView.dataSource = self
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
            let left = UIBarButtonItem(title: L10n.cancel)
            left.rx.tap
                .subscribe(onNext: { [weak self] in
                    self?.dismiss()
                })
                .disposed(by: disposeBag)
            navigationItem.leftBarButtonItem = left

            let right = UIBarButtonItem(title: L10n.save)
            right.rx.tap
                 .subscribe(onNext: { [weak self] in
                     guard let self else { return }
                     save()
                     dismiss()
                 })
                 .disposed(by: disposeBag)
            navigationItem.rightBarButtonItem = right
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
        tableView.reloadData()
        for name in state.selectedTags {
            guard let index = state.tags.firstIndex(where: { $0.name == name }) else { continue }
            tableView.selectRow(at: IndexPath(row: index, section: Self.tagsSection), animated: false, scrollPosition: (state.addedTagName == name ? .middle : .none))
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

extension TagPickerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case Self.addSection:
            return viewModel.state.showAddTagButton ? 1 : 0

        case Self.tagsSection:
            return viewModel.state.tags.count

        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellId = indexPath.section == Self.tagsSection ? Self.tagCellId : Self.addCellId
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
        if let cell = cell as? TagPickerCell {
            let tag = viewModel.state.tags[indexPath.row]
            cell.setup(with: tag)
        } else {
            cell.textLabel?.text = L10n.TagPicker.createTag(viewModel.state.searchTerm)
        }
        return cell
    }
}

extension TagPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case Self.addSection:
            addTagIfNeeded()

        case Self.tagsSection:
            let name = viewModel.state.tags[indexPath.row].name
            viewModel.process(action: .select(name))

        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let name = viewModel.state.tags[indexPath.row].name
        viewModel.process(action: .deselect(name))
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == Self.tagsSection
    }
}
