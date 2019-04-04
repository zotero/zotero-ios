//
//  CollectionEditorViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 18/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class CollectionEditorViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: CollectionEditStore
    private let defaultParent: LibraryModel
    private let disposeBag: DisposeBag

    init(store: CollectionEditStore) {
        self.store = store
        self.defaultParent = LibraryModel(name: store.state.value.libraryName)
        self.disposeBag = DisposeBag()
        super.init(nibName: "CollectionEditorViewController", bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Edit Collection"
        self.setupNavigationBar()
        self.setupTableView()

        self.store.state.observeOn(MainScheduler.instance)
                        .subscribe(onNext: { [weak self] state in
                            self?.process(state: state)
                        })
                        .disposed(by: self.disposeBag)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.focusName()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.view.endEditing(true)
    }

    // MARK: - Actions

    private func process(state: CollectionEditStore.StoreState) {
        if state.didSave {
            self.presentingViewController?.dismiss(animated: true, completion: nil)
            return
        }

        if state.changes.contains(.parent) {
            self.reloadParent()
        }

        if let error = state.error {
            if !self.tableView.isUserInteractionEnabled {
                self.tableView.isUserInteractionEnabled = true
                self.navigationItem.rightBarButtonItem?.isEnabled = true
            }

            switch error {
            case .invalidName:
                self.focusName(scrollToVisibility: true)
            case .saveFailed, .collectionNotStoredInLibrary: break
            }
            // TODO: - Show error
        }
    }

    @objc private func save() {
        self.store.handle(action: .save)
        self.tableView.isUserInteractionEnabled = false
        self.navigationItem.rightBarButtonItem?.isEnabled = false
    }

    @objc private func cancel() {
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    private func showParentPicker() {
        guard let section = self.store.state.value.sections.firstIndex(of: .parent) else { return }
        let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: section))
        let state = CollectionPickerStore.StoreState(libraryId: self.store.state.value.libraryId,
                                                     excludedKey: self.store.state.value.key)
        let store = CollectionPickerStore(initialState: state, dbStorage: self.store.dbStorage)

        let controller = CollectionPickerViewController(store: store)
        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.sourceView = cell
        controller.popoverPresentationController?.sourceRect = cell?.bounds ?? CGRect()
        self.present(controller, animated: true, completion: nil)

        store.state.observeOn(MainScheduler.instance)
                   .subscribe(onNext: { [weak self] state in
                       if state.changes.contains(.pickedCollection),
                          let data = state.pickedData {
                           self?.store.handle(action: .changeParent(data))
                           self?.dismiss(animated: true, completion: nil)
                       }
                   })
                   .disposed(by: self.disposeBag)
    }

    private func delete() {
        guard let section = self.store.state.value.sections.firstIndex(of: .actions) else { return }
        let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: section))

        let controller = UIAlertController(title: "Are you sure?", message: nil, preferredStyle: .actionSheet)
        controller.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { [weak self] _ in
            self?.store.handle(action: .delete)
        }))
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.sourceView = cell
        controller.popoverPresentationController?.sourceRect = cell?.bounds ?? CGRect()
        self.present(controller, animated: true, completion: nil)
    }

    private func reloadParent() {
        guard let section = self.store.state.value.sections.firstIndex(of: .parent) else { return }
        self.tableView.reloadRows(at: [IndexPath(row: 0, section: section)], with: .none)
    }

    private func focusName(scrollToVisibility: Bool = false) {
        guard let section = self.store.state.value.sections.firstIndex(of: .name) else { return }
        let indexPath = IndexPath(row: 0, section: section)
        guard let cell = self.tableView.cellForRow(at: indexPath) as? TextFieldCell else { return }

        cell.focusTextField()
        if scrollToVisibility {
            self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        }
    }

    private func cellId(for section: CollectionEditStore.StoreState.Section) -> String {
        switch section {
        case .actions:
            return "ActionCell"
        case .name:
            return TextFieldCell.nibName
        case .parent:
            return CollectionCell.nibName
        }
    }

    // MARK: - Setups

    private func setupNavigationBar() {
        let cancel = UIBarButtonItem(title: "Cancel", style: .plain, target: self,
                                     action: #selector(CollectionEditorViewController.cancel))
        self.navigationItem.leftBarButtonItem = cancel
        let save = UIBarButtonItem(title: "Save", style: .done, target: self,
                                   action: #selector(CollectionEditorViewController.save))
        self.navigationItem.rightBarButtonItem = save
    }

    private func setupTableView() {
        self.tableView.register(UINib(nibName: TextFieldCell.nibName, bundle: nil),
                                forCellReuseIdentifier: self.cellId(for: .name))
        self.tableView.register(UINib(nibName: CollectionCell.nibName, bundle: nil),
                                forCellReuseIdentifier: self.cellId(for: .parent))
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: self.cellId(for: .actions))
        self.tableView.dataSource = self
        self.tableView.delegate = self
    }
}

extension CollectionEditorViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.store.state.value.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch self.store.state.value.sections[section] {
        case .parent:
            return "PARENT COLLECTION"
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = self.store.state.value.sections[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: self.cellId(for: section), for: indexPath)

        if let cell = cell as? CollectionCell {
            cell.setup(with: (self.store.state.value.parent ?? self.defaultParent))
        } else if let cell = cell as? TextFieldCell {
            cell.setup(with: self.store.state.value.name, placeholder: "Collection name") { [weak self] newName in
                self?.store.handle(action: .changeName(newName))
            }
        } else {
            cell.textLabel?.text = "Delete Collection"
            cell.textLabel?.textColor = .red
            cell.textLabel?.textAlignment = .center
        }

        return cell
    }
}

extension CollectionEditorViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = self.store.state.value.sections[indexPath.section]
        tableView.deselectRow(at: indexPath, animated: (section != .name))

        switch section {
        case .parent:
            self.showParentPicker()
        case .actions:
            if indexPath.row == 0 {
                self.delete()
            }
        default: break
        }
    }
}

extension CollectionEditStore.StoreState.Parent: CollectionCellModel {
    var level: Int {
        return 0
    }

    var icon: UIImage? {
        return UIImage(named: "icon_cell_collection")?.withRenderingMode(.alwaysTemplate)
    }
}

struct LibraryModel: CollectionCellModel {
    let name: String

    var level: Int {
        return 0
    }

    var icon: UIImage? {
        return UIImage(named: "icon_cell_library")?.withRenderingMode(.alwaysTemplate)
    }
}
