//
//  LookupItemCell.swift
//  Zotero
//
//  Created by Michal Rentka on 23.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class LookupItemCell: UITableViewCell {
    @IBOutlet private var typeImageView: UIImageView!
    @IBOutlet private var attachmentView: FileAttachmentView!
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var leftConstraint: NSLayoutConstraint!

    static let attachmentOffset: CGFloat = 30
    static let attachmentToLabelOffset: CGFloat = 20

    func set(title: String, type: String) {
        self.typeImageView.isHidden = false
        self.attachmentView.isHidden = true
        self.leftConstraint.constant = 0

        self.titleLabel.text = title
        self.typeImageView.image = UIImage(named: ItemTypes.iconName(for: type, contentType: nil))
    }

    func set(title: String, attachmentType: Attachment.Kind, update: RemoteAttachmentDownloader.Update.Kind) {
        self.typeImageView.isHidden = true
        self.attachmentView.isHidden = false
        self.leftConstraint.constant = LookupItemCell.attachmentOffset

        self.titleLabel.text = title

        switch update {
        case .ready:
            self.attachmentView.set(state: .ready(attachmentType), style: .lookup)
        case .failed, .cancelled:
            // Just assign any error, it doesn't matter here
            self.attachmentView.set(state: .failed(attachmentType, ZoteroApiError.unchanged), style: .lookup)
        case .progress(let progress):
            self.attachmentView.set(state: .progress(progress), style: .lookup)
        }
    }
}
