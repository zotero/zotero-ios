//
//  CollectionCell.swift
//  Zotero
//
//  Created by Michal Rentka on 14/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CollectionCell: UITableViewCell {
    private static let imageWidth: CGFloat = 44
    private static let levelOffset: CGFloat = 16.0

    @IBOutlet private weak var leftConstraint: NSLayoutConstraint!
    @IBOutlet private weak var iconImage: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var badgeContainer: UIView!
    @IBOutlet private weak var badgeLabel: UILabel!
    // These 2 need to be strong because they are being activated/deactivated
    @IBOutlet private var rightConstraint: NSLayoutConstraint!
    @IBOutlet private var contentToBadgeConstraint: NSLayoutConstraint!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.badgeContainer.layer.masksToBounds = true
        self.badgeContainer.backgroundColor = self.badgeBackgroundColor
        self.rightConstraint.isActive = false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.badgeContainer.backgroundColor = self.badgeBackgroundColor
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        self.badgeContainer.layer.cornerRadius = self.badgeContainer.frame.height / 2.0
    }

    func updateBadge(for collection: Collection) {
        self.badgeContainer.isHidden = !self.shouldShowCount(for: collection)
        if !self.badgeContainer.isHidden {
            self.badgeLabel.text = "\(collection.itemCount)"
        }
        self.contentToBadgeConstraint.isActive = !self.badgeContainer.isHidden
        self.rightConstraint.isActive = self.badgeContainer.isHidden
    }

    func set(collection: Collection) {
        self.setup(with: collection)
        self.separatorInset = UIEdgeInsets(top: 0, left: self.separatorInset(for: collection.level), bottom: 0, right: 0)
    }

    func set(searchableCollection: SearchableCollection) {
        self.setup(with: searchableCollection.collection)
        self.contentView.alpha = searchableCollection.isActive ? 1 : 0.4
        self.separatorInset = UIEdgeInsets(top: 0, left: self.separatorInset(for: searchableCollection.collection.level), bottom: 0, right: 0)
    }

    private func setup(with collection: Collection) {
        self.iconImage.image = UIImage(named: collection.iconName)?.withRenderingMode(.alwaysTemplate)
        self.titleLabel.text = collection.name
        self.leftConstraint.constant = self.inset(for: collection.level)
        self.updateBadge(for: collection)
    }

    private func shouldShowCount(for collection: Collection) -> Bool {
        if collection.itemCount == 0 {
            return false
        }

        if Defaults.shared.showCollectionItemCount {
            return true
        }

        switch collection.type {
        case .custom(let type):
            return type == .all
        case .collection, .search:
            return false
        }
    }

    private func separatorInset(for level: Int) -> CGFloat {
        return self.inset(for: level) + CollectionCell.imageWidth
    }

    private func inset(for level: Int) -> CGFloat {
        let offset = CollectionCell.levelOffset
        return offset + (CGFloat(level) * offset)
    }

    private var badgeBackgroundColor: UIColor {
        return UIColor { traitCollection -> UIColor in
            return UIColor.systemGray.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.5 : 0.2)
        }
    }
}
