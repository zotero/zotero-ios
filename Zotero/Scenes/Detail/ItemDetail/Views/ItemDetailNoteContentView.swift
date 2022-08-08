//
//  ItemDetailNoteContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailNoteContentView: UIView {
    @IBOutlet private weak var labelTop: NSLayoutConstraint!
    @IBOutlet private weak var labelLeft: NSLayoutConstraint!
    @IBOutlet private weak var label: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.accessibilityTraits = .button
        self.heightAnchor.constraint(greaterThanOrEqualToConstant: ItemDetailLayout.minCellHeight).isActive = true
    }

    func setup(with note: Note, isSaving: Bool) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = ItemDetailLayout.lineHeight
        paragraphStyle.maximumLineHeight = ItemDetailLayout.lineHeight
        let attributedString = NSAttributedString(string: note.title, attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .paragraphStyle: paragraphStyle])
        self.label.attributedText = attributedString
        self.label.textColor = isSaving ? .systemGray2 : .label

        let font = self.label.font!
        self.labelTop.constant = -(font.ascender - font.capHeight) - (ItemDetailLayout.lineHeight - font.lineHeight)
        self.labelLeft.constant = self.layoutMargins.left
    }
}
