//
//  ItemDetailAbstractContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAbstractContentView: UIView {
    @IBOutlet private weak var separatorHeight: NSLayoutConstraint!
    @IBOutlet private weak var titleTop: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleToContent: NSLayoutConstraint!
    @IBOutlet private weak var contentLabel: CollapsibleLabel!

    private static let paragraphStyle: NSMutableParagraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.hyphenationFactor = 1
        paragraphStyle.alignment = .justified
        paragraphStyle.minimumLineHeight = ItemDetailLayout.lineHeight
        paragraphStyle.maximumLineHeight = ItemDetailLayout.lineHeight
        return paragraphStyle
    }()

    private var titleFont: UIFont {
        return UIFont.preferredFont(for: .headline, weight: .regular)
    }

    private var bodyFont: UIFont {
        return UIFont.preferredFont(forTextStyle: .body)
    }

    private var showMoreLessFont: UIFont {
        return UIFont.systemFont(ofSize: 13)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.separatorHeight.constant = ItemDetailLayout.separatorHeight

        let titleFont = self.titleFont
        self.titleLabel.font = titleFont
        self.titleTop.constant = ItemDetailLayout.separatorHeight - (titleFont.ascender - titleFont.capHeight)

        let attributes: [NSAttributedString.Key: Any] = [.font: self.showMoreLessFont,
                                                         .foregroundColor: Asset.Colors.zoteroBlue.color,
                                                         .paragraphStyle: ItemDetailAbstractContentView.paragraphStyle]
        let showMore = NSMutableAttributedString(string: " ... ", attributes: [.font: self.bodyFont, .paragraphStyle: ItemDetailAbstractContentView.paragraphStyle])
        showMore.append(NSAttributedString(string: L10n.ItemDetail.showMore, attributes: attributes))

        self.contentLabel.collapsedNumberOfLines = 2
        self.contentLabel.showLessString = NSAttributedString(string: " \(L10n.ItemDetail.showLess)", attributes: attributes)
        self.contentLabel.showMoreString = showMore
    }

    func setup(with abstract: String, isCollapsed: Bool) {
        let font = self.bodyFont
        let attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: ItemDetailAbstractContentView.paragraphStyle, .font: font]
        let hyphenatedText = NSAttributedString(string: abstract, attributes: attributes)

        self.contentLabel.set(text: hyphenatedText, isCollapsed: isCollapsed)

        let lineHeightOffset = (ItemDetailLayout.lineHeight - font.lineHeight)
        self.titleToContent.constant = self.layoutMargins.top - (font.ascender - font.capHeight) - lineHeightOffset
    }
}
