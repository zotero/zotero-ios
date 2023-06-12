//
//  ItemCell.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

final class ItemCell: UITableViewCell {
    @IBOutlet private weak var typeImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleLabelsToContainerBottom: NSLayoutConstraint!
    @IBOutlet private weak var subtitleLabel: InsetLabel!
    @IBOutlet private weak var tagCircles: TagCirclesView!
    @IBOutlet private weak var noteIcon: UIImageView!
    @IBOutlet private weak var accessoryContainer: UIView!
    @IBOutlet private weak var fileView: FileAttachmentView!
    @IBOutlet private weak var accessoryImageView: UIImageView!
    @IBOutlet private weak var accessoryContainerRight: NSLayoutConstraint!

    private static let noAccessoryTrailingInset: CGFloat = 16

    var key: String = ""
    private var tagBorderColor: CGColor {
        return self.traitCollection.userInterfaceStyle == .dark ? UIColor.black.cgColor : UIColor.white.cgColor
    }
    private var highlightColor: UIColor? {
        return self.isEditing ? self.multipleSelectionBackgroundView?.backgroundColor :
                                self.selectedBackgroundView?.backgroundColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.key = ""
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.accessoryType = .detailButton

        let font = UIFont.preferredFont(for: .headline, weight: .regular)
        self.titleLabel.font = font
        self.titleLabelsToContainerBottom.constant = 12 + ItemDetailLayout.separatorHeight // + bottom separator
        self.fileView.contentInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        self.tagCircles.borderColor = self.tagBorderColor

        self.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 0)
        
        let highlightView = UIView()
        highlightView.backgroundColor = Asset.Colors.cellHighlighted.color
        self.selectedBackgroundView = highlightView

        let selectionView = UIView()
        selectionView.backgroundColor = Asset.Colors.cellSelected.color
        self.multipleSelectionBackgroundView = selectionView
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        self.tagCircles.borderColor = self.tagBorderColor
        self.fileView.set(backgroundColor: self.backgroundColor)
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)

        if highlighted {
            guard let highlightColor = self.highlightColor else { return }
            self.fileView.set(backgroundColor: highlightColor)
            self.tagCircles.borderColor = highlightColor.cgColor
        } else {
            self.fileView.set(backgroundColor: self.backgroundColor)
            self.tagCircles.borderColor = self.tagBorderColor
        }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        if selected {
            guard let highlightColor = self.highlightColor else { return }
            self.fileView.set(backgroundColor: highlightColor)
            self.tagCircles.borderColor = highlightColor.cgColor
        } else {
            self.fileView.set(backgroundColor: self.backgroundColor)
            self.tagCircles.borderColor = self.tagBorderColor
        }
    }

    func set(item: ItemCellModel) {
        self.key = item.key

        self.typeImageView.image = UIImage(named: item.typeIconName)
        self.titleLabel.text = item.title.isEmpty ? " " : item.title
        self.titleLabel.accessibilityLabel = self.titleAccessibilityLabel(for: item)
        self.subtitleLabel.text = item.subtitle.isEmpty ? " " : item.subtitle
        self.subtitleLabel.accessibilityLabel = item.subtitle
        // The label adds extra horizontal spacing so there is a negative right inset so that the label ends where the text ends exactly.
        // The note icon is rectangular and has 1px white space on each side, so it needs an extra negative pixel when there are no tags.
        self.subtitleLabel.rightInset = item.tagColors.isEmpty ? -2 : -1
        self.subtitleLabel.isHidden = item.subtitle.isEmpty && (item.hasNote || !item.tagColors.isEmpty)
        self.noteIcon.isHidden = !item.hasNote
        self.noteIcon.isAccessibilityElement = false

        self.tagCircles.isHidden = item.tagColors.isEmpty
        self.tagCircles.isAccessibilityElement = false
        if !self.tagCircles.isHidden {
            self.tagCircles.colors = item.tagColors
        }

        self.set(accessory: item.accessory)
    }

    func set(accessory: ItemCellModel.Accessory?) {
        guard let accessory = accessory else {
            self.accessoryContainer.isHidden = true
            self.accessoryContainerRight.constant = ItemCell.noAccessoryTrailingInset - self.accessoryContainer.frame.width
            return
        }

        self.accessoryContainer.isHidden = false
        self.accessoryContainerRight.constant = 0

        switch accessory {
        case .attachment(let state):
            self.fileView.set(state: state, style: .list)
            self.fileView.isHidden = false
            self.accessoryImageView.isHidden = true
        case .doi, .url:
            self.fileView.isHidden = true
            self.accessoryImageView.isHidden = false
            self.accessoryImageView.image = Asset.Images.Attachments.listLink.image
        }
    }

    private func titleAccessibilityLabel(for item: ItemCellModel) -> String {
        let title = item.title.isEmpty ? L10n.Accessibility.untitled : item.title
        return item.typeName + ", " + title
    }
}
