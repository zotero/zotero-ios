//
//  ItemsCollectionViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

typealias ItemContextualActionCompletion = (Bool) -> Void

protocol ItemsCollectionViewHandlerDelegate: AnyObject {
    var isInViewHierarchy: Bool { get }
    var collectionKey: String? { get }
    var library: Library { get }

    func process(action: ItemAction.Kind, at indexPath: IndexPath, contextualActionCompletion: ItemContextualActionCompletion?)
    func process(tapAction action: ItemsCollectionViewHandler.TapAction)
    func process(dragAndDropAction action: ItemsCollectionViewHandler.DragAndDropAction)
}

protocol ItemsCollectionViewDataSource: UICollectionViewDataSource {
    var count: Int { get }
    var selectedItems: Set<AnyHashable> { get }
    var handler: ItemsCollectionViewHandler? { get set }

    func object(at index: Int) -> ItemsCollectionViewObject?
    func tapAction(for indexPath: IndexPath) -> ItemsCollectionViewHandler.TapAction?
    func createTrailingCellActions(at index: Int) -> [ItemAction]?
    func createContextMenuActions(at index: Int) -> [ItemAction]
}

final class ItemsCollectionViewHandler: NSObject {
    enum TapAction {
        case metadata(ItemsCollectionViewObject)
        case note(ItemsCollectionViewObject)
        case attachment(attachment: Attachment, parentKey: String?)
        case doi(String)
        case url(URL)
        case selectItem(ItemsCollectionViewObject)
        case deselectItem(ItemsCollectionViewObject)
    }

    enum DragAndDropAction {
        case moveItems(keys: Set<String>, toKey: String)
        case tagItem(key: String, libraryId: LibraryIdentifier, tags: Set<String>)
    }

    static let cellId = "ItemCell"
    private unowned let collectionView: UICollectionView
    private unowned let delegate: ItemsCollectionViewHandlerDelegate
    private unowned let dataSource: ItemsCollectionViewDataSource
    private unowned let dragDropController: DragDropController?
    private let disposeBag: DisposeBag

    private var reloadAnimationsDisabled: Bool

    init(
        collectionView: UICollectionView,
        delegate: ItemsCollectionViewHandlerDelegate,
        dataSource: ItemsCollectionViewDataSource,
        dragDropController: DragDropController?
    ) {
        self.collectionView = collectionView
        self.delegate = delegate
        self.dataSource = dataSource
        self.dragDropController = dragDropController
        reloadAnimationsDisabled = false
        disposeBag = DisposeBag()

        super.init()

        dataSource.handler = self
        bindCollectionView()
    }

    deinit {
        DDLogInfo("ItemsCollectionViewHandler deinitialized")
    }

    func attachmentAccessoriesChanged() {
        if collectionView.isEditing, !dataSource.selectedItems.isEmpty {
            // Accessories changed by user, reload only selected items.
            reloadSelected()
        } else {
            // Otherwise just reload everything.
            collectionView.reloadData()
        }

        func reloadSelected() {
            guard let indexPaths = collectionView.indexPathsForSelectedItems else { return }
            collectionView.reconfigureItems(at: indexPaths)
        }
    }

    func reloadAll() {
        collectionView.reloadData()
    }

    private func createContextMenu(at indexPath: IndexPath) -> UIMenu {
        let actions: [UIAction] = dataSource.createContextMenuActions(at: indexPath.item).map({ action in
            return UIAction(title: action.title, image: action.image, attributes: (action.isDestructive ? .destructive : [])) { [weak self] _ in
                self?.delegate.process(action: action.type, at: indexPath, contextualActionCompletion: nil)
            }
        })
        return UIMenu(title: "", children: actions)
    }

    private func createSwipeConfiguration(from itemActions: [ItemAction], at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !collectionView.isEditing && delegate.library.metadataEditable else { return nil }
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
                delegate.process(action: action.type, at: indexPath, contextualActionCompletion: completion)
            })
            contextualAction.image = action.image
            switch action.type {
            case .delete, .trash:
                contextualAction.backgroundColor = .systemRed

            case .duplicate, .restore:
                contextualAction.backgroundColor = .systemBlue

            case .addToCollection, .createParent, .retrieveMetadata, .getStructuredText:
                contextualAction.backgroundColor = .systemOrange

            case .removeFromCollection, .removeFromRecentlyRead:
                contextualAction.backgroundColor = .systemPurple

            case .sort, .filter, .copyCitation, .copyBibliography, .share, .download, .removeDownload, .debugReader:
                break
            }
            return contextualAction
        })
        return UISwipeActionsConfiguration(actions: actions)
    }

    func trailingSwipeActionsConfiguration(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return dataSource.createTrailingCellActions(at: indexPath.item).flatMap({ createSwipeConfiguration(from: $0, at: indexPath) })
    }

    func sourceItemForCell(for key: String) -> UIPopoverPresentationControllerSourceItem {
        return collectionView.visibleCells.first(where: { ($0 as? ItemCell)?.key == key }) ?? collectionView
    }

    func reload(modifications: [IndexPath], insertions: [IndexPath], deletions: [IndexPath], updateSnapshot: () -> Void, completion: (() -> Void)? = nil) {
        if !delegate.isInViewHierarchy || reloadAnimationsDisabled {
            // Avoid animated batch updates while the collection view is not visible.
            // The changes will not be seen, so a reload is sufficient.
            updateSnapshot()
            collectionView.reloadData()
            completion?()
            return
        }

        collectionView.performBatchUpdates({
            updateSnapshot()
            collectionView.deleteItems(at: deletions)
            collectionView.reconfigureItems(at: modifications)
            collectionView.insertItems(at: insertions)
        }, completion: { _ in
            completion?()
        })
    }

    // MARK: - Actions

    /// Disables performing collection view batch reloads. Instead just uses `reloadData()`.
    func disableReloadAnimations() {
        reloadAnimationsDisabled = true
    }

    /// Enables performing collection view batch reloads.
    func enableReloadAnimations() {
        reloadAnimationsDisabled = false
    }

    func set(editing: Bool, animated: Bool) {
        if editing && collectionView.isEditing {
            // End an active swipe before entering multiple selection mode.
            collectionView.isEditing = false
        }
        if animated {
            collectionView.isEditing = editing
        } else {
            UIView.performWithoutAnimation {
                collectionView.isEditing = editing
                collectionView.layoutIfNeeded()
            }
        }
    }

    func updateCell(key: String, withAccessory accessory: ItemCellModel.Accessory?) {
        guard let cell = collectionView.visibleCells.first(where: { ($0 as? ItemCell)?.key == key }) as? ItemCell else { return }
        cell.set(accessory: accessory)
    }

    func updateCell(key: String, withSubtitle subtitle: ItemCellModel.Subtitle?) {
        guard let cell = collectionView.visibleCells.first(where: { ($0 as? ItemCell)?.key == key }) as? ItemCell else { return }
        cell.set(subtitle: subtitle)
    }

    @discardableResult
    func performTapAction(forIndexPath indexPath: IndexPath) -> Bool {
        guard let action = dataSource.tapAction(for: indexPath) else {
            collectionView.deselectItem(at: indexPath, animated: true)
            return false
        }
        switch action {
        case .attachment, .doi, .metadata, .note, .url:
            collectionView.deselectItem(at: indexPath, animated: true)

        case .selectItem:
            break

        case .deselectItem: // this should never happen
            DDLogError("ItemsCollectionViewHandler: deselect item action called in didSelectItemAt")
            return false
        }
        delegate.process(tapAction: action)
        return true
    }

    private func performAccessoryAction(at indexPath: IndexPath) {
        guard let object = dataSource.object(at: indexPath.item) else { return }
        if object.isNote {
            delegate.process(tapAction: .note(object))
        } else {
            delegate.process(tapAction: .metadata(object))
        }
    }

    func selectAll() {
        let itemCount = collectionView.numberOfItems(inSection: 0)
        (0..<itemCount).forEach { item in
            collectionView.selectItem(at: IndexPath(item: item, section: 0), animated: false, scrollPosition: [])
        }
    }

    func deselectAll() {
        collectionView.indexPathsForSelectedItems?.forEach({ indexPath in
            collectionView.deselectItem(at: indexPath, animated: false)
        })
    }

    // MARK: - Setups

    private func bindCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = dataSource
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.allowsSelectionDuringEditing = true
        collectionView.allowsMultipleSelectionDuringEditing = true
        // keyboardDismissMode is device based, regardless of horizontal size class.
        collectionView.keyboardDismissMode = UIDevice.current.userInterfaceIdiom == .phone ? .interactive : .none
        collectionView.shouldGroupAccessibilityChildren = true
        collectionView.register(ItemCell.self, forCellWithReuseIdentifier: Self.cellId)
    }
}

extension ItemsCollectionViewHandler: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        performTapAction(forIndexPath: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard collectionView.isEditing, let object = dataSource.object(at: indexPath.item) else { return }
        delegate.process(tapAction: .deselectItem(object))
    }

    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        return collectionView.isEditing
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !collectionView.isEditing else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            return self.createContextMenu(at: indexPath)
        }
    }
}

extension ItemsCollectionViewHandler: ItemCellActionDelegate {
    func itemCellDidTapDetail(_ cell: ItemCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        performAccessoryAction(at: indexPath)
    }

    func itemCellDidRequestOpen(_ cell: ItemCell) -> Bool {
        guard let indexPath = collectionView.indexPath(for: cell) else { return false }
        return performTapAction(forIndexPath: indexPath)
    }
}

extension ItemsCollectionViewHandler: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let dragDropController, let item = dataSource.object(at: indexPath.item) as? RItem else { return [] }
        let localContext = (session.localContext as? DragDropController.LocalContext) ?? dragDropController.startContext(libraryIdentifier: item.libraryIdentifier)
        session.localContext = localContext
        guard localContext.addToContext(item: item) else { return [] }
        return [dragDropController.dragItem(from: item, localContext: localContext)]
    }

    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: any UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        guard let dragDropController,
              let item = dataSource.object(at: indexPath.item) as? RItem,
              let localContext = session.localContext as? DragDropController.LocalContext,
              localContext.addToContext(item: item)
        else { return [] }
        return [dragDropController.dragItem(from: item, localContext: localContext)]
    }
}

extension ItemsCollectionViewHandler: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let indexPath = coordinator.destinationIndexPath, let object = dataSource.object(at: indexPath.item) else { return }
        switch coordinator.proposal.operation {
        case .copy:
            let key = object.key
            guard let localContext = coordinator.session.localDragSession?.localContext as? DragDropController.LocalContext, !localContext.keys.isEmpty else { break }
            delegate.process(dragAndDropAction: .moveItems(keys: localContext.keys, toKey: key))

        default:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        let library = delegate.library
        guard library.metadataEditable,
              let localContext = session.localDragSession?.localContext as? DragDropController.LocalContext,
              localContext.libraryIdentifier == library.identifier,
              !localContext.keys.isEmpty,
              let destinationIndexPath,
              destinationIndexPath.item < dataSource.count,
              let object = dataSource.object(at: destinationIndexPath.item),
              !object.isNote,
              !object.isAttachment,
              !session.items.compactMap({ $0.localObject as? RItem }).contains(where: { $0.rawType != ItemTypes.attachment && $0.rawType != ItemTypes.note })
        else { return UICollectionViewDropProposal(operation: .forbidden) }
        return UICollectionViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
    }
}
