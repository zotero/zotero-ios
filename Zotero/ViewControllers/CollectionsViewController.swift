//
//  CollectionsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class CollectionsViewController: UIViewController, ProgressToolbarController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private static let defaultIndexPath: IndexPath = IndexPath(row: 0, section: 0)
    private let store: CollectionsStore
    private let disposeBag: DisposeBag
    // Variables
    weak var toolbarTitleLabel: UILabel?
    weak var toolbarSubtitleLabel: UILabel?
    private weak var navigationDelegate: ItemNavigationDelegate?

    // MARK: - Lifecycle

    init(store: CollectionsStore, delegate: ItemNavigationDelegate?) {
        self.store = store
        self.navigationDelegate = delegate
        self.disposeBag = DisposeBag()
        super.init(nibName: "CollectionsViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = self.store.state.value.title
        self.setupTableView()
        self.setupNavbar()

        self.store.state.asObservable()
                        .observeOn(MainScheduler.instance)
                        .subscribe(onNext: { [weak self] state in
                            self?.process(state: state)
                        })
                        .disposed(by: self.disposeBag)

        self.store.handle(action: .load)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if self.tableView.indexPathForSelectedRow == nil {
            self.tableView.selectRow(at: CollectionsViewController.defaultIndexPath,
                                     animated: false, scrollPosition: .none)
        }
    }

    // MARK: - Actions

    private func process(state: CollectionsStore.StoreState) {
        if state.changes.contains(.data) {
            let selectedIndexPath = self.tableView.indexPathForSelectedRow
            self.tableView.reloadData()
            if let indexPath = selectedIndexPath {
                self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        }

        if state.changes.contains(.editing) {
            if let collection = state.collectionToEdit {
                do {
                    let state = try CollectionEditStore.StoreState(collection: collection)
                    let store = CollectionEditStore(initialState: state, dbStorage: self.store.dbStorage)
                    let controller = CollectionEditorViewController(store: store)
                    self.present(controller: controller)
                } catch let error as CollectionEditStore.StoreError where error == .collectionNotStoredInLibrary {
                    // TODO: - Show collection not in library error
                } catch let error {
                    // TODO: - Show general error
                }
            }

            // TODO: - Add search editing
        }

        if let error = state.error {
            // TODO: - show some error
        }
    }

    private func addCollection() {
        let libraryId = self.store.state.value.libraryId
        let state = CollectionEditStore.StoreState(libraryId: libraryId, libraryName: self.store.state.value.title)
        let store = CollectionEditStore(initialState: state, dbStorage: self.store.dbStorage)
        let controller = CollectionEditorViewController(store: store)
        self.present(controller: controller)
    }

    private func edit(at indexPath: IndexPath) {
        let section = self.store.state.value.sections[indexPath.section]
        switch section {
        case .collections:
            self.store.handle(action: .editCollection(indexPath.row))
        case .searches:
            self.store.handle(action: .editSearch(indexPath.row))
        default:
            return
        }
    }

    private func delete(at indexPath: IndexPath, cell: UITableViewCell) {
        let controller = UIAlertController(title: "Are you sure?", message: nil, preferredStyle: .actionSheet)

        controller.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { [weak self] _ in
            guard let `self` = self else { return }
            let section = self.store.state.value.sections[indexPath.section]
            switch section {
            case .collections:
                self.store.handle(action: .deleteCollection(indexPath.row))
            case .searches:
                self.store.handle(action: .deleteSearch(indexPath.row))
            default: break
            }
        }))

        controller.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))

        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.sourceView = cell
        controller.popoverPresentationController?.sourceRect = cell.bounds
        self.present(controller, animated: true, completion: nil)
    }

    private func present(controller: UIViewController) {
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .currentContext
        self.present(navigationController, animated: true, completion: nil)
    }

    @objc private func showOptions() {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem

        controller.addAction(UIAlertAction(title: "New Collection", style: .default, handler: { [weak self] _ in
            self?.addCollection()
        }))
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        self.present(controller, animated: true, completion: nil)
    }

    private func data(for section: Int) -> [CollectionCellData] {
        guard section < self.store.state.value.sections.count else { return [] }
        switch self.store.state.value.sections[section] {
        case .allItems:
            return self.store.state.value.allItemsCellData
        case .collections:
            return self.store.state.value.collectionCellData
        case .searches:
            return self.store.state.value.searchCellData
        case .custom:
            return self.store.state.value.customCellData
        }
    }

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.register(UINib(nibName: CollectionCell.nibName, bundle: nil), forCellReuseIdentifier: "Cell")
        self.tableView.dataSource = self
        self.tableView.delegate = self
    }

    private func setupNavbar() {
        guard self.store.state.value.metadataEditable else { return }
        let options = UIBarButtonItem(image: UIImage(named: "navbar_options"), style: .plain, target: self,
                                      action: #selector(CollectionsViewController.showOptions))
        self.navigationItem.rightBarButtonItem = options
    }
}

extension CollectionsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.store.state.value.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.data(for: section).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        guard let collectionCell = cell as? CollectionCell else { return cell }

        let data = self.data(for: indexPath.section)
        if indexPath.row < data.count {
            collectionCell.setup(with: data[indexPath.row])
        }

        return cell
    }

    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard self.store.state.value.metadataEditable else { return [] }

        switch self.data(for: indexPath.section)[indexPath.row].type {
        // Don't add cell actions for custom types (all items, my publications, ...)
        case .custom: return []
        default: break
        }

        let editAction = UITableViewRowAction(style: .normal, title: "Edit") { [weak self] _, indexPath in
            self?.edit(at: indexPath)
        }
        let deleteAction = UITableViewRowAction(style: .destructive,
                                                title: "Delete") { [weak self, weak tableView] _, indexPath in
            if let cell = tableView?.cellForRow(at: indexPath) {
                self?.delete(at: indexPath, cell: cell)
            }
        }

        return [editAction, deleteAction]
    }
}

extension CollectionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if UIDevice.current.userInterfaceIdiom == .phone {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        let state = self.store.state.value
        let data = self.data(for: indexPath.section)[indexPath.row]

        switch data.type {
        case .collection:
            self.navigationDelegate?.showCollectionItems(libraryId: state.libraryId,
                                                         collectionData: (data.key, data.name),
                                                         metadataEditable: state.metadataEditable,
                                                         filesEditable: state.filesEditable)
        case .search:
            self.navigationDelegate?.showSearchItems(libraryId: state.libraryId,
                                                     searchData: (data.key, data.name),
                                                     metadataEditable: state.metadataEditable,
                                                     filesEditable: state.filesEditable)
        case .custom(let type):
            switch type {
            case .all:
                self.navigationDelegate?.showAllItems(for: state.libraryId,
                                                      metadataEditable: state.metadataEditable,
                                                      filesEditable: state.filesEditable)
            case .trash:
                self.navigationDelegate?.showTrashItems(for: state.libraryId,
                                                        metadataEditable: state.metadataEditable,
                                                        filesEditable: state.filesEditable)
            case .publications:
                self.navigationDelegate?.showPublications(for: state.libraryId,
                                                          metadataEditable: state.metadataEditable,
                                                          filesEditable: state.filesEditable)
            }
        }
    }
}

extension CollectionCellData: CollectionCellModel {
    var icon: UIImage? {
        let name: String
        switch self.type {
        case .collection(let hasChildren):
            name = "icon_cell_collection" + (hasChildren ? "s" : "")
        case .search:
            name = "icon_cell_document"
        case .custom(let type):
            switch type {
            case .all, .publications:
                name = "icon_cell_document"
            case .trash:
                name = "icon_cell_trash"
            }
        }

        return UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
    }
}
