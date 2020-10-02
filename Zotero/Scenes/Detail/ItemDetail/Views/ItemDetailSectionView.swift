//
//  ItemDetailSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailSectionView: UITableViewHeaderFooterView {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var topSeparatorHeight: NSLayoutConstraint!
    @IBOutlet private weak var bottomSeparatorHeight: NSLayoutConstraint!

    override func awakeFromNib() {
        super.awakeFromNib()

        let height = 1 / UIScreen.main.scale
        self.topSeparatorHeight.constant = height
        self.bottomSeparatorHeight.constant = height
    }

    func setup(with title: String) {
        self.titleLabel.text = title
    }
}
