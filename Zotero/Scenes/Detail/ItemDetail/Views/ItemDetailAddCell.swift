//
//  ItemDetailAddCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAddCell: UITableViewCell {
    @IBOutlet private weak var titleTop: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleBottom: NSLayoutConstraint!

    private static let verticalInset: CGFloat = 11

    func setup(with title: String) {
        self.titleLabel.text = title

        let separatorHeight = 1 / UIScreen.main.scale
        self.titleTop.constant = ItemDetailAddCell.verticalInset - separatorHeight
        self.titleBottom.constant = ItemDetailAddCell.verticalInset - separatorHeight
    }
}
