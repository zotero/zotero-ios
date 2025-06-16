//
//  ItemDetailFieldMultilineEditContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 04.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemDetailFieldMultilineEditContentView: UIView {
    @IBOutlet private weak var titleWidthConstraint: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var valueTextView: UITextView!
    @IBOutlet private weak var titleTopConstraint: NSLayoutConstraint!
    @IBOutlet private weak var textViewTopConstraint: NSLayoutConstraint!
    @IBOutlet private weak var bottomConstraint: NSLayoutConstraint!
    var textChanged: ((String) -> Void)?

    private static let textViewTapAreaOffset: CGFloat = 8

    override func awakeFromNib() {
        super.awakeFromNib()

        let valueFont = UIFont.preferredFont(forTextStyle: .body)

        titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
        valueTextView.font = valueFont

        titleTopConstraint.constant = valueFont.capHeight - valueFont.ascender
        textViewTopConstraint.constant = valueFont.capHeight - valueFont.ascender - ItemDetailFieldMultilineEditContentView.textViewTapAreaOffset
        bottomConstraint.constant = valueFont.descender - ItemDetailLayout.separatorHeight - ItemDetailFieldMultilineEditContentView.textViewTapAreaOffset

        valueTextView.delegate = self
        valueTextView.isScrollEnabled = false
        valueTextView.textContainerInset = UIEdgeInsets(
            top: ItemDetailFieldMultilineEditContentView.textViewTapAreaOffset,
            left: 0,
            bottom: ItemDetailFieldMultilineEditContentView.textViewTapAreaOffset,
            right: 0
        )
        valueTextView.textContainer.lineFragmentPadding = 0

        clipsToBounds = true
    }

    func setup(with field: ItemDetailState.Field, titleWidth: CGFloat) {
        titleLabel.text = field.name
        titleWidthConstraint.constant = titleWidth
        valueTextView.text = field.value
    }
}

extension ItemDetailFieldMultilineEditContentView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        textChanged?(textView.text)
    }
}
