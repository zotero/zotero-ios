//
//  ItemDetailNoteCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailNoteCell: UITableViewCell {
    @IBOutlet private weak var containerHeight: NSLayoutConstraint!
    @IBOutlet private weak var labelTop: NSLayoutConstraint!
    @IBOutlet private weak var labelLeft: NSLayoutConstraint!
    @IBOutlet private weak var label: UILabel!

    private static let height: CGFloat = 44
    private static let lineHeight: CGFloat = 22

    override func awakeFromNib() {
        super.awakeFromNib()

        let separatorHeight = 1 / UIScreen.main.scale
        self.containerHeight.constant = ItemDetailNoteCell.height - separatorHeight
    }

    func setup(with note: Note) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = ItemDetailNoteCell.lineHeight
        paragraphStyle.maximumLineHeight = ItemDetailNoteCell.lineHeight
        let attributedString = NSAttributedString(string: note.title,
                                                  attributes: [.font: UIFont.preferredFont(forTextStyle: .body),
                                                               .paragraphStyle: paragraphStyle])
        self.label.attributedText = attributedString

        let font = self.label.font!
        self.labelTop.constant = -(font.ascender - font.capHeight) - (ItemDetailNoteCell.lineHeight - font.lineHeight)
        self.labelLeft.constant = self.layoutMargins.left
    }
}
