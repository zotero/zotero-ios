//
//  ItemDetailFieldCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class ItemDetailFieldCell: RxTableViewCell {
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

        self.valueLabel.text = field.value
        if field.isTappable {
            self.valueLabel.textColor = Asset.Colors.zoteroBlue.color
        } else {
            self.valueLabel.textColor = UIColor(dynamicProvider: { $0.userInterfaceStyle == .dark ? .white : .black })
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
        if let value = value {
            self.additionalInfoLabel.text = value
        } else {
            self.additionalInfoLabel.text = nil
        }
        self.additionalInfoOffset.constant = value == nil ? 0 : self.layoutMargins.right
    }

    private func setupInsets() {
        // Workaround for weird iOS bug, when layout margins are too short, the baseline is misaligned
        let needsOffset = self.layoutMargins.bottom == 10 && self.layoutMargins.top == 10
        self.valueTop.constant = self.valueLabel.font.capHeight - self.valueLabel.font.ascender - (needsOffset ? 1 : ItemDetailLayout.separatorHeight)
        self.valueBottom.constant = needsOffset ? -1 : -ItemDetailLayout.separatorHeight
    }
}
