//
//  ItemDetailAddCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAddCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!

    func setup(with title: String) {
        self.titleLabel.text = title
    }
}
