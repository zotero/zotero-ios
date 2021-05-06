//
//  TagRow.swift
//  ZShare
//
//  Created by Michal Rentka on 06.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class TagRow: UIView {
    @IBOutlet private weak var tagView: UIView!
    @IBOutlet private weak var label: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.tagView.layer.cornerRadius = self.tagView.frame.width / 2
        self.tagView.layer.masksToBounds = true
    }

    func setup(with tag: Tag) {
        let (color, style) = TagColorGenerator.uiColor(for: tag.color)

        switch style {
        case .border:
            self.tagView.isHidden = true
        case .filled:
            self.tagView.backgroundColor = color
            self.tagView.isHidden = false
        }

        self.label.text = tag.name
    }
}
