//
//  ItemDetailAddContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAddContentView: UIView {
    @IBOutlet private weak var titleTop: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleBottom: NSLayoutConstraint!

    private static let verticalInset: CGFloat = 11

    func setup(with title: String) {
        self.titleLabel.text = title
        self.titleTop.constant = ItemDetailAddContentView.verticalInset - ItemDetailLayout.separatorHeight
        self.titleBottom.constant = ItemDetailAddContentView.verticalInset - ItemDetailLayout.separatorHeight
    }
}
