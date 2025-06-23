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
            maxWidthConstraint.isActive = false
        }
    }

    var maxWidth: CGFloat? {
        didSet {
            guard let maxWidth else { return }
            maxWidthConstraint.isActive = true
            maxWidthConstraint.constant = maxWidth
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        roundBackground.layer.masksToBounds = true
        roundBackground.layer.borderWidth = 1
        roundBackground.layer.borderColor = Asset.Colors.zoteroBlueWithDarkMode.color.cgColor
        roundBackground.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.25)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        roundBackground.layer.cornerRadius = frame.height / 2
    }

    func set(selected: Bool) {
        roundBackground.isHidden = !selected
    }

    func setup(with text: String, color: UIColor, bolded: Bool, isActive: Bool) {
        label.text = text
        label.textColor = color
        label.alpha = isActive ? 1 : 0.55
        label.font = .preferredFont(for: .body, weight: bolded ? .medium : .regular)
        roundBackground.isHidden = !isSelected
        roundBackground.alpha = isActive ? 1 : 0.55
    }
}
