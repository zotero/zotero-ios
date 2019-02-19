//
//  ItemFieldCell.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol ItemFieldCellModel {
    var title: String { get }
    var value: String { get }
}

class ItemFieldCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var valueLabel: UILabel!

    func setup(with model: ItemFieldCellModel) {
        self.titleLabel.text = model.title
        self.valueLabel.text = model.value
    }
}
