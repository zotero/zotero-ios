//
//  ItemCell.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol ItemCellModel {
    var title: String { get }
    var creator: String? { get }
    var date: String? { get }
    var hasAttachment: Bool { get }
    var hasNote: Bool { get }
    var tagColors: [UIColor] { get }
    var icon: UIImage? { get }
}

class ItemCell: UITableViewCell {
    @IBOutlet private weak var iconView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var bottomStackView: UIStackView!
    @IBOutlet private weak var creatorLabel: UILabel!
    @IBOutlet private weak var noteIndicator: UIImageView!
    @IBOutlet private weak var attachmentIndicator: UIImageView!
    @IBOutlet private weak var colorsView: TagColorsView!

    static let height: CGFloat = 60

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    // MARK: - Setups

    func setup(with model: ItemCellModel) {
        self.iconView.image = model.icon
        self.titleLabel.text = model.title

        let colors = model.tagColors

        if model.creator == nil && model.date == nil &&
           !model.hasNote && !model.hasAttachment && colors.isEmpty {
            self.bottomStackView.isHidden = true
            return
        }

        self.bottomStackView.isHidden = false

        var subtitle = ""
        if let creator = model.creator {
            subtitle = "(\(creator)"
        }
        if let date = model.date {
            if subtitle.isEmpty {
                subtitle = "(\(date)"
            } else {
                subtitle += ", \(date)"
            }
        }
        if !subtitle.isEmpty {
            subtitle += ")"
            self.creatorLabel.text = subtitle
        } else {
            self.creatorLabel.text = nil
        }

        if !colors.isEmpty {
            self.colorsView.colors = colors
        }

        self.attachmentIndicator.isHidden = !model.hasAttachment
        self.noteIndicator.isHidden = !model.hasNote
        self.colorsView.isHidden = colors.isEmpty
    }
}
