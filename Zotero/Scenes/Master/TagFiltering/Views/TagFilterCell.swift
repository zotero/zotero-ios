//
//  TagFilterCell.swift
//  Zotero
//
//  Created by Michal Rentka on 14.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class TagFilterCell: UICollectionViewCell {
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var roundBackground: UIView!
    @IBOutlet private var maxWidthConstraint: NSLayoutConstraint! {
        didSet {
            self.maxWidthConstraint.isActive = false
        }
    }

    var maxWidth: CGFloat? = nil {
        didSet {
            guard let maxWidth = self.maxWidth else { return }
            self.maxWidthConstraint.isActive = true
            self.maxWidthConstraint.constant = maxWidth
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.roundBackground.layer.masksToBounds = true
        self.roundBackground.layer.borderWidth = 1
        self.roundBackground.layer.borderColor = Asset.Colors.zoteroBlueWithDarkMode.color.cgColor
        self.roundBackground.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.25)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.roundBackground.layer.cornerRadius = self.frame.height / 2
    }

    func set(selected: Bool) {
        self.roundBackground.isHidden = !selected
    }

    func setup(with text: String, color: UIColor) {
        self.label.text = text
        self.label.textColor = color
        self.roundBackground.isHidden = !self.isSelected
    }
}
