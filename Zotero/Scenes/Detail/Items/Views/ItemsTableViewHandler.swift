//
//  ItemsTableViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
import RxCocoa
import RxSwift

protocol ItemsTableViewHandlerDelegate: class {
    var isInViewHierarchy: Bool { get }

    func process(action: ItemAction.Kind, for item: RItem)
}

final class ItemsTableViewHandler: NSObject {
    enum TapAction {
        case metadata(RItem)
        case doi(String)
    }

    private static let cellId = "ItemCell"
    private unowned let tableView: UITableView
    private unowned let viewModel: ViewModel<ItemsActionHandler>
    private unowned let delegate: ItemsTableViewHandlerDelegate
    private unowned let dragDropController: DragDropController
    let tapObserver: PublishSubject<TapAction>
    private let disposeBag: DisposeBag
    private let contextMenuActions: [ItemAction]
    private let leadingCellActions: [ItemAction]
    private let trailingCellActions: [ItemAction]

    private var snapshot: Results<RItem>?
    private var reloadAnimationsDisabled: Bool
    private weak var fileDownloader: FileDownloader?

    init(tableView: UITableView, viewModel: ViewModel<ItemsActionHandler>, delegate: ItemsTableViewHandlerDelegate, dragDropController: DragDropController, fileDownloader: FileDownloader?) {
        let (leadingActions, trailingActions) = ItemsTableViewHandler.createCellActions(for: viewModel.state)
        self.tableView = tableView
        self.viewModel = viewModel
        self.delegate = delegate
        self.dragDropController = dragDropController
        self.fileDownloader = fileDownloader
        self.leadingCellActions = leadingActions
        self.trailingCellActions = trailingActions
        self.contextMenuActions = ItemsTableViewHandler.createContextMenuActions(for: viewModel.state)
        self.reloadAnimationsDisabled = false
        self.tapObserver = PublishSubject()
        self.disposeBag = DisposeBag()

        super.init()

        self.setupTableView()
        self.setupKeyboardObserving()
    }

    private static func createContextMenuActions(for state: ItemsState) -> [ItemAction] {
        if state.type.isTrash {
            return [ItemAction(type: .restore), ItemAction(type: .delete)]
        }
        var actions = [ItemAction(type: .addToCollection), ItemAction(type: .duplicate), ItemAction(type: .trash)]
        if state.type.collectionKey != nil {
            actions.insert(ItemAction(type: .removeFromCollection), at: 1)
        }
        return actions
    }

    private static func createCellActions(for state: ItemsState) -> (leading: [ItemAction], trailing: [ItemAction]) {
        if state.type.isTrash {
            return ([], [ItemAction(type: .delete), ItemAction(type: .restore)])
        }
        var trailingActions: [ItemAction] = [ItemAction(type: .trash), ItemAction(type: .addToCollection)]
        if state.type.collectionKey != nil {
            trailingActions.insert(ItemAction(type: .removeFromCollection), at: 1)
        }
        return ([], trailingActions)
    }

    private func createContextMenu(for item: RItem) -> UIMenu {
        let actions: [UIAction] = self.contextMenuActions.map({ action in
            return UIAction(title: action.title, image: action.image, attributes: (action.isDestructive ? .destructive : [])) { [weak self] _ in
                self?.delegate.process(action: action.type, for: item)
            }
        })
        return UIMenu(title: "", children: actions)
    }

    private func createSwipeConfiguration(from itemActions: [ItemAction], at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !self.tableView.isEditing && self.viewModel.state.library.metadataEditable else { return nil }
        let actions = itemActions.map({ action -> UIContextualAction in
            let contextualAction = UIContextualAction(style: (action.isDestructive ? .destructive : .normal), title: action.title, handler: { [weak self] _, _, completion in
                guard let item = self?.snapshot?[indexPath.row] else { return }
                self?.delegate.process(action: action.type, for: item)
                completion(true)
            })
            contextualAction.image = action.image
            switch action.type {
            case .delete, .trash:
                contextualAction.backgroundColor = .systemRed
            case .duplicate, .restore:
                contextualAction.backgroundColor = .systemBlue
            case .addToCollection:
                contextualAction.backgroundColor = .systemOrange
            case .removeFromCollection:
                contextualAction.backgroundColor = .systemPurple
            }
            return contextualAction
        })
        return UISwipeActionsConfiguration(actions: actions)
    }

    // MARK: - Data source

    func sourceDataForCell(for key: String) -> (UIView, CGRect?) {
        let cell = self.tableView.visibleCells.first(where: { ($0 as? ItemCell)?.key == key })
        return (self.tableView, cell?.frame)
    }

    // MARK: - Actions

    /// Disables performing tableView batch reloads. Instead just uses `reloadData()`.
    func disableReloadAnimations() {
        self.reloadAnimationsDisabled = true
    }

    /// Enables performing tableView batch reloads.
    func enableReloadAnimations() {
        self.reloadAnimationsDisabled = false
    }

    func set(editing: Bool, animated: Bool) {
        self.tableView.setEditing(editing, animated: animated)
    }

    func updateCell(with attachment: Attachment?, parentKey: String) {
        guard let cell = self.tableView.visibleCells.first(where: { ($0 as? ItemCell)?.key == parentKey }) as? ItemCell else { return }

        if let attachment = attachment {
            let (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)
            cell.set(state: .stateFrom(contentType: attachment.contentType, progress: progress, error: error))
        } else {
            cell.clearAttachment()
        }
    }

    func reloadAll(snapshot: Results<RItem>) {
        self.snapshot = snapshot
        self.tableView.reloadData()
    }

    func reloadAllAttachments() {
        self.tableView.reloadData()
    }

    func reload(snapshot: Results<RItem>, modifications: [Int], insertions: [Int], deletions: [Int]) {
        if !self.delegate.isInViewHierarchy || self.reloadAnimationsDisabled {
            // If view controller is outside of view hierarchy, performing batch updates with animations will cause a crash (UITableViewAlertForLayoutOutsideViewHierarchy).
            // Simple reload will suffice, animations will not be seen anyway.
            self.snapshot = snapshot
            self.tableView.reloadData()
            return
        }

        self.tableView.performBatchUpdates({
            self.snapshot = snapshot
            self.tableView.deleteRows(at: deletions.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
            self.tableView.reloadRows(at: modifications.map({ IndexPath(row: $0, section: 0) }), with: .none)
            self.tableView.insertRows(at: insertions.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
        }, completion: { _ in
        })
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

    // MARK: - Setups

    private func setupTableView() {
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.dragDelegate = self
        self.tableView.dropDelegate = self
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 60
        self.tableView.allowsMultipleSelectionDuringEditing = true
        self.tableView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none

        self.tableView.register(UINib(nibName: "ItemCell", bundle: nil), forCellReuseIdentifier: ItemsTableViewHandler.cellId)
        self.tableView.tableFooterView = UIView()
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
        return self.snapshot?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ItemsTableViewHandler.cellId, for: indexPath)

        let count = self.snapshot?.count ?? 0
        if indexPath.row >= count {
            DDLogError("ItemsTableViewHandler: indexPath.row (\(indexPath.row)) out of bounds (\(count))")
            return cell
        }

        if let item = self.snapshot?[indexPath.row],
           let cell = cell as? ItemCell {
            // Create and cache attachment if needed
            self.viewModel.process(action: .cacheAttachment(item: item))

            let parentKey = item.key
            let attachment = self.viewModel.state.attachments[parentKey]
            let attachmentState: FileAttachmentView.State? = attachment.flatMap({ attachment in
                let (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)
                return .stateFrom(contentType: attachment.contentType, progress: progress, error: error)
            })

            cell.set(item: ItemCellModel(item: item, attachment: attachmentState), tapAction: { [weak self] in
                guard let key = attachment?.key else { return }
                self?.viewModel.process(action: .openAttachment(key: key, parentKey: parentKey))
            })
        }

        return cell
    }
}

extension ItemsTableViewHandler: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = self.snapshot?[indexPath.row] else { return }

        if self.viewModel.state.isEditing {
            self.viewModel.process(action: .selectItem(item.key))
        } else {
            tableView.deselectRow(at: indexPath, animated: true)

            if let attachment = self.viewModel.state.attachments[item.key] {
                self.viewModel.process(action: .openAttachment(key: attachment.key, parentKey: item.key))
            } else if let doi = item.doi {
                self.tapObserver.on(.next(.doi(doi)))
            } else {
                self.tapObserver.on(.next(.metadata(item)))
            }
        }
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard let item = self.snapshot?[indexPath.row] else { return }
        self.tapObserver.on(.next(.metadata(item)))
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if self.viewModel.state.isEditing,
           let item = self.snapshot?[indexPath.row] {
            self.viewModel.process(action: .deselectItem(item.key))
        }
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return tableView.isEditing
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !tableView.isEditing && self.viewModel.state.library.metadataEditable else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ -> UIMenu? in
            guard let item = self?.snapshot?[indexPath.row] else { return nil }
            return self?.createContextMenu(for: item)
        }
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return self.createSwipeConfiguration(from: self.leadingCellActions, at: indexPath)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return self.createSwipeConfiguration(from: self.trailingCellActions, at: indexPath)
    }
}

extension ItemsTableViewHandler: UITableViewDragDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let item = self.snapshot?[indexPath.row] else { return [] }
        return [self.dragDropController.dragItem(from: item)]
    }
}

extension ItemsTableViewHandler: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath,
              let key = self.snapshot?[indexPath.row].key else { return }

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
        guard self.viewModel.state.library.metadataEditable,    // allow only when library is editable
              session.localDragSession != nil,                  // allow only local drag session
              let destinationIndexPath = destinationIndexPath,
              let results = self.snapshot,
              destinationIndexPath.row < results.count  else {
            return UITableViewDropProposal(operation: .forbidden)
        }

        let item = results[destinationIndexPath.row]
        if item.rawType == ItemTypes.note || item.rawType == ItemTypes.attachment ||        // allow dropping only to non-standalone items
           session.items.compactMap({ self.dragDropController.item(from: $0) })             // allow drops of only standalone items
                        .contains(where: { $0.rawType != ItemTypes.attachment && $0.rawType != ItemTypes.note }) {
           return UITableViewDropProposal(operation: .forbidden)
        }

        return UITableViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
    }
}
