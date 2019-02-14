//
//  CollectionCell.swift
//  Zotero
//
//  Created by Michal Rentka on 14/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol CollectionCellModel {
    var name: String { get }
    var level: Int { get }
}

class CollectionCell: UITableViewCell {
    // Outlets
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var leftConstraint: NSLayoutConstraint!
    // Constants
    static let baseOffset: CGFloat = 20.0
    static let levelOffset: CGFloat = 30.0

    func setup(with model: CollectionCellModel) {
        self.titleLabel.text = model.name
        self.leftConstraint.constant = CollectionCell.baseOffset + (CGFloat(model.level) * CollectionCell.levelOffset)
    }
}
