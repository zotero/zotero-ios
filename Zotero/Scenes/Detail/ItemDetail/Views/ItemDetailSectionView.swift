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
    @IBOutlet private weak var headerHeight: NSLayoutConstraint!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.topSeparatorHeight.constant = ItemDetailLayout.separatorHeight
        self.bottomSeparatorHeight.constant = ItemDetailLayout.separatorHeight
        self.headerHeight.constant = ItemDetailLayout.sectionHeaderHeight - ItemDetailLayout.separatorHeight
    }

    func setup(with title: String) {
        self.titleLabel.text = title
    }
}
