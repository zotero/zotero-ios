//
//  RItemsCollectionViewDataSource.swift
//  Zotero
//
//  Created by Michal Rentka on 19.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift

extension RItem: ItemsCollectionViewObject {
    var libraryIdentifier: LibraryIdentifier {
        return libraryId ?? .custom(.myLibrary)
    }
    
    var isNote: Bool {
        switch rawType {
        case ItemTypes.note:
            return true

        default:
            return false
        }
    }

    var isAttachment: Bool {
        switch rawType {
        case ItemTypes.attachment:
            return true

        default:
            return false
        }
    }
}

final class RItemsCollectionViewDataSource: NSObject {
    private unowned let viewModel: ViewModel<ItemsActionHandler>
    private unowned let schemaController: SchemaController
    private weak var fileDownloader: AttachmentDownloader?
    private weak var recognizerController: RecognizerController?

    private var snapshot: Results<RItem>?
    weak var handler: ItemsCollectionViewHandler?

    init(viewModel: ViewModel<ItemsActionHandler>, fileDownloader: AttachmentDownloader?, recognizerController: RecognizerController?, schemaController: SchemaController) {
        self.viewModel = viewModel
        self.fileDownloader = fileDownloader
        self.recognizerController = recognizerController
        self.schemaController = schemaController
    }

    func apply(snapshot: Results<RItem>) {
        self.snapshot = snapshot
        handler?.reloadAll()
    }

    func apply(snapshot: Results<RItem>, modifications: [Int], insertions: [Int], deletions: [Int], completion: (() -> Void)? = nil) {
        guard let handler else { return }
        handler.reload(
            modifications: modifications.map({ IndexPath(item: $0, section: 0) }),
            insertions: insertions.map({ IndexPath(item: $0, section: 0) }),
            deletions: deletions.map({ IndexPath(item: $0, section: 0) }),
            updateSnapshot: {
                self.snapshot = snapshot
            },
            completion: completion
        )
    }

    private func accessory(forKey key: String) -> ItemAccessory? {
        return viewModel.state.itemAccessories[key]
    }
}

extension RItemsCollectionViewDataSource: ItemsCollectionViewDataSource {
    var count: Int {
        return snapshot?.count ?? 0
    }

    var selectedItems: Set<AnyHashable> {
        return viewModel.state.selectedItems
    }

    func object(at index: Int) -> ItemsCollectionViewObject? {
        return item(at: index)
    }

    private func item(at index: Int) -> RItem? {
        guard index < count else { return nil }
        return snapshot?[index]
    }

    func tapAction(for indexPath: IndexPath) -> ItemsCollectionViewHandler.TapAction? {
        guard let item = item(at: indexPath.item) else { return nil }

        if viewModel.state.isEditing {
            return .selectItem(item)
        }

        guard let accessory = accessory(forKey: item.key) else {
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

    func createTrailingCellActions(at index: Int) -> [ItemAction]? {
        guard let item = item(at: index) else { return nil }
        var trailingActions: [ItemAction] = [ItemAction(type: .trash), ItemAction(type: .addToCollection)]
        // Allow removing from collection only if item is in current collection. This can happen when "Show items from subcollection" is enabled.
        if let key = viewModel.state.collection.identifier.key, item.collections.filter(.key(key)).first != nil {
            trailingActions.insert(ItemAction(type: .removeFromCollection), at: 1)
        } else if case .custom(.recentlyRead) = viewModel.state.collection.identifier {
            trailingActions.insert(ItemAction(type: .removeFromRecentlyRead), at: 1)
        }
        return trailingActions
    }

    func createContextMenuActions(at index: Int) -> [ItemAction] {
        guard let item = item(at: index) else { return [] }

        var actions: [ItemAction] = []

        // Add citation for valid types
        if !CitationController.invalidItemTypes.contains(item.rawType) {
            actions.append(contentsOf: [ItemAction(type: .copyCitation), ItemAction(type: .copyBibliography), ItemAction(type: .share)])
        }

        let attachment = accessory(forKey: item.key)?.attachment
        let location = attachment?.location

        // Add parent creation for standalone attachments
        if item.rawType == ItemTypes.attachment && item.parent == nil {
            if FeatureGates.enabled.contains(.documentWorker), attachment?.file?.mimeType == "application/pdf" {
                switch location {
                case .local, .localAndChangedRemotely, .remote, .remoteMissing:
                    actions.append(ItemAction(type: .retrieveMetadata))

                case .none:
                    break
                }
            }
            actions.append(ItemAction(type: .createParent))
        }

        // Add download/remove downloaded option for attachments
        switch location {
        case .local:
            actions.append(ItemAction(type: .removeDownload))

        case .remote:
            actions.append(ItemAction(type: .download))

        case .localAndChangedRemotely:
            actions.append(ItemAction(type: .download))
            actions.append(ItemAction(type: .removeDownload))

        case .none, .remoteMissing:
            break
        }

        if FeatureGates.enabled.contains(.documentWorkerDebugging), attachment?.supportsStructuredDocumentTextExtraction == true {
            actions.append(ItemAction(type: .getStructuredText))
        }

        if viewModel.state.library.metadataEditable {
            actions.append(ItemAction(type: .addToCollection))

            // Add removing from collection only if item is in current collection.
            if let key = viewModel.state.collection.identifier.key, item.collections.filter(.key(key)).first != nil {
                actions.append(ItemAction(type: .removeFromCollection))
            }

            if item.rawType != ItemTypes.note && item.rawType != ItemTypes.attachment {
                actions.append(ItemAction(type: .duplicate))
            }
            actions.append(ItemAction(type: .trash))
        }

        if case .custom(.recentlyRead) = viewModel.state.collection.identifier {
            let index = actions.last?.type == .trash ? actions.count - 1 : actions.count
            actions.insert(ItemAction(type: .removeFromRecentlyRead), at: index)
        }

        #if DEBUG
        if let attachment, case .file(_, let contentType, _, _, _) = attachment.type, contentType == "application/epub+zip" || contentType == "text/html" {
            actions.append(ItemAction(type: .debugReader))
        }
        #endif

        return actions
    }
}

extension RItemsCollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ItemsCollectionViewHandler.cellId, for: indexPath)

        guard let item = item(at: indexPath.item) else {
            DDLogError("RItemsCollectionViewDataSource: indexPath.item (\(indexPath.item)) out of bounds (\(count))")
            return cell
        }

        if let model = model(for: item), let cell = cell as? ItemCell {
            cell.actionDelegate = handler
            cell.set(item: model)
        }

        return cell

        func model(for item: RItem) -> ItemCellModel? {
            // Create and cache attachment if needed
            viewModel.process(action: .cacheItemAccessory(item: item))

            let title = createTitleIfNeeded()
            let accessory = accessory(forKey: item.key)
            let typeName = schemaController.localized(itemType: item.rawType) ?? item.rawType
            return ItemCellModel(item: item, typeName: typeName, title: title, accessory: accessory, fileDownloader: fileDownloader, recognizerController: recognizerController)

            func createTitleIfNeeded() -> NSAttributedString {
                if let title = viewModel.state.itemTitles[item.key] {
                    return title
                } else {
                    viewModel.process(action: .cacheItemTitle(key: item.key, title: item.displayTitle))
                    return viewModel.state.itemTitles[item.key, default: NSAttributedString()]
                }
            }
        }
    }
}
