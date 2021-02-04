//
//  ItemDetailNoteCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ItemDetailNoteCell: UITableViewCell {
    @IBOutlet private weak var containerHeight: NSLayoutConstraint!
    @IBOutlet private weak var labelTop: NSLayoutConstraint!
    @IBOutlet private weak var labelLeft: NSLayoutConstraint!
    @IBOutlet private weak var label: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.containerHeight.constant = ItemDetailLayout.minCellHeight
    }

    func setup(with note: Note) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = ItemDetailLayout.lineHeight
        paragraphStyle.maximumLineHeight = ItemDetailLayout.lineHeight
        let attributedString = NSAttributedString(string: note.title,
                                                  attributes: [.font: UIFont.preferredFont(forTextStyle: .body),
                                                               .paragraphStyle: paragraphStyle])
        self.label.attributedText = attributedString

        let font = self.label.font!
        self.labelTop.constant = -(font.ascender - font.capHeight) - (ItemDetailLayout.lineHeight - font.lineHeight)
        self.labelLeft.constant = self.layoutMargins.left
    }
}
