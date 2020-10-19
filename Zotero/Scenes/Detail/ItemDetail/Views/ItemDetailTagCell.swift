//
//  ItemDetailTagCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailTagCell: UITableViewCell {
    @IBOutlet private weak var tagView: UIView!
    @IBOutlet private weak var label: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.tagView.layer.cornerRadius = self.tagView.frame.width / 2
        self.tagView.layer.masksToBounds = true
    }

    func setup(with tag: Tag, showEmptyTagCircle: Bool = true) {
        let (color, style) = TagColorGenerator.uiColor(for: tag.color)

        switch style {
        case .border:
            if showEmptyTagCircle {
                self.tagView.backgroundColor = .clear
                self.tagView.layer.borderWidth = 1
                self.tagView.layer.borderColor = color.cgColor
            } else {
                self.tagView.isHidden = true
            }
        case .filled:
            self.tagView.backgroundColor = color
            self.tagView.layer.borderWidth = 0
            self.tagView.isHidden = false
        }

        self.label.text = tag.name
    }
}
