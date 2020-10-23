//
//  ItemDetailAbstractCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class ItemDetailAbstractCell: RxTableViewCell {
    @IBOutlet private weak var separatorHeight: NSLayoutConstraint!
    @IBOutlet private weak var titleTop: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleToContent: NSLayoutConstraint!
    @IBOutlet private weak var contentLabel: CollapsibleLabel!

    private static let lineHeight: CGFloat = 22
    private static let verticalInset: CGFloat = 15

    override func awakeFromNib() {
        super.awakeFromNib()

        self.separatorHeight.constant = 1 / UIScreen.main.scale

        let font = UIFont.preferredFont(for: .headline, weight: .regular)
        self.titleLabel.font = font
        self.titleTop.constant = ItemDetailAbstractCell.verticalInset - (font.ascender - font.capHeight)

        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13),
                                                         .foregroundColor: Asset.Colors.zoteroBlue.color]
        let showMore = NSMutableAttributedString(string: " ... ")
        showMore.append(NSAttributedString(string: L10n.ItemDetail.showMore, attributes: attributes))

        self.contentLabel.collapsedNumberOfLines = 2
        self.contentLabel.showLessString = NSAttributedString(string: L10n.ItemDetail.showLess, attributes: attributes)
        self.contentLabel.showMoreString = showMore
    }

    func setup(with abstract: String, isCollapsed: Bool) {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.hyphenationFactor = 1
        paragraphStyle.alignment = .justified
        paragraphStyle.minimumLineHeight = ItemDetailAbstractCell.lineHeight
        paragraphStyle.maximumLineHeight = ItemDetailAbstractCell.lineHeight
        let attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraphStyle, .font: font]
        let hyphenatedText = NSAttributedString(string: abstract, attributes: attributes)

        self.contentLabel.set(text: hyphenatedText, isCollapsed: isCollapsed)

        self.titleToContent.constant = ItemDetailAbstractCell.verticalInset - (font.ascender - font.capHeight) - (ItemDetailAbstractCell.lineHeight - font.lineHeight)
    }
}
