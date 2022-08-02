//
//  ItemDetailTitleContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ItemDetailTitleContentView: UIView {
    @IBOutlet private weak var textView: UITextView!
    @IBOutlet private weak var topConstraint: NSLayoutConstraint!
    @IBOutlet private weak var bottomConstraint: NSLayoutConstraint!
    @IBOutlet private weak var separatorHeight: NSLayoutConstraint!

    lazy var delegate: PlaceholderTextViewDelegate = {
        PlaceholderTextViewDelegate(placeholder: L10n.ItemDetail.untitled, menuItems: nil, textView: self.textView)
    }()

    override func awakeFromNib() {
        super.awakeFromNib()

        self.isAccessibilityElement = false

        self.separatorHeight.constant = ItemDetailLayout.separatorHeight

        self.textView.font = .preferredFont(forTextStyle: .title1)
        self.textView.delegate = self.delegate
        self.textView.isScrollEnabled = false
        self.textView.textContainerInset = UIEdgeInsets()
        self.textView.textContainer.lineFragmentPadding = 0

        let font = self.textView.font!
        self.topConstraint.constant = font.capHeight - font.ascender
        self.bottomConstraint.constant = -font.descender
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.delegate.layoutPlaceholder(in: self.textView)
    }

    func setup(with title: String, isEditing: Bool) {
        self.textView.isEditable = isEditing
        self.delegate.set(text: title, to: self.textView)
    }
}
