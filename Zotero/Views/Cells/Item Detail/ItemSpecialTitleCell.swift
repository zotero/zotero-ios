//
//  ItemSpecialTitleCell.swift
//  Zotero
//
//  Created by Michal Rentka on 20/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemSpecialTitleCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!

    func setup(with title: String, showAddButton: Bool) {
        self.titleLabel.text = title
    }
}
