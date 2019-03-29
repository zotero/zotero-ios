//
//  ItemSpecialCell.swift
//  Zotero
//
//  Created by Michal Rentka on 20/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol ItemSpecialCellModel {
    var title: String { get }
    var specialIcon: UIImage? { get }
    var tintColor: UIColor? { get }
}

class ItemSpecialCell: UITableViewCell {
    @IBOutlet private weak var iconView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    func setup(with model: ItemSpecialCellModel) {
        self.iconView.image = model.specialIcon
        self.titleLabel.text = model.title

        if let color = model.tintColor {
            self.iconView.tintColor = color
            self.titleLabel.textColor = color
        } else {
            self.iconView.tintColor = self.contentView.tintColor
            self.titleLabel.textColor = .black
        }
    }
}
