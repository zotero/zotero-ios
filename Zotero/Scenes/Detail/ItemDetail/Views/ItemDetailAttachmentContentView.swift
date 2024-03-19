//
//  ItemDetailAttachmentContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 03.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAttachmentContentView: UIView {
    @IBOutlet private(set) weak var fileView: FileAttachmentView!
    @IBOutlet private weak var attachmentIcon: UIImageView!
    @IBOutlet private weak var labelTop: NSLayoutConstraint!
    @IBOutlet private weak var labelLeft: NSLayoutConstraint!
    @IBOutlet private weak var label: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.heightAnchor.constraint(greaterThanOrEqualToConstant: ItemDetailLayout.minCellHeight).isActive = true
    }

    func setup(with attachment: Attachment, type: ItemDetailAttachmentCell.Kind) {
        switch attachment.type {
        case .file:
            self.fileView.isHidden = false
            self.fileView.set(backgroundColor: .systemBackground)
            self.attachmentIcon.isHidden = true

            switch type {
            case .default, .disabled:
                self.fileView.set(state: .ready(attachment.type), style: .detail)

            case .inProgress(let progress):
                self.fileView.set(state: .progress(progress), style: .detail)

            case .failed(let error):
                self.fileView.set(state: .failed(attachment.type, error), style: .detail)
            }

        case .url:
            self.fileView.isHidden = true
            self.attachmentIcon.isHidden = false
            self.attachmentIcon.image = Asset.Images.ItemTypes.webPage.image
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = ItemDetailLayout.lineHeight
        paragraphStyle.maximumLineHeight = ItemDetailLayout.lineHeight
        let attributedString = NSAttributedString(string: attachment.title,
                                                  attributes: [.font: UIFont.preferredFont(forTextStyle: .body),
                                                               .paragraphStyle: paragraphStyle])
        self.label.attributedText = attributedString

        let font = self.label.font!
        self.labelTop.constant = ceil(-(font.ascender - font.capHeight) - (ItemDetailLayout.lineHeight - font.lineHeight))
        self.labelLeft.constant = self.layoutMargins.left

        switch type {
        case .disabled:
            self.label.textColor = .placeholderText
            self.isUserInteractionEnabled = false

        default:
            self.label.textColor = .label
            self.isUserInteractionEnabled = true
        }

        self.setupAccessibility(for: attachment, type: type)
    }

    private func setupAccessibility(for attachment: Attachment, type: ItemDetailAttachmentCell.Kind) {
        switch type {
        case .disabled:
            self.accessibilityTraits = []
            self.accessibilityHint = nil

        case .failed:
            self.accessibilityTraits = .button
            self.accessibilityHint = L10n.error

        case .inProgress:
            self.accessibilityTraits = .button
            self.accessibilityHint = L10n.cancel

        case .default:
            switch attachment.type {
            case .file(_, _, let location, _):
                switch location {
                case .remoteMissing:
                    self.accessibilityTraits = []
                    self.accessibilityHint = nil

                case .remote, .localAndChangedRemotely:
                    self.accessibilityHint = L10n.Accessibility.ItemDetail.downloadAndOpen
                    self.accessibilityTraits = .button

                case .local:
                    self.accessibilityHint = L10n.Accessibility.ItemDetail.open
                    self.accessibilityTraits = .button
                }

            case .url:
                self.accessibilityHint = L10n.Accessibility.ItemDetail.open
                self.accessibilityTraits = .button
            }
        }
    }
}
