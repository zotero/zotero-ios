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
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var labelBottom: NSLayoutConstraint!

    private static let height: CGFloat = 44
    private static let verticalInset: CGFloat = 15
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
        let separatorHeight = (1 / UIScreen.main.scale)
        self.labelTop.constant = ItemDetailNoteCell.verticalInset - (font.ascender - font.capHeight) - (ItemDetailNoteCell.lineHeight - font.lineHeight) - separatorHeight
        self.labelBottom.constant = ItemDetailNoteCell.verticalInset
    }
}
