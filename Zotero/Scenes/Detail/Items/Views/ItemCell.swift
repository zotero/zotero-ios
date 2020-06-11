//
//  ItemCell.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemCell: UITableViewCell {
    @IBOutlet private weak var typeImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var subtitleLabel: UILabel!
    @IBOutlet private weak var tagCircles: TagCirclesView!
    @IBOutlet private weak var noteIcon: UIImageView!
    @IBOutlet private weak var fileView: FileAttachmentView!

    override func prepareForReuse() {
        super.prepareForReuse()
        self.fileView.tapAction = nil
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
        self.fileView.contentInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 15)
    }

    func set(item: ItemCellModel, tapAction: @escaping () -> Void) {
        self.fileView.tapAction = tapAction

        self.typeImageView.image = UIImage(named: item.typeIconName)
        self.titleLabel.text = item.title.isEmpty ? " " : item.title
        self.subtitleLabel.text = item.subtitle.isEmpty ? " " : item.subtitle
        self.subtitleLabel.isHidden = item.subtitle.isEmpty && (item.hasNote || !item.tagColors.isEmpty)
        self.noteIcon.isHidden = !item.hasNote

        self.tagCircles.isHidden = item.tagColors.isEmpty
        if !self.tagCircles.isHidden {
            self.tagCircles.colors = item.tagColors
        }

        if let (contentType, progress, error) = item.attachment {
            self.fileView.set(contentType: contentType, progress: progress, error: error)
            self.fileView.isHidden = false
        } else {
            self.fileView.isHidden = true
        }
    }

    func set(contentType: Attachment.ContentType, progress: CGFloat?, error: Error?) {
        self.fileView.set(contentType: contentType, progress: progress, error: error)
        self.fileView.isHidden = false
    }
}
