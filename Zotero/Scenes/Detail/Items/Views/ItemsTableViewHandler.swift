//
//  ItemsTableViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemsTableViewHandler: NSObject {
    private static let cellId = "ItemCell"
    private unowned let tableView: UITableView
    private unowned let viewModel: ViewModel<ItemsActionHandler>
    private unowned let dragDropController: DragDropController
    let tapObserver: PublishSubject<RItem>
    private let disposeBag: DisposeBag

    private weak var fileDownloader: FileDownloader?
    private weak var coordinatorDelegate: DetailItemsCoordinatorDelegate?
    private var canReload: Bool
    private var hasPendingReloads: Bool

    init(tableView: UITableView, viewModel: ViewModel<ItemsActionHandler>, dragDropController: DragDropController, fileDownloader: FileDownloader?) {
        self.tableView = tableView
        self.viewModel = viewModel
        self.dragDropController = dragDropController
        self.fileDownloader = fileDownloader
        self.tapObserver = PublishSubject()
        self.disposeBag = DisposeBag()
        self.canReload = true
        self.hasPendingReloads = false

        super.init()

        self.setupTableView()
        self.setupKeyboardObserving()
    }
    
    func pauseReloading() {
        self.canReload = false
    }
    
    func resumeReloading() {
        self.canReload = true
        
        if self.hasPendingReloads {
            self.tableView.reloadData()
            self.hasPendingReloads = false
        }
    }

    func set(editing: Bool, animated: Bool) {
        self.tableView.setEditing(editing, animated: animated)
    }

    func updateCell(with attachment: Attachment?, parentKey: String) {
        guard let cell = self.tableView.visibleCells.first(where: { ($0 as? ItemCell)?.key == parentKey }) as? ItemCell else { return }

        if let attachment = attachment {
            let (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)
            cell.set(contentType: attachment.contentType, progress: progress, error: error)
        } else {
            cell.clearAttachment()
        }
    }

    func reload() {
        self.tableView.reloadData()
    }

    func reload(modifications: [Int], insertions: [Int], deletions: [Int]) {
        guard self.canReload else {
            self.hasPendingReloads = true
            return
        }

        self.tableView.performBatchUpdates({
            self.tableView.deleteRows(at: deletions.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
            self.tableView.reloadRows(at: modifications.map({ IndexPath(row: $0, section: 0) }), with: .none)
            self.tableView.insertRows(at: insertions.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
        }, completion: nil)
    }

    func selectAll() {
        let rows = self.tableView(self.tableView, numberOfRowsInSection: 0)
        (0..<rows).forEach { row in
            self.tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
        }
    }

    func deselectAll() {
        self.tableView.indexPathsForSelectedRows?.forEach({ indexPath in
            self.tableView.deselectRow(at: indexPath, animated: false)
        })
    }

    func sourceDataForCell(for key: String) -> (UIView, CGRect?) {
        let cell = self.tableView.visibleCells.first(where: { ($0 as? ItemCell)?.key == key })
        return (self.tableView, cell?.frame)
    }

    private func setupTableView() {
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.dragDelegate = self
        self.tableView.dropDelegate = self
        self.tableView.rowHeight = 58
        self.tableView.allowsMultipleSelectionDuringEditing = true
        self.tableView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none

        self.tableView.register(UINib(nibName: "ItemCell", bundle: nil), forCellReuseIdentifier: ItemsTableViewHandler.cellId)
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

extension ItemsTableViewHandler: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.viewModel.state.results?.count ?? 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ItemsTableViewHandler.cellId, for: indexPath)

        if let item = self.viewModel.state.results?[indexPath.row],
           let cell = cell as? ItemCell {
            // Create and cache attachment if needed
            self.viewModel.process(action: .cacheAttachment(item: item))

            let parentKey = item.key
            let attachment = self.viewModel.state.attachments[parentKey]
            let attachmentData: ItemCellAttachmentData? = attachment.flatMap({ attachment in
                let (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)
                return (attachment.contentType, progress, error)
            })

            cell.set(item: ItemCellModel(item: item, attachment: attachmentData), tapAction: { [weak self] in
                guard let key = attachment?.key else { return }
                self?.viewModel.process(action: .openAttachment(key: key, parentKey: parentKey))
            })
        }

        return cell
    }
}

extension ItemsTableViewHandler: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = self.viewModel.state.results?[indexPath.row] else { return }

        if self.viewModel.state.isEditing {
            self.viewModel.process(action: .selectItem(item.key))
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
            self.tapObserver.on(.next(item))
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if self.viewModel.state.isEditing,
           let item = self.viewModel.state.results?[indexPath.row] {
            self.viewModel.process(action: .deselectItem(item.key))
        }
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return tableView.isEditing
    }
}

extension ItemsTableViewHandler: UITableViewDragDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let item = self.viewModel.state.results?[indexPath.row] else { return [] }
        return [self.dragDropController.dragItem(from: item)]
    }
}

extension ItemsTableViewHandler: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath,
              let key = self.viewModel.state.results?[indexPath.row].key else { return }

        switch coordinator.proposal.operation {
        case .move:
            self.dragDropController.itemKeys(from: coordinator.items) { [weak self] keys in
                self?.viewModel.process(action: .moveItems(keys, key))
            }
        default: break
        }
    }

    func tableView(_ tableView: UITableView,
                   dropSessionDidUpdate session: UIDropSession,
                   withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        if !self.viewModel.state.library.metadataEditable {
            return UITableViewDropProposal(operation: .forbidden)
        }

        // Allow only local drag session
        guard session.localDragSession != nil else {
            return UITableViewDropProposal(operation: .forbidden)
        }

        // Allow dropping only to non-standalone items
        if let item = destinationIndexPath.flatMap({ self.viewModel.state.results?[$0.row] }),
           (item.rawType == ItemTypes.note || item.rawType == ItemTypes.attachment) {
           return UITableViewDropProposal(operation: .forbidden)
        }

        // Allow drops of only standalone items
        if session.items.compactMap({ self.dragDropController.item(from: $0) })
                        .contains(where: { $0.rawType != ItemTypes.attachment && $0.rawType != ItemTypes.note }) {
            return UITableViewDropProposal(operation: .forbidden)
        }

        return UITableViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
    }
}
