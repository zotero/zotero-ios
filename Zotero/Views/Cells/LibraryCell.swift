//
//  LibraryCell.swift
//  Zotero
//
//  Created by Michal Rentka on 16/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class LibraryCell: UITableViewCell {
    @IBOutlet private weak var iconView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.iconView.image = UIImage(named: "icon_cell_library")?.withRenderingMode(.alwaysTemplate)
    }

    func setup(with title: String) {
        self.titleLabel.text = title
    }
}
