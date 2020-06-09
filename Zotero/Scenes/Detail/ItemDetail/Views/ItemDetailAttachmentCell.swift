//
//  ItemDetailAttachmentCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAttachmentCell: UITableViewCell {
    enum Accessory {
        case downloadIcon, progress(Double), disclosureIndicator, error
    }

    @IBOutlet private weak var icon: UIImageView!
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var accessory: UIImageView!
    @IBOutlet private weak var progressView: UIProgressView!

    func setup(with attachment: Attachment, progress: Double?, error: Error?) {
        self.icon.image = UIImage(named: attachment.iconName)
        self.label.text = attachment.title

        guard let accessory = self.accessory(for: attachment, progress: progress, error: error) else {
            self.accessory.isHidden = true
            self.progressView.isHidden = true
            return
        }

        var isProgress = false
        switch accessory {
        case .disclosureIndicator:
            self.accessory.image = UIImage(systemName: "chevron.right")
        case .downloadIcon:
            self.accessory.image = UIImage(systemName: "square.and.arrow.down")
        case .error:
            self.accessory.image = UIImage(systemName: "xmark.octagon")
        case .progress(let progress):
            self.progressView.progress = Float(progress)
            isProgress = true
        }
        self.accessory.isHidden = isProgress
        self.progressView.isHidden = !isProgress
    }

    private func accessory(for attachment: Attachment, progress: Double?, error: Error?) -> Accessory? {
        if error != nil {
            return .error
        }

        if let progress = progress {
            return .progress(progress)
        }

        switch attachment.type {
        case .file(_, _, let isLocal, let hasRemoteResource):
            return isLocal ? .disclosureIndicator : (hasRemoteResource ? .downloadIcon : nil)
        case .url:
            return .disclosureIndicator
        }
    }
}
