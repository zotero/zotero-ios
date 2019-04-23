//
//  ItemSpecialTitleCell.swift
//  Zotero
//
//  Created by Michal Rentka on 20/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemSpecialTitleCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var addButton: UIButton!

    private var addAction: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        self.addButton.setImage(UIImage(named: "icon_itemdetail_add")?.withRenderingMode(.alwaysTemplate), for: .normal)
    }

    @IBAction private func addTapped() {
        self.addAction?()
    }

    func setup(with title: String, showAddButton: Bool, addAction: (() -> Void)?) {
        self.titleLabel.text = title
        self.addButton.isHidden = !showAddButton
        if showAddButton {
            self.addAction = addAction
        } else {
            self.addAction = nil
        }
    }
}
