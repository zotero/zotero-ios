//
//  TableViewDiffableDataSource.swift
//  Zotero
//
//  Created by Michal Rentka on 08.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class TableViewDiffableDataSource<Section: Hashable, Row: Hashable>: UITableViewDiffableDataSource<Section, Row> {
    var canMoveRow: ((IndexPath) -> Bool)?
    var moveRow: ((IndexPath, IndexPath) -> Void)?
    var canEditRow: ((IndexPath) -> Bool)?
    var commitEditingStyle: ((UITableViewCell.EditingStyle, IndexPath) -> Void)?

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return self.canMoveRow?(indexPath) ?? false
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        self.moveRow?(sourceIndexPath, destinationIndexPath)
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return self.canEditRow?(indexPath) ?? false
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        self.commitEditingStyle?(editingStyle, indexPath)
    }
}
