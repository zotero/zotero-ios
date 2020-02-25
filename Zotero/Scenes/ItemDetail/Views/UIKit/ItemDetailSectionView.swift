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

    override func awakeFromNib() {
        super.awakeFromNib()
        self.titleLabel.font = UIFont.preferredFont(for: .title1, weight: .light)
    }

    func setup(with title: String) {
        self.titleLabel.text = title
    }
}
