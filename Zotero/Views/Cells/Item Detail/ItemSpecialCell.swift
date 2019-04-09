//
//  ItemSpecialCell.swift
//  Zotero
//
//  Created by Michal Rentka on 20/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol ItemSpecialCellModel {
    var title: String { get }
    var specialIcon: UIImage? { get }
    var tintColor: UIColor? { get }
}

class ItemSpecialCell: UITableViewCell {
    @IBOutlet private weak var iconView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var progressView: UIProgressView!
    @IBOutlet private weak var downloadIndicator: UIImageView!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    func setProgress(_ progress: Float) {
        self.progressView.progress = progress
        self.progressView.isHidden = progress == 0
        if progress > 0 {
            self.downloadIndicator.isHidden = true
        }
    }

    func setAttachmentType(_ type: ItemDetailStore.StoreState.AttachmentType) {
        switch type {
        case .file(_, let isLocal):
            self.downloadIndicator.isHidden = isLocal
            self.accessoryType = isLocal ? .disclosureIndicator : .none

        case .url:
            self.downloadIndicator.isHidden = true
            self.accessoryType = .disclosureIndicator
        }
    }

    func setup(with model: ItemSpecialCellModel) {
        self.iconView.image = model.specialIcon
        self.titleLabel.text = model.title

        self.downloadIndicator.isHidden = true
        self.accessoryType = .none

        if let color = model.tintColor {
            self.iconView.tintColor = color
            self.titleLabel.textColor = color
        } else {
            self.iconView.tintColor = self.contentView.tintColor
            self.titleLabel.textColor = .black
        }
    }
}
