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

    weak var handler: ItemsTableViewHandler?
    private var snapshot: OrderedDictionary<TrashKey, TrashObject>?

    init(viewModel: ViewModel<TrashActionHandler>) {
        self.viewModel = viewModel
    }

    func apply(snapshot: OrderedDictionary<TrashKey, TrashObject>) {
        self.snapshot = snapshot
        handler?.reloadAll()
    }
}

extension TrashTableViewDataSource {
    var count: Int {
        return snapshot?.count ?? 0
    }

    var selectedItems: Set<String> {
        return []
    }

    func object(at index: Int) -> ItemsTableViewObject? {
        return trashObject(at: index)
    }

    private func trashObject(at index: Int) -> TrashObject? {
        guard let snapshot, index < snapshot.keys.count else { return nil }
        return snapshot.values[index]
    }

    func accessory(forKey key: String) -> ItemAccessory? {
        return nil
    }

    func tapAction(for indexPath: IndexPath) -> ItemsTableViewHandler.TapAction? {
        return nil
    }

    func createTrailingCellActions(at index: Int) -> [ItemAction]? {
        return nil
    }

    func createContextMenuActions(at index: Int) -> [ItemAction] {
        return []
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
            cell.set(item: ItemCellModel(object: object))

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
        case .item(_, let sortData):
            return sortData.type == ItemTypes.note

        case .collection:
            return false
        }
    }
    
    var isAttachment: Bool {
        switch type {
        case .item(_, let sortData):
            return sortData.type == ItemTypes.attachment

        case .collection:
            return false
        }
    }

    var libraryIdentifier: LibraryIdentifier {
        return libraryId
    }
}
