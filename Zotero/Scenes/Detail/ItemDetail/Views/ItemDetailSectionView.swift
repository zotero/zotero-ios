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

    private static let height: CGFloat = 44

    override func awakeFromNib() {
        super.awakeFromNib()

        let separatorHeight = 1 / UIScreen.main.scale
        self.topSeparatorHeight.constant = separatorHeight
        self.bottomSeparatorHeight.constant = separatorHeight
        self.headerHeight.constant = ItemDetailSectionView.height - separatorHeight
    }

    func setup(with title: String) {
        self.titleLabel.text = title
    }
}
