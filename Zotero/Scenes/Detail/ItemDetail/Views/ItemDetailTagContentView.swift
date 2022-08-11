//
//  ItemDetailTagContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailTagContentView: UIView {
    @IBOutlet private weak var tagView: UIView!
    @IBOutlet private weak var labelTop: NSLayoutConstraint!
    @IBOutlet private weak var label: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.tagView.layer.cornerRadius = self.tagView.frame.width / 2
        self.tagView.layer.masksToBounds = true
        self.labelTop.constant = self.label.font.capHeight - self.label.font.ascender
    }

    func setup(tag: Tag, isProcessing: Bool) {
        let (color, style) = TagColorGenerator.uiColor(for: tag.color)

        switch style {
        case .border:
            self.tagView.backgroundColor = .clear
            self.tagView.layer.borderWidth = 1
            self.tagView.layer.borderColor = color.cgColor
        case .filled:
            self.tagView.backgroundColor = color
            self.tagView.layer.borderWidth = 0
        }

        self.label.text = tag.name
        self.label.textColor = isProcessing ? .systemGray2 : .label
    }
}
