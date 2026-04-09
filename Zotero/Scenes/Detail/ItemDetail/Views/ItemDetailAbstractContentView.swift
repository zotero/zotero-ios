//
//  ItemDetailAbstractContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAbstractContentView: UIView {
    @IBOutlet private weak var titleTop: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!

    private var contentTextView: CollapsibleTextView!
    private var titleToContent: NSLayoutConstraint!
    var toggleCollapse: (() -> Void)?

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

        let titleFont = self.titleFont
        self.titleLabel.font = titleFont
        self.titleTop.constant = ItemDetailLayout.separatorHeight - (titleFont.ascender - titleFont.capHeight)

        setupContentTextView()
    }

    private func setupContentTextView() {
        let textView = CollapsibleTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentHuggingPriority(.init(1000), for: .horizontal)
        textView.setContentHuggingPriority(.init(750), for: .vertical)
        textView.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        textView.setContentCompressionResistancePriority(.init(1000), for: .vertical)
        addSubview(textView)

        titleToContent = textView.topAnchor.constraint(equalTo: titleLabel.lastBaselineAnchor, constant: 15)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            titleToContent,
            layoutMarginsGuide.bottomAnchor.constraint(equalTo: textView.bottomAnchor)
        ])

        textView.onToggle = { [weak self] in
            self?.toggleCollapse?()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: showMoreLessFont,
            .foregroundColor: Asset.Colors.zoteroBlue.color,
            .paragraphStyle: ItemDetailAbstractContentView.paragraphStyle
        ]

        let showMore = NSMutableAttributedString(
            string: " ... ",
            attributes: [.font: bodyFont, .paragraphStyle: ItemDetailAbstractContentView.paragraphStyle]
        )
        let showMoreLink = NSMutableAttributedString(string: L10n.ItemDetail.showMore, attributes: attributes)
        showMoreLink.addAttribute(.link, value: CollapsibleTextView.toggleURL, range: NSRange(location: 0, length: showMoreLink.length))
        showMore.append(showMoreLink)

        let showLessLink = NSMutableAttributedString(string: " \(L10n.ItemDetail.showLess)", attributes: attributes)
        showLessLink.addAttribute(.link, value: CollapsibleTextView.toggleURL, range: NSRange(location: 0, length: showLessLink.length))

        textView.collapsedNumberOfLines = 2
        textView.showLessString = showLessLink
        textView.showMoreString = showMore

        contentTextView = textView
    }

    func setup(with abstract: String, isCollapsed: Bool, maxWidth: CGFloat) {
        let font = self.bodyFont
        let attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: ItemDetailAbstractContentView.paragraphStyle, .font: font]
        let hyphenatedText = NSAttributedString(string: abstract, attributes: attributes)

        self.contentTextView.set(text: hyphenatedText, isCollapsed: isCollapsed, maxWidth: maxWidth)

        let lineHeightOffset = (ItemDetailLayout.lineHeight - font.lineHeight)
        self.titleToContent.constant = ceil(self.layoutMargins.top - (font.ascender - font.capHeight) - lineHeightOffset)
    }
}
