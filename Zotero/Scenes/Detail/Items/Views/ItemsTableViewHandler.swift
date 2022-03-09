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

protocol ItemsTableViewHandlerDelegate: AnyObject {
    var isInViewHierarchy: Bool { get }

    func process(action: ItemAction.Kind, for item: RItem, completionAction: ((Bool) -> Void)?)
}

final class ItemsTableViewHandler: NSObject {
    enum TapAction {
        case metadata(RItem)
        case doi(String)
        case url(URL)
        case showAttachmentError(Error, Attachment, String?)
    }

    private static let cellId = "ItemCell"
    private unowned let tableView: UITableView
    private unowned let viewModel: ViewModel<ItemsActionHandler>
    private unowned let delegate: ItemsTableViewHandlerDelegate
    private unowned let dragDropController: DragDropController
    let tapObserver: PublishSubject<TapAction>
    private let disposeBag: DisposeBag

    private var snapshot: Results<RItem>?
    private var reloadAnimationsDisabled: Bool
    private weak var fileDownloader: AttachmentDownloader?
    private weak var schemaController: SchemaController?

    init(tableView: UITableView, viewModel: ViewModel<ItemsActionHandler>, delegate: ItemsTableViewHandlerDelegate, dragDropController: DragDropController,
         fileDownloader: AttachmentDownloader?, schemaController: SchemaController?) {
        self.tableView = tableView
        self.viewModel = viewModel
        self.delegate = delegate
        self.dragDropController = dragDropController
        self.fileDownloader = fileDownloader
        self.schemaController = schemaController
        self.reloadAnimationsDisabled = false
        self.tapObserver = PublishSubject()
        self.disposeBag = DisposeBag()

        super.init()

        self.setupTableView()
        self.setupKeyboardObserving()
    }

    deinit {
        DDLogInfo("ItemsTableViewHandler deinitialized")
    }

    private func createContextMenuActions(for item: RItem, state: ItemsState) -> [ItemAction] {
        if state.collection.identifier.isTrash {
            return [ItemAction(type: .restore), ItemAction(type: .delete)]
        }

        var actions: [ItemAction] = []

        // Add citation for valid types
        if !CitationController.invalidItemTypes.contains(item.rawType) {
            actions.append(contentsOf: [ItemAction(type: .copyCitation), ItemAction(type: .copyBibliography), ItemAction(type: .share)])
        }

        // Add parent creation for standalone attachments
        if item.rawType == ItemTypes.attachment, item.parent == nil {
            actions.append(ItemAction(type: .createParent))
        }
        
        // Add download/remove downloaded option for attachments
        if let accessory = state.itemAccessories[item.key], let location = accessory.attachment?.location {
            switch location {
            case .local:
                actions.append(ItemAction(type: .removeDownload))
            case .remote, .localAndChangedRemotely:
                actions.append(ItemAction(type: .download))
            case .remoteMissing: break
            }
        }

        actions.append(ItemAction(type: .addToCollection))

        // Add removing from collection only if item is in current collection.
        if case .collection(let key) = state.collection.identifier, item.collections.filter(.key(key)).first != nil {
            actions.append(ItemAction(type: .removeFromCollection))
        }

        actions.append(contentsOf: [ItemAction(type: .duplicate), ItemAction(type: .trash)])

        return actions
    }

    private func createTrailingCellActions(for item: RItem, state: ItemsState) -> [ItemAction] {
        if state.collection.identifier.isTrash {
            return [ItemAction(type: .delete), ItemAction(type: .restore)]
        }
        var trailingActions: [ItemAction] = [ItemAction(type: .trash), ItemAction(type: .addToCollection)]
        // Allow removing from collection only if item is in current collection. This can happen when "Show items from subcollection" is enabled.
        if case .collection(let key) = state.collection.identifier, item.collections.filter(.key(key)).first != nil {
            trailingActions.insert(ItemAction(type: .removeFromCollection), at: 1)
        }
        return trailingActions
    }

    private func createContextMenu(for item: RItem) -> UIMenu {
        let actions: [UIAction] = self.createContextMenuActions(for: item, state: self.viewModel.state).map({ action in
            return UIAction(title: action.title, image: action.image, attributes: (action.isDestructive ? .destructive : [])) { [weak self] _ in
                self?.delegate.process(action: action.type, for: item, completionAction: nil)
            }
        })
        return UIMenu(title: "", children: actions)
    }

    private func createSwipeConfiguration(from itemActions: [ItemAction], at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !self.tableView.isEditing && self.viewModel.state.library.metadataEditable else { return nil }
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

    private func cellAccessory(from accessory: ItemAccessory?) -> ItemCellModel.Accessory? {
        return accessory.flatMap({ accessory -> ItemCellModel.Accessory in
            switch accessory {
            case .attachment(let attachment):
                let (progress, error) = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId) ?? (nil, nil)
                return .attachment(.stateFrom(type: attachment.type, progress: progress, error: error))
            case .doi:
                return .doi
            case .url:
                return .url
            }
        })
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

    func updateCell(with accessory: ItemAccessory?, parentKey: String) {
        guard let cell = self.tableView.visibleCells.first(where: { ($0 as? ItemCell)?.key == parentKey }) as? ItemCell else { return }
        cell.set(accessory: self.cellAccessory(from: accessory))
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
        self.tableView.shouldGroupAccessibilityChildren = true

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
                .subscribe(onNext: { [weak self] notification in
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

        if let item = self.snapshot?[indexPath.row],
           let cell = cell as? ItemCell {
            // Create and cache attachment if needed
            self.viewModel.process(action: .cacheItemAccessory(item: item))

            let accessory = self.viewModel.state.itemAccessories[item.key]
            let typeName = self.schemaController?.localized(itemType: item.rawType) ?? item.rawType
            cell.set(item: ItemCellModel(item: item, typeName: typeName, accessory: self.cellAccessory(from: accessory)))

            let openInfoAction = UIAccessibilityCustomAction(name: L10n.Accessibility.Items.openItem, actionHandler: { [weak self, weak tableView] _ in
                guard let `self` = self, let tableView = tableView else { return false }
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
        guard let item = self.snapshot?[indexPath.row] else { return }

        if self.viewModel.state.isEditing {
            self.viewModel.process(action: .selectItem(item.key))
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)

        guard let accessory = self.viewModel.state.itemAccessories[item.key] else {
            self.tapObserver.on(.next(.metadata(item)))
            return
        }

        switch accessory {
        case .attachment(let attachment):
            let parentKey = item.key == attachment.key ? nil : item.key
            if let error = self.fileDownloader?.data(for: attachment.key, libraryId: attachment.libraryId).error {
                self.tapObserver.on(.next(.showAttachmentError(error, attachment, parentKey)))
            } else {
                self.viewModel.process(action: .openAttachment(attachment: attachment, parentKey: parentKey))
            }
        case .doi(let doi):
            self.tapObserver.on(.next(.doi(doi)))
        case .url(let url):
            self.tapObserver.on(.next(.url(url)))
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
        guard !tableView.isEditing && self.viewModel.state.library.metadataEditable, let item = self.snapshot?[indexPath.row] else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            return self.createContextMenu(for: item)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = self.snapshot?[indexPath.row] else { return nil }
        return self.createSwipeConfiguration(from: self.createTrailingCellActions(for: item, state: self.viewModel.state), at: indexPath)
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
        case .copy:
            self.dragDropController.itemKeys(from: coordinator.items.map({ $0.dragItem })) { [weak self] keys in
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

        let dragItemsLibraryId = session.items.compactMap({ $0.localObject as? RItem }).compactMap({ $0.libraryId }).first
        let item = results[destinationIndexPath.row]

        if dragItemsLibraryId != item.libraryId ||                                          // allow dropping only to the same library
           item.rawType == ItemTypes.note || item.rawType == ItemTypes.attachment ||        // allow dropping only to non-standalone items
           session.items.compactMap({ self.dragDropController.item(from: $0) })             // allow drops of only standalone items
                        .contains(where: { $0.rawType != ItemTypes.attachment && $0.rawType != ItemTypes.note }) {
           return UITableViewDropProposal(operation: .forbidden)
        }

        return UITableViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
    }
}
