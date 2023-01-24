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
    @IBOutlet private weak var tableView: UITableView!

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
        self.disposeBag = DisposeBag()
        super.init(nibName: "TagPickerViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupTableView()
        self.setupSearchBar()
        self.setupNavigationBar()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)

        if self.viewModel.state.tags.isEmpty {
            self.viewModel.process(action: .load)
        } else {
            self.tableView.reloadData()
            self.select(selected: self.viewModel.state.selectedTags, tags: self.viewModel.state.tags, focusTagName: self.viewModel.state.addedTagName)
        }
    }

    // MARK: - Actions

    private func update(to state: TagPickerState) {
        self.title = L10n.TagPicker.title(state.selectedTags.count)

        if state.changes.contains(.tags) {
            self.tableView.reloadData()
            self.select(selected: state.selectedTags, tags: state.tags, focusTagName: state.addedTagName)
        }

        if let error = state.error {
            // TODO: - show error
        }
    }

    private func select(selected: Set<String>, tags: [Tag], focusTagName: String?) {
        for name in selected {
            guard let index = tags.firstIndex(where: { $0.name == name }) else { continue }
            self.tableView.selectRow(at: IndexPath(row: index, section: TagPickerViewController.tagsSection), animated: false, scrollPosition: (focusTagName == name ? .middle: .none))
        }
    }

    private func addTagIfNeeded() {
        // When there are no search results during search, add current search query
        guard let searchController = self.navigationItem.searchController,
              !self.viewModel.state.searchTerm.isEmpty,
              let text = searchController.searchBar.text, !text.isEmpty else { return }
        self.viewModel.process(action: .add(text))
        searchController.searchBar.text = nil
        searchController.isActive = false
    }

    private func save() {
        let allTags = self.viewModel.state.snapshot ?? self.viewModel.state.tags
        let tags = self.viewModel.state.selectedTags.compactMap { id in
            allTags.first(where: { $0.id == id })
        }.sorted(by: { $0.name < $1.name })
        self.saveAction(tags)
    }

    private func dismiss() {
        guard let navigationController = self.navigationController else {
            self.presentingViewController?.dismiss(animated: true, completion: nil)
            return
        }

        if navigationController.viewControllers.count == 1 {
            navigationController.dismiss(animated: true, completion: nil)
        } else {
            navigationController.popViewController(animated: true)
        }
    }

    // MARK: - Setups

    private func setupSearchBar() {
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
                         .disposed(by: self.disposeBag)

        searchController.searchBar.rx.searchButtonClicked.observe(on: MainScheduler.instance)
                        .subscribe(onNext: { [weak self] in
                            self?.addTagIfNeeded()
                        })
                        .disposed(by: self.disposeBag)

        self.navigationItem.searchController = searchController
        self.navigationItem.hidesSearchBarWhenScrolling = false
    }

    private func setupTableView() {
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.allowsMultipleSelectionDuringEditing = true
        self.tableView.isEditing = true
        self.tableView.register(UINib(nibName: "TagPickerCell", bundle: nil), forCellReuseIdentifier: TagPickerViewController.tagCellId)
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: TagPickerViewController.addCellId)
    }

    private func setupNavigationBar() {
        let left = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        left.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.dismiss()
            })
            .disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = left

        let right = UIBarButtonItem(title: L10n.save, style: .plain, target: nil, action: nil)
        right.rx.tap
             .subscribe(onNext: { [weak self] in
                 self?.save()
                 self?.dismiss()
             })
             .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = right
    }
}

extension TagPickerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case TagPickerViewController.addSection: return self.viewModel.state.showAddTagButton ? 1 : 0
        case TagPickerViewController.tagsSection: return self.viewModel.state.tags.count
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellId = indexPath.section == TagPickerViewController.tagsSection ? TagPickerViewController.tagCellId : TagPickerViewController.addCellId
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
        if let cell = cell as? TagPickerCell {
            let tag = self.viewModel.state.tags[indexPath.row]
            cell.setup(with: tag)
        } else {
            cell.textLabel?.text = L10n.TagPicker.createTag(self.viewModel.state.searchTerm)
        }
        return cell
    }
}

extension TagPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case TagPickerViewController.addSection:
            self.addTagIfNeeded()

        case TagPickerViewController.tagsSection:
            let name = self.viewModel.state.tags[indexPath.row].name
            self.viewModel.process(action: .select(name))

        default: break
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let name = self.viewModel.state.tags[indexPath.row].name
        self.viewModel.process(action: .deselect(name))
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == TagPickerViewController.tagsSection
    }
}
