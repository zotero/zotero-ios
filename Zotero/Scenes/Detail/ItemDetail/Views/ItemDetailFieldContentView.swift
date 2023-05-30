//
//  ItemDetailFieldContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailFieldContentView: UIView {
    @IBOutlet private weak var titleWidth: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var valueTop: NSLayoutConstraint!
    @IBOutlet private weak var valueLabel: UILabel!
    @IBOutlet private weak var valueBottom: NSLayoutConstraint!
    @IBOutlet private weak var additionalInfoLabel: UILabel!
    @IBOutlet private weak var additionalInfoOffset: NSLayoutConstraint!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
    }

    func setup(with field: ItemDetailState.Field, titleWidth: CGFloat) {
        self.titleLabel.text = field.name
        self.titleWidth.constant = titleWidth
        self.setAdditionalInfo(value: field.additionalInfo?[.dateOrder])

        let value = field.additionalInfo?[.formattedDate] ?? field.value
        self.valueLabel.text = value.isEmpty ? " " : value
        if field.isTappable {
            self.valueLabel.textColor = Asset.Colors.zoteroBlue.color
            self.accessibilityTraits = .button
        } else {
            self.valueLabel.textColor = UIColor(dynamicProvider: { $0.userInterfaceStyle == .dark ? .white : .black })
            self.accessibilityTraits = []
        }

        self.setupInsets()
    }

    func setup(with creator: ItemDetailState.Creator, titleWidth: CGFloat) {
        self.titleLabel.text = creator.localizedType
        self.valueLabel.text = creator.name
        self.valueLabel.textColor = UIColor(dynamicProvider: { $0.userInterfaceStyle == .dark ? .white : .black })
        self.titleWidth.constant = titleWidth
        self.setAdditionalInfo(value: nil)
        self.setupInsets()
    }

    func setup(with date: String, title: String, titleWidth: CGFloat) {
        self.titleLabel.text = title
        self.valueLabel.text = date
        self.valueLabel.textColor = UIColor(dynamicProvider: { $0.userInterfaceStyle == .dark ? .white : .black })
        self.titleWidth.constant = titleWidth
        self.setAdditionalInfo(value: nil)
        self.setupInsets()
    }

    private func setAdditionalInfo(value: String?) {
        self.additionalInfoLabel.text = value
        self.additionalInfoOffset.constant = value == nil ? 0 : self.layoutMargins.right
    }

    private func setupInsets() {
        // Workaround for weird iOS bug, when layout margins are too short, the baseline is misaligned
        let needsOffset = self.layoutMargins.bottom == 10 && self.layoutMargins.top == 10
        self.valueTop.constant = self.valueLabel.font.capHeight - self.valueLabel.font.ascender - (needsOffset ? 1 : ItemDetailLayout.separatorHeight)
        self.valueBottom.constant = needsOffset ? -1 : 0//-ItemDetailLayout.separatorHeight
    }
}
