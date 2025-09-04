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
    var collectionKey: String? { get }
    var library: Library { get }

    func process(action: ItemAction.Kind, at index: Int, completionAction: ((Bool) -> Void)?)
    func process(tapAction action: ItemsTableViewHandler.TapAction)
    func process(dragAndDropAction action: ItemsTableViewHandler.DragAndDropAction)
}

protocol ItemsTableViewDataSource: UITableViewDataSource {
    var count: Int { get }
    var selectedItems: Set<AnyHashable> { get }
    var handler: ItemsTableViewHandler? { get set }

    func object(at index: Int) -> ItemsTableViewObject?
    func tapAction(for indexPath: IndexPath) -> ItemsTableViewHandler.TapAction?
    func createTrailingCellActions(at index: Int) -> [ItemAction]?
    func createContextMenuActions(at index: Int) -> [ItemAction]
}

final class ItemsTableViewHandler: NSObject {
    enum TapAction {
        case metadata(ItemsTableViewObject)
        case note(ItemsTableViewObject)
        case attachment(attachment: Attachment, parentKey: String?)
        case doi(String)
        case url(URL)
        case selectItem(ItemsTableViewObject)
        case deselectItem(ItemsTableViewObject)
    }

    enum DragAndDropAction {
        case moveItems(keys: Set<String>, toKey: String)
        case tagItem(key: String, libraryId: LibraryIdentifier, tags: Set<String>)
    }

    static let cellId = "ItemCell"
    private unowned let tableView: UITableView
    private unowned let delegate: ItemsTableViewHandlerDelegate
    private unowned let dataSource: ItemsTableViewDataSource
    private unowned let dragDropController: DragDropController?
    private let disposeBag: DisposeBag

    private var reloadAnimationsDisabled: Bool

    init(
        tableView: UITableView,
        delegate: ItemsTableViewHandlerDelegate,
        dataSource: ItemsTableViewDataSource,
        dragDropController: DragDropController?
    ) {
        self.tableView = tableView
        self.delegate = delegate
        self.dataSource = dataSource
        self.dragDropController = dragDropController
        reloadAnimationsDisabled = false
        disposeBag = DisposeBag()

        super.init()

        dataSource.handler = self
        setupTableView()
        setupKeyboardObserving()
    }

    deinit {
        DDLogInfo("ItemsTableViewHandler deinitialized")
    }

    func attachmentAccessoriesChanged() {
        if tableView.isEditing, !dataSource.selectedItems.isEmpty {
            // Accessories changed by user, reload only selected items
            reloadSelected()
        } else {
            // Otherwise just reload everything
            tableView.reloadData()
        }

        func reloadSelected() {
            guard let indexPathsForSelectedRows = tableView.indexPathsForSelectedRows else { return }
            tableView.reconfigureRows(at: indexPathsForSelectedRows)
        }
    }

    func reloadAll() {
        tableView.reloadData()
    }

    private func createContextMenu(at indexPath: IndexPath) -> UIMenu {
        let actions: [UIAction] = dataSource.createContextMenuActions(at: indexPath.row).map({ action in
            return UIAction(title: action.title, image: action.image, attributes: (action.isDestructive ? .destructive : [])) { [weak self] _ in
                self?.delegate.process(action: action.type, at: indexPath.row, completionAction: nil)
            }
        })
        return UIMenu(title: "", children: actions)
    }

    private func createSwipeConfiguration(from itemActions: [ItemAction], at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !tableView.isEditing && delegate.library.metadataEditable else { return nil }
        let actions = itemActions.map({ action -> UIContextualAction in
            var title: String?
            if #unavailable(iOS 26.0.0) {
                title = action.title
            }
            let contextualAction = UIContextualAction(style: (action.isDestructive ? .destructive : .normal), title: title, handler: { [weak self] _, _, completion in
                guard let self else {
                    completion(false)
                    return
                }
                delegate.process(action: action.type, at: indexPath.row, completionAction: completion)
            })
            contextualAction.image = action.image
            switch action.type {
            case .delete, .trash:
                contextualAction.backgroundColor = .systemRed

            case .duplicate, .restore:
                contextualAction.backgroundColor = .systemBlue

            case .addToCollection, .createParent, .retrieveMetadata:
                contextualAction.backgroundColor = .systemOrange

            case .removeFromCollection:
                contextualAction.backgroundColor = .systemPurple
            case .sort, .filter, .copyCitation, .copyBibliography, .share, .download, .removeDownload: break
            }
            return contextualAction
        })
        return UISwipeActionsConfiguration(actions: actions)
    }

    func sourceItemForCell(for key: String) -> UIPopoverPresentationControllerSourceItem {
        return tableView.visibleCells.first(where: { ($0 as? ItemCell)?.key == key }) ?? tableView
    }

    func reload(modifications: [IndexPath], insertions: [IndexPath], deletions: [IndexPath], updateSnapshot: () -> Void, completion: (() -> Void)? = nil) {
        if !delegate.isInViewHierarchy || reloadAnimationsDisabled {
            // If view controller is outside of view hierarchy, performing batch updates with animations will cause a crash (UITableViewAlertForLayoutOutsideViewHierarchy).
            // Simple reload will suffice, animations will not be seen anyway.
            updateSnapshot()
            tableView.reloadData()
            completion?()
            return
        }

        tableView.performBatchUpdates({
            updateSnapshot()
            tableView.deleteRows(at: deletions, with: .automatic)
            tableView.reloadRows(at: modifications, with: .none)
            tableView.insertRows(at: insertions, with: .automatic)
        }, completion: { _ in
            completion?()
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

    func updateCell(key: String, withAccessory accessory: ItemCellModel.Accessory?) {
        guard let cell = tableView.visibleCells.first(where: { ($0 as? ItemCell)?.key == key }) as? ItemCell else { return }
        cell.set(accessory: accessory)
    }

    func updateCell(key: String, withSubtitle subtitle: ItemCellModel.Subtitle?) {
        guard let cell = tableView.visibleCells.first(where: { ($0 as? ItemCell)?.key == key }) as? ItemCell else { return }
        cell.set(subtitle: subtitle)
    }

    func performTapAction(forIndexPath indexPath: IndexPath) {
        guard let action = dataSource.tapAction(for: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
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
    }

    func selectAll() {
        let rows = dataSource.tableView(tableView, numberOfRowsInSection: 0)
        (0..<rows).forEach { row in
            tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
        }
    }

    func deselectAll() {
        tableView.indexPathsForSelectedRows?.forEach({ indexPath in
            tableView.deselectRow(at: indexPath, animated: false)
        })
    }

    // MARK: - Setups

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self.dataSource
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        if #available(iOS 26.0.0, *) {
            tableView.rowHeight = 68
            tableView.estimatedRowHeight = 68
            tableView.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 12)
        } else {
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 60
            tableView.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 0)
        }
        tableView.allowsMultipleSelectionDuringEditing = true
        // keyboardDismissMode is device based, regardless of horizontal size class.
        tableView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none
        tableView.shouldGroupAccessibilityChildren = true

        tableView.register(UINib(nibName: "ItemCell", bundle: nil), forCellReuseIdentifier: Self.cellId)
        tableView.tableFooterView = UIView()
    }

    private func setupTableView(with keyboardData: KeyboardData) {
        var insets = tableView.contentInset
        insets.bottom = keyboardData.visibleHeight
        tableView.contentInset = insets
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
    }
}

extension ItemsTableViewHandler: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        performTapAction(forIndexPath: indexPath)
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard let object = dataSource.object(at: indexPath.row) else { return }
        if object.isNote {
            delegate.process(tapAction: .note(object))
        } else {
            delegate.process(tapAction: .metadata(object))
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard tableView.isEditing, let object = dataSource.object(at: indexPath.row) else { return }
        delegate.process(tapAction: .deselectItem(object))
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return tableView.isEditing
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !tableView.isEditing else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            return self.createContextMenu(at: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return dataSource.createTrailingCellActions(at: indexPath.row).flatMap({ createSwipeConfiguration(from: $0, at: indexPath) })
    }
}

extension ItemsTableViewHandler: UITableViewDragDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let dragDropController, let item = dataSource.object(at: indexPath.row) as? RItem else { return [] }
        let localContext = (session.localContext as? DragDropController.LocalContext) ?? dragDropController.startContext(libraryIdentifier: item.libraryIdentifier)
        session.localContext = localContext
        guard localContext.addToContext(item: item) else { return [] }
        return [dragDropController.dragItem(from: item, localContext: localContext)]
    }

    func tableView(_ tableView: UITableView, itemsForAddingTo session: any UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        guard let dragDropController,
              let item = dataSource.object(at: indexPath.row) as? RItem,
              let localContext = session.localContext as? DragDropController.LocalContext,
              localContext.addToContext(item: item)
        else { return [] }
        return [dragDropController.dragItem(from: item, localContext: localContext)]
    }
}

extension ItemsTableViewHandler: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath, let object = dataSource.object(at: indexPath.row) else { return }
        switch coordinator.proposal.operation {
        case .copy:
            let key = object.key
            guard let localContext = coordinator.session.localDragSession?.localContext as? DragDropController.LocalContext, !localContext.keys.isEmpty else { break }
            delegate.process(dragAndDropAction: .moveItems(keys: localContext.keys, toKey: key))

        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        let library = delegate.library
        guard library.metadataEditable,
              let localContext = session.localDragSession?.localContext as? DragDropController.LocalContext,
              localContext.libraryIdentifier == library.identifier,
              !localContext.keys.isEmpty,
              let destinationIndexPath,
              destinationIndexPath.row < dataSource.count,
              let object = dataSource.object(at: destinationIndexPath.row),
              !object.isNote,
              !object.isAttachment,
              !session.items.compactMap({ $0.localObject as? RItem }).contains(where: { $0.rawType != ItemTypes.attachment && $0.rawType != ItemTypes.note })
        else { return UITableViewDropProposal(operation: .forbidden) }
        return UITableViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
    }
}
