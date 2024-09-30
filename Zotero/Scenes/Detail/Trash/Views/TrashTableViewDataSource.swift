//
//  TrashTableViewDataSource.swift
//  Zotero
//
//  Created by Michal Rentka on 19.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import OrderedCollections

import CocoaLumberjackSwift

final class TrashTableViewDataSource: NSObject, ItemsTableViewDataSource {
    private let viewModel: ViewModel<TrashActionHandler>
    private unowned let fileDownloader: AttachmentDownloader?

    weak var handler: ItemsTableViewHandler?
    private var snapshot: OrderedDictionary<TrashKey, TrashObject>?

    init(viewModel: ViewModel<TrashActionHandler>, fileDownloader: AttachmentDownloader?) {
        self.viewModel = viewModel
        self.fileDownloader = fileDownloader
    }

    func apply(snapshot: OrderedDictionary<TrashKey, TrashObject>) {
        self.snapshot = snapshot
        handler?.reloadAll()
    }

    func updateCellAccessory(key: TrashKey, snapshot: OrderedDictionary<TrashKey, TrashObject>) {
        self.snapshot = snapshot
        guard let itemAccessory = snapshot[key]?.itemAccessory else { return }
        let accessory = ItemCellModel.createAccessory(from: itemAccessory, fileDownloader: fileDownloader)
        handler?.updateCell(key: key.key, withAccessory: accessory)
    }

    func updateAttachmentAccessories(snapshot: OrderedDictionary<TrashKey, TrashObject>) {
        self.snapshot = snapshot
        handler?.attachmentAccessoriesChanged()
    }
}

extension TrashTableViewDataSource {
    var count: Int {
        return snapshot?.count ?? 0
    }

    var selectedItems: Set<AnyHashable> {
        return viewModel.state.selectedItems
    }

    func key(at index: Int) -> TrashKey? {
        guard let snapshot, index < snapshot.keys.count else { return nil }
        return snapshot.keys[index]
    }

    func object(at index: Int) -> ItemsTableViewObject? {
        return trashObject(at: index)
    }

    private func trashObject(at index: Int) -> TrashObject? {
        guard let snapshot, index < snapshot.keys.count else { return nil }
        return snapshot.values[index]
    }

    func tapAction(for indexPath: IndexPath) -> ItemsTableViewHandler.TapAction? {
        guard let object = trashObject(at: indexPath.row) else { return nil }

        if viewModel.state.isEditing {
            return .selectItem(object)
        }

        guard let accessory = object.itemAccessory else {
            guard case .item(let item) = object.type else { return nil }
            switch item.type {
            case ItemTypes.note:
                return .note(object)

            default:
                return .metadata(object)
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

    func createTrailingCellActions(at index: Int) -> [ItemAction]? {
        return [ItemAction(type: .delete), ItemAction(type: .restore)]
    }

    func createContextMenuActions(at index: Int) -> [ItemAction] {
        var actions = [ItemAction(type: .restore), ItemAction(type: .delete)]

        // Add download/remove downloaded option for attachments
        if let accessory = trashObject(at: index)?.itemAccessory, let location = accessory.attachment?.location {
            switch location {
            case .local:
                actions.append(ItemAction(type: .removeDownload))

            case .remote:
                actions.append(ItemAction(type: .download))

            case .localAndChangedRemotely:
                actions.append(ItemAction(type: .download))
                actions.append(ItemAction(type: .removeDownload))

            case .remoteMissing:
                break
            }
        }

        return actions
    }
}

extension TrashTableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ItemsTableViewHandler.cellId, for: indexPath)

        guard let object = trashObject(at: indexPath.row) else {
            DDLogError("TrashTableViewDataSource: indexPath.row (\(indexPath.row)) out of bounds (\(count))")
            return cell
        }

        if let cell = cell as? ItemCell {
            cell.set(item: ItemCellModel(object: object, fileDownloader: fileDownloader))

            let openInfoAction = UIAccessibilityCustomAction(name: L10n.Accessibility.Items.openItem, actionHandler: { [weak self] _ in
                guard let self else { return false }
                handler?.performTapAction(forIndexPath: indexPath)
                return true
            })
            cell.accessibilityCustomActions = [openInfoAction]
        }

        return cell
    }
}

extension TrashObject: ItemsTableViewObject {
    var isNote: Bool {
        switch type {
        case .item(let item):
            return item.type == ItemTypes.note

        case .collection:
            return false
        }
    }
    
    var isAttachment: Bool {
        switch type {
        case .item(let item):
            return item.type == ItemTypes.attachment

        case .collection:
            return false
        }
    }

    var libraryIdentifier: LibraryIdentifier {
        return libraryId
    }
}
