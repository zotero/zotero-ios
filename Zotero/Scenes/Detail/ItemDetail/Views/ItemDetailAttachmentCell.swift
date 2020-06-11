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
        let data = FileAttachmentViewData(contentType: attachment.contentType, progress: progress, error: error)
        if let data = data {
            self.fileView.set(data: data)
        } else {
            switch attachment.contentType {
            case .file: break // handled above
            case .url:
                self.attachmentIcon.image = UIImage(named: "web-page")
            }
        }
        self.fileView.isHidden = data == nil
        self.attachmentIcon.isHidden = data != nil
        self.label.text = attachment.title
    }

    func set(fileData: FileAttachmentViewData) {
        self.fileView.isHidden = false
        self.attachmentIcon.isHidden = true
        self.fileView.set(data: fileData)
    }
}
