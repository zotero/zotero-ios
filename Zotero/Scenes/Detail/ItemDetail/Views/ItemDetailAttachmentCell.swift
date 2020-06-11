//
//  ItemDetailAttachmentCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAttachmentCell: UITableViewCell {
    @IBOutlet private weak var fileView: FileAttachmentView!
    @IBOutlet private weak var attachmentIcon: UIImageView!
    @IBOutlet private weak var label: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.fileView.tapEnabled = false
    }

    func setup(with attachment: Attachment, progress: CGFloat?, error: Error?) {
        switch attachment.contentType {
        case .file:
            self.fileView.set(contentType: attachment.contentType, progress: progress, error: error)
            self.fileView.isHidden = false
            self.attachmentIcon.isHidden = true
        case .url:
            self.attachmentIcon.image = UIImage(named: "web-page")
            self.fileView.isHidden = true
            self.attachmentIcon.isHidden = false
        }
        self.label.text = attachment.title
    }
}
