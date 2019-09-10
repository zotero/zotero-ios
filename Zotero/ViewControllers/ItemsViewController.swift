//
//  ItemsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

import CocoaLumberjack
import RxSwift
import RealmSwift

class ItemsViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var tableView: UITableView!
    // Constants
    private let store: ItemsStore
    private let disposeBag: DisposeBag

    // MARK: - Lifecycle

    init(store: ItemsStore) {
        self.store = store
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemsViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if UIDevice.current.userInterfaceIdiom == .phone {
            self.navigationItem.title = self.store.state.value.title
        }
        self.navigationItem.leftBarButtonItem = self.splitViewController?.displayModeButtonItem
        self.navigationItem.leftItemsSupplementBackButton = true
        self.setupTableView()
        self.setupNavbar()

        self.store.state.asObservable()
                        .observeOn(MainScheduler.instance)
                        .subscribe(onNext: { [weak self] state in
                            self?.tableView.reloadData()
                        })
                        .disposed(by: self.disposeBag)

        self.store.handle(action: .load)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.splitViewController?.presentsWithGesture = true
    }

    // MARK: - Actions

    private func addItem() {
        let libraryId = self.store.state.value.libraryId
        let collectionKey = self.store.state.value.type.collectionKey
        let filesEditable = self.store.state.value.filesEditable
        self.showItemDetail(with: .creation(libraryId: libraryId,
                                            collectionKey: collectionKey,
                                            filesEditable: filesEditable))
    }

    @objc private func showOptions() {
        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem

        controller.addAction(UIAlertAction(title: "New Item", style: .default, handler: { [weak self] _ in
            self?.addItem()
        }))
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        self.present(controller, animated: true, completion: nil)
    }

    private func showItem(at indexPath: IndexPath) {
        guard let items = self.store.state.value.dataSource?.items(for: indexPath.section),
              indexPath.row < items.count else { return }
        let item = items[indexPath.row]
        self.showItemDetail(with: .preview(item))
    }

    private func showItemDetail(with type: ItemDetailStore.StoreState.DetailType) {
        do {
            let userId = try self.store.dbStorage.createCoordinator().perform(request: ReadUserDbRequest()).identifier
            let libraryId = self.store.state.value.libraryId
            let store = try ItemDetailStore(type: type,
                                               userId: userId,
                                               libraryId: libraryId,
                                               apiClient: self.store.apiClient,
                                               fileStorage: self.store.fileStorage,
                                               dbStorage: self.store.dbStorage,
                                               schemaController: self.store.schemaController)
            let controller = UIHostingController(rootView: ItemDetailView(store: store))
            self.navigationController?.pushViewController(controller, animated: true)
        } catch let error {
            DDLogError("ItemsViewController: could not create ItemDewtailStore: \(error)")
            // TODO: - Show error message
        }
    }

    private func deleteItem(at indexPath: IndexPath, cell: UITableViewCell) {
        let controller = UIAlertController(title: "Are you sure?", message: nil, preferredStyle: .actionSheet)

        controller.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { [weak self] _ in
            guard let `self` = self else { return }
            switch self.store.state.value.type {
            case .trash:
                self.store.handle(action: .delete(indexPath))
            default:
                self.store.handle(action: .trash(indexPath))
            }
        }))

        controller.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))

        controller.modalPresentationStyle = .popover
        controller.popoverPresentationController?.sourceView = cell
        controller.popoverPresentationController?.sourceRect = cell.bounds
        self.present(controller, animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupNavbar() {
        guard self.store.state.value.metadataEditable else { return }

        let options = UIBarButtonItem(image: UIImage(named: "navbar_options"), style: .plain, target: self,
                                      action: #selector(ItemsViewController.showOptions))
        self.navigationItem.rightBarButtonItem = options
    }

    private func setupTableView() {
        self.tableView.register(UINib(nibName: ItemCell.nibName, bundle: nil), forCellReuseIdentifier: "Cell")
        self.tableView.dataSource = self
        self.tableView.delegate = self
    }
}

extension ItemsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.store.state.value.dataSource?.sectionCount ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.store.state.value.dataSource?.items(for: section)?.count ?? 0
    }

    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return self.store.state.value.dataSource?.sectionIndexTitles
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return ItemCell.height
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        guard let itemCell = cell as? ItemCell,
              let items = self.store.state.value.dataSource?.items(for: indexPath.section) else { return cell }

        itemCell.setup(with: items[indexPath.row])

        return cell
    }

    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard self.store.state.value.metadataEditable else { return [] }

        let isTrash = self.store.state.value.type.isTrash
        let deleteTitle = isTrash ? "Delete" : "Trash"

        let deleteAction = UITableViewRowAction(style: .destructive,
                                                title: deleteTitle) { [weak self, weak tableView] _, indexPath in
            if let cell = tableView?.cellForRow(at: indexPath) {
                self?.deleteItem(at: indexPath, cell: cell)
            }
        }

        if !isTrash {
            return [deleteAction]
        }

        let restoreAction = UITableViewRowAction(style: .normal, title: "Restore") { [weak self] _, indexPath in
            self?.store.handle(action: .restore(indexPath))
        }

        return [restoreAction, deleteAction]
    }
}

extension ItemsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.showItem(at: indexPath)
    }
}

extension RItem: ItemCellModel {
    var creator: String? {
        return self.creatorSummary.isEmpty ? nil : self.creatorSummary
    }

    var date: String? {
        return self.parsedDate.isEmpty ? nil : self.parsedDate
    }

    var hasAttachment: Bool {
        return self.children.filter(Predicates.items(type: ItemTypes.attachment, notSyncState: .dirty)).count > 0
    }

    var hasNote: Bool {
        return self.children.filter(Predicates.items(type: ItemTypes.note, notSyncState: .dirty)).count > 0
    }

    var tagColors: [UIColor] {
        return self.tags.compactMap({ $0.uiColor })
    }

    var icon: UIImage? {
        let name: String
        switch self.rawType {
        case "artwork":
            name = "icon_item_type_artwork"
        case "attachment":
            name = "icon_item_type_attachment"
        case "audioRecording":
            name = "icon_item_type_audio-recording"
        case "book":
            name = "icon_item_type_book"
        case "bookSection":
            name = "icon_item_type_book-section"
        case "bill":
            name = "icon_item_type_bill"
        case "blogPost":
            name = "icon_item_type_blog-post"
        case "case":
            name = "icon_item_type_case"
        case "computerProgram":
            name = "icon_item_type_computer-program"
        case "conferencePaper":
            name = "icon_item_type_conference-paper"
        case "dictionaryEntry":
            name = "icon_item_type_dictionary-entry"
        case "document":
            name = "icon_item_type_document"
        case "email":
            name = "icon_item_type_e-mail"
        case "encyclopediaArticle":
            name = "icon_item_type_encyclopedia-article"
        case "film":
            name = "icon_item_type_film"
        case "forumPost":
            name = "icon_item_type_forum-post"
        case "hearing":
            name = "icon_item_type_hearing"
        case "instantMessage":
            name = "icon_item_type_instant-message"
        case "interview":
            name = "icon_item_type_interview"
        case "journalArticle":
            name = "icon_item_type_journal-article"
        case "letter":
            name = "icon_item_type_letter"
        case "magazineArticle":
            name = "icon_item_type_magazine-article"
        case "map":
            name = "icon_item_type_map"
        case "manuscript":
            name = "icon_item_type_manuscript"
        case "note":
            name = "icon_item_type_note"
        case "newspaperArticle":
            name = "icon_item_type_newspaper-article"
        case "patent":
            name = "icon_item_type_patent"
        case "podcast":
            name = "icon_item_type_podcast"
        case "presentation":
            name = "icon_item_type_presentation"
        case "radioBroadcast":
            name = "icon_item_type_radio-broadcast"
        case "report":
            name = "icon_item_type_report"
        case "statute":
            name = "icon_item_type_statute"
        case "thesis":
            name = "icon_item_type_thesis"
        case "tvBroadcast":
            name = "icon_item_type_tv-broadcast"
        case "videoRecording":
            name = "icon_item_type_video-recording"
        case "webpage":
            name = "icon_item_type_web-page"
        default:
            name = "icon_item_type_unknown"
        }
        return UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
    }
}
