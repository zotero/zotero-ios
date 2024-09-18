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
import RxSwift

protocol ItemsTableViewHandlerDelegate: AnyObject {
    var isInViewHierarchy: Bool { get }
    var library: Library { get }
    var isEditing: Bool { get }
    var selectedItems: Set<String> { get }
    var isTrash: Bool { get }
    var collectionKey: String? { get }

    func model(for item: RItem) -> ItemCellModel
    func accessory(forKey key: String) -> ItemAccessory?
    func process(action: ItemAction.Kind, for item: RItem, completionAction: ((Bool) -> Void)?)
    func process(tapAction action: ItemsTableViewHandler.TapAction)
    func process(dragAndDropAction action: ItemsTableViewHandler.DragAndDropAction)
    func createContextMenuActions(for item: RItem) -> [ItemAction]
}

final class ItemsTableViewHandler: NSObject {
    enum TapAction {
        case metadata(RItem)
        case note(RItem)
        case attachment(attachment: Attachment, parentKey: String?)
        case doi(String)
        case url(URL)
        case selectItem(String)
        case deselectItem(String)
    }

    enum DragAndDropAction {
        case moveItems(keys: Set<String>, toKey: String)
        case tagItem(key: String, libraryId: LibraryIdentifier, tags: Set<String>)
    }

    private static let cellId = "ItemCell"
    private unowned let tableView: UITableView
    private unowned let delegate: ItemsTableViewHandlerDelegate
    private unowned let dragDropController: DragDropController
    private let disposeBag: DisposeBag

    private var snapshot: Results<RItem>?
    private var reloadAnimationsDisabled: Bool

    init(
        tableView: UITableView,
        delegate: ItemsTableViewHandlerDelegate,
        dragDropController: DragDropController
    ) {
        self.tableView = tableView
        self.delegate = delegate
        self.dragDropController = dragDropController
        reloadAnimationsDisabled = false
        disposeBag = DisposeBag()

        super.init()

        setupTableView()
        setupKeyboardObserving()
    }

    deinit {
        DDLogInfo("ItemsTableViewHandler deinitialized")
    }

    private func createTrailingCellActions(for item: RItem) -> [ItemAction] {
        if delegate.isTrash {
            return [ItemAction(type: .delete), ItemAction(type: .restore)]
        }
        var trailingActions: [ItemAction] = [ItemAction(type: .trash), ItemAction(type: .addToCollection)]
        // Allow removing from collection only if item is in current collection. This can happen when "Show items from subcollection" is enabled.
        if let key = delegate.collectionKey, item.collections.filter(.key(key)).first != nil {
            trailingActions.insert(ItemAction(type: .removeFromCollection), at: 1)
        }
        return trailingActions
    }

    private func createContextMenu(for item: RItem) -> UIMenu {
        let actions: [UIAction] = self.delegate.createContextMenuActions(for: item).map({ action in
            return UIAction(title: action.title, image: action.image, attributes: (action.isDestructive ? .destructive : [])) { [weak self] _ in
                self?.delegate.process(action: action.type, for: item, completionAction: nil)
            }
        })
        return UIMenu(title: "", children: actions)
    }

    private func createSwipeConfiguration(from itemActions: [ItemAction], at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !self.tableView.isEditing && self.delegate.library.metadataEditable else { return nil }
        let actions = itemActions.map({ action -> UIContextualAction in
            let contextualAction = UIContextualAction(style: (action.isDestructive ? .destructive : .normal), title: action.title, handler: { [weak self] _, _, completion in
                guard let item = self?.snapshot?[indexPath.row] else {
                    completion(false)
                    return
                }
                self?.delegate.process(action: action.type, for: item, completionAction: completion)
            })
            contextualAction.image = action.image
            switch action.type {
            case .delete, .trash:
                contextualAction.backgroundColor = .systemRed

            case .duplicate, .restore:
                contextualAction.backgroundColor = .systemBlue

            case .addToCollection, .createParent:
                contextualAction.backgroundColor = .systemOrange

            case .removeFromCollection:
                contextualAction.backgroundColor = .systemPurple
            case .sort, .filter, .copyCitation, .copyBibliography, .share, .download, .removeDownload: break
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

    func updateCell(key: String, withAccessory accessory: ItemCellModel.Accessory?) {
        guard let cell = tableView.visibleCells.first(where: { ($0 as? ItemCell)?.key == key }) as? ItemCell else { return }
        cell.set(accessory: accessory)
    }

    func reloadAll(snapshot: Results<RItem>? = nil) {
        if let snapshot {
            self.snapshot = snapshot
        }
        self.tableView.reloadData()
    }

    func reloadAllAttachments() {
        if delegate.isEditing && !delegate.selectedItems.isEmpty, let indexPathsForSelectedRows = tableView.indexPathsForSelectedRows {
            tableView.reconfigureRows(at: indexPathsForSelectedRows)
        } else {
            tableView.reloadData()
        }
    }

    func reload(snapshot: Results<RItem>, modifications: [Int], insertions: [Int], deletions: [Int], completion: (() -> Void)? = nil) {
        if !self.delegate.isInViewHierarchy || self.reloadAnimationsDisabled {
            // If view controller is outside of view hierarchy, performing batch updates with animations will cause a crash (UITableViewAlertForLayoutOutsideViewHierarchy).
            // Simple reload will suffice, animations will not be seen anyway.
            self.snapshot = snapshot
            self.tableView.reloadData()
            completion?()
            return
        }

        self.tableView.performBatchUpdates({
            self.snapshot = snapshot
            self.tableView.deleteRows(at: deletions.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
            self.tableView.reloadRows(at: modifications.map({ IndexPath(row: $0, section: 0) }), with: .none)
            self.tableView.insertRows(at: insertions.map({ IndexPath(row: $0, section: 0) }), with: .automatic)
        }, completion: { _ in
            completion?()
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
        // keyboardDismissMode is device based, regardless of horizontal size class.
        self.tableView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none
        self.tableView.shouldGroupAccessibilityChildren = true

        self.tableView.register(UINib(nibName: "ItemCell", bundle: nil), forCellReuseIdentifier: ItemsTableViewHandler.cellId)
        self.tableView.tableFooterView = UIView()
    }

    private func setupTableView(with keyboardData: KeyboardData) {
        var insets = self.tableView.contentInset
        insets.bottom = keyboardData.visibleHeight
        self.tableView.contentInset = insets
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupTableView(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .rx.notification(.forceReloadItems)
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] _ in
                              self?.reloadAllAttachments()
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

        if let item = self.snapshot?[indexPath.row], let cell = cell as? ItemCell {
            let model = delegate.model(for: item)
            cell.set(item: model)

            let openInfoAction = UIAccessibilityCustomAction(name: L10n.Accessibility.Items.openItem, actionHandler: { [weak self, weak tableView] _ in
                guard let self, let tableView else { return false }
                self.tableView(tableView, didSelectRowAt: indexPath)
                return true
            })
            cell.accessibilityCustomActions = [openInfoAction]
        }

        return cell
    }
}

extension ItemsTableViewHandler: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let action = tapAction(for: indexPath) else { return }
        switch action {
        case .attachment, .doi, .metadata, .note, .url:
            tableView.deselectRow(at: indexPath, animated: true)

        case .selectItem:
            break

        case .deselectItem: // this should never happen
            DDLogError("ItemsTableViewHandler: deselect item action called in didSelectRowAt")
            return
        }

        delegate.process(tapAction: action)

        func tapAction(for indexPath: IndexPath) -> TapAction? {
            guard let item = self.snapshot?[indexPath.row] else { return nil }

            if delegate.isEditing {
                return .selectItem(item.key)
            }

            guard let accessory = delegate.accessory(forKey: item.key) else {
                switch item.rawType {
                case ItemTypes.note:
                    return .note(item)

                default:
                    return .metadata(item)
                }
            }

            switch accessory {
            case .attachment(let attachment, let parentKey):
                return .attachment(attachment: attachment, parentKey: parentKey)

            case .doi(let doi):
                return .doi(doi)

            case .url(let url):
                return .url(url)
            }
        }
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard let item = self.snapshot?[indexPath.row] else { return }
        switch item.rawType {
        case ItemTypes.note:
            delegate.process(tapAction: .note(item))

        default:
            delegate.process(tapAction: .metadata(item))
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard delegate.isEditing, let item = self.snapshot?[indexPath.row] else { return }
        delegate.process(tapAction: .deselectItem(item.key))
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return tableView.isEditing
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !tableView.isEditing, let item = self.snapshot?[indexPath.row] else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            return self.createContextMenu(for: item)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = self.snapshot?[indexPath.row] else { return nil }
        return self.createSwipeConfiguration(from: self.createTrailingCellActions(for: item), at: indexPath)
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
        guard let item = coordinator.destinationIndexPath.flatMap({ self.snapshot?[$0.row] }),
              let libraryId = item.libraryId else { return }

        switch coordinator.proposal.operation {
        case .copy:
            let key = item.key
            let localObject = coordinator.items.first?.dragItem.localObject
            self.dragDropController.keys(from: coordinator.items.map({ $0.dragItem })) { [weak self] keys in
                guard let self else { return }
                if localObject is RItem {
                    delegate.process(dragAndDropAction: .moveItems(keys: keys, toKey: key))
                } else if localObject is RTag {
                    delegate.process(dragAndDropAction: .tagItem(key: key, libraryId: libraryId, tags: keys))
                }
            }
        default: break
        }
    }

    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        guard
            delegate.library.metadataEditable,                // allow only when library is editable
            session.localDragSession != nil,                  // allow only local drag session
            let destinationIndexPath = destinationIndexPath,
            let results = self.snapshot,
            destinationIndexPath.row < results.count,
            session.items.first?.localObject is RItem
        else {
            return UITableViewDropProposal(operation: .forbidden)
        }
        return self.itemDropSessionDidUpdate(session: session, withDestinationIndexPath: destinationIndexPath, results: results)
    }

    private func itemDropSessionDidUpdate(session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath, results: Results<RItem>) -> UITableViewDropProposal {
        let dragItemsLibraryId = session.items.compactMap({ $0.localObject as? RItem }).compactMap({ $0.libraryId }).first
        let item = results[destinationIndexPath.row]

        if dragItemsLibraryId != item.libraryId ||                                          // allow dropping only to the same library
           item.rawType == ItemTypes.note || item.rawType == ItemTypes.attachment ||        // allow dropping only to non-standalone items
           session.items.compactMap({ self.dragDropController.item(from: $0) })             // allow drops of only standalone items
                        .contains(where: { $0.rawType != ItemTypes.attachment && $0.rawType != ItemTypes.note })
        {
           return UITableViewDropProposal(operation: .forbidden)
        }

        return UITableViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
    }
}
