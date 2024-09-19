//
//  TrashTableViewDataSource.swift
//  Zotero
//
//  Created by Michal Rentka on 19.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import OrderedCollections

final class TrashTableViewDataSource: NSObject, ItemsTableViewDataSource {
    private let viewModel: ViewModel<TrashActionHandler>

    weak var handler: ItemsTableViewHandler?
    private var snapshot: OrderedDictionary<TrashKey, TrashObject>?

    init(viewModel: ViewModel<TrashActionHandler>) {
        self.viewModel = viewModel
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
        guard let snapshot, index < snapshot.keys.count else { return nil }
        return snapshot.values[index]
    }

    func accessory(forKey key: String) -> ItemAccessory? {
        <#code#>
    }

    func tapAction(for indexPath: IndexPath) -> ItemsTableViewHandler.TapAction? {
        <#code#>
    }

    func createTrailingCellActions(at index: Int) -> [ItemAction]? {
        <#code#>
    }

    func createContextMenuActions(at index: Int) -> [ItemAction] {
        <#code#>
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        <#code#>
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        <#code#>
    }
}

extension TrashObject: ItemsTableViewObject {
    var isNote: Bool {
        switch type {
        case .item(let cellData, let sortData):
            return sortData.type == ItemTypes.note

        case .collection:
            return false
        }
    }
    
    var isAttachment: Bool {
        switch type {
        case .item(let cellData, let sortData):
            return sortData.type == ItemTypes.attachment

        case .collection:
            return false
        }
    }
    
    var item: RItem? {
        return nil
    }
}
