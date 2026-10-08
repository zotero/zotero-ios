//
//  TrashCollectionViewDataSource.swift
//  Zotero
//
//  Created by Michal Rentka on 19.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import OrderedCollections

import CocoaLumberjackSwift

final class TrashCollectionViewDataSource: NSObject, ItemsCollectionViewDataSource {
    private let viewModel: ViewModel<TrashActionHandler>
    private unowned let schemaController: SchemaController
    private unowned let fileDownloader: AttachmentDownloader?

    weak var handler: ItemsCollectionViewHandler?
    private var snapshot: TrashState.Snapshot?

    init(viewModel: ViewModel<TrashActionHandler>, schemaController: SchemaController, fileDownloader: AttachmentDownloader?) {
        self.viewModel = viewModel
        self.schemaController = schemaController
        self.fileDownloader = fileDownloader
    }

    func apply(snapshot: TrashState.Snapshot) {
        self.snapshot = snapshot
        handler?.reloadAll()
    }

    func updateCellAccessory(key: TrashKey, itemAccessory: ItemAccessory) {
        let accessory = ItemCellModel.createAccessory(from: itemAccessory, fileDownloader: fileDownloader)
        handler?.updateCell(key: key.key, withAccessory: accessory)
    }

    func updateAttachmentAccessories() {
        handler?.attachmentAccessoriesChanged()
    }
}

extension TrashCollectionViewDataSource {
    var count: Int {
        return snapshot?.count ?? 0
    }

    var selectedItems: Set<AnyHashable> {
        return viewModel.state.selectedItems
    }

    func key(at index: Int) -> TrashKey? {
        return snapshot?.key(for: index)
    }

    func object(at index: Int) -> ItemsCollectionViewObject? {
        return trashObject(at: index)
    }

    private func trashObject(at index: Int) -> TrashObject? {
        return snapshot?.key(for: index).flatMap({ snapshot?.object(for: $0) })
    }

    func tapAction(for indexPath: IndexPath) -> ItemsCollectionViewHandler.TapAction? {
        guard let object = trashObject(at: indexPath.item) else { return nil }

        if viewModel.state.isEditing {
            return .selectItem(object)
        }

        guard let accessory = viewModel.state.itemDataCache[TrashKey(type: .item, key: object.key)]?.accessory else {
            let itemType = (object as? RItem)?.rawType ?? ""
            switch itemType {
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
        guard let key = snapshot?.key(for: index), let attachment = viewModel.state.itemDataCache[key]?.accessory?.attachment else {
            return actions
        }

        // Add download/remove downloaded option for attachments
        if let location = attachment.location {
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

        #if DEBUG
        if case .file(_, let contentType, _, _, _) = attachment.type, contentType == "application/epub+zip" || contentType == "text/html" {
            actions.append(ItemAction(type: .debugReader))
        }
        #endif

        return actions
    }
}

extension TrashCollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ItemsCollectionViewHandler.cellId, for: indexPath)

        guard let key = key(at: indexPath.item), let object = trashObject(at: indexPath.item) else {
            DDLogError("TrashCollectionViewDataSource: indexPath.item (\(indexPath.item)) out of bounds (\(count))")
            return cell
        }

        if let cell = cell as? ItemCell, let model = model(for: object, key: key) {
            cell.actionDelegate = handler
            cell.set(item: model)
        }

        return cell

        func model(for object: TrashObject, key: TrashKey) -> ItemCellModel? {
            viewModel.process(action: .cacheItemDataIfNeeded(key))
            let data = viewModel.state.itemDataCache[key]
            if let item = object as? RItem {
                let typeName = schemaController.localized(itemType: item.rawType) ?? item.rawType
                return ItemCellModel(item: item, typeName: typeName, title: data?.title ?? NSAttributedString(), accessory: data?.accessory, fileDownloader: fileDownloader, recognizerController: nil)
            } else {
                return ItemCellModel(collectionWithKey: object.key, title: data?.title ?? NSAttributedString())
            }
        }
    }
}

extension RCollection: ItemsCollectionViewObject {
    var isNote: Bool {
        return false
    }
    
    var isAttachment: Bool {
        return false
    }

    var libraryIdentifier: LibraryIdentifier {
        return libraryId ?? .custom(.myLibrary)
    }
}
