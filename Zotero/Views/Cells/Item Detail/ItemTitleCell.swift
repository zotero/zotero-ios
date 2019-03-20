//
//  ItemTitleCell.swift
//  Zotero
//
//  Created by Michal Rentka on 20/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemTitleCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!

    func setup(with title: String) {
        self.titleLabel?.text = title
    }
}
