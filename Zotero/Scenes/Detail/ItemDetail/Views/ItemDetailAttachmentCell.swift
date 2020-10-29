//
//  ItemDetailAttachmentCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAttachmentCell: UITableViewCell {
    @IBOutlet private weak var containerHeight: NSLayoutConstraint!
    @IBOutlet private weak var fileView: FileAttachmentView!
    @IBOutlet private weak var attachmentIcon: UIImageView!
    @IBOutlet private weak var labelTop: NSLayoutConstraint!
    @IBOutlet private weak var labelLeft: NSLayoutConstraint!
    @IBOutlet private weak var label: UILabel!

    private static let height: CGFloat = 44
    private static let lineHeight: CGFloat = 22

    override func awakeFromNib() {
        super.awakeFromNib()
        self.fileView.tapEnabled = false
        
        let highlightView = UIView()
        highlightView.backgroundColor = Asset.Colors.cellHighlighted.color
        self.selectedBackgroundView = highlightView

        let separatorHeight = 1 / UIScreen.main.scale
        self.containerHeight.constant = ItemDetailAttachmentCell.height - separatorHeight
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        
        self.fileView.set(backgroundColor: (highlighted ? self.selectedBackgroundView?.backgroundColor : self.backgroundColor))
    }

    func setup(with attachment: Attachment, progress: CGFloat?, error: Error?) {
        switch attachment.contentType {
        case .file, .snapshot:
            self.fileView.set(contentType: attachment.contentType, progress: progress, error: error, style: .detail)
            self.fileView.isHidden = false
            self.attachmentIcon.isHidden = true
        case .url:
            self.attachmentIcon.image = Asset.Images.ItemTypes.webPage.image
            self.fileView.isHidden = true
            self.attachmentIcon.isHidden = false
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = ItemDetailAttachmentCell.lineHeight
        paragraphStyle.maximumLineHeight = ItemDetailAttachmentCell.lineHeight
        let attributedString = NSAttributedString(string: attachment.title,
                                                  attributes: [.font: UIFont.preferredFont(forTextStyle: .body),
                                                               .paragraphStyle: paragraphStyle])
        self.label.attributedText = attributedString

        let font = self.label.font!
        self.labelTop.constant = -(font.ascender - font.capHeight) - (ItemDetailAttachmentCell.lineHeight - font.lineHeight)
        self.labelLeft.constant = self.layoutMargins.left
    }
}
