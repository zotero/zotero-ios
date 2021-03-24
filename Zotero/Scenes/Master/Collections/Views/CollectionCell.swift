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
    @IBOutlet private weak var chevronButton: UIButton!
    // These 2 need to be strong because they are being activated/deactivated
    @IBOutlet private var contentToRightConstraint: NSLayoutConstraint!
    @IBOutlet private var contentToBadgeConstraint: NSLayoutConstraint!

    private var toggleCollapsedAction: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()

        self.badgeContainer.layer.masksToBounds = true
        self.badgeContainer.backgroundColor = self.badgeBackgroundColor
        self.contentToRightConstraint.isActive = false
        self.chevronButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: CollectionCell.levelOffset, bottom: 0, right: CollectionCell.levelOffset)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.badgeContainer.backgroundColor = self.badgeBackgroundColor
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        self.badgeContainer.layer.cornerRadius = self.badgeContainer.frame.height / 2.0
    }

    @IBAction private func toggleCollapsed() {
        self.toggleCollapsedAction?()
    }

    func set(collection: Collection, toggleCollapsed: @escaping () -> Void) {
        self.toggleCollapsedAction = toggleCollapsed
        self.setup(with: collection)
        self.separatorInset = UIEdgeInsets(top: 0, left: self.separatorInset(for: collection.level), bottom: 0, right: 0)
    }

    func set(searchableCollection: SearchableCollection) {
        self.setup(with: searchableCollection.collection)
        self.contentView.alpha = searchableCollection.isActive ? 1 : 0.4
        self.separatorInset = UIEdgeInsets(top: 0, left: self.separatorInset(for: searchableCollection.collection.level), bottom: 0, right: 0)
    }

    func updateBadgeView(for collection: Collection) {
        self.badgeContainer.isHidden = !self.shouldShowCount(for: collection)
        if !self.badgeContainer.isHidden {
            self.badgeLabel.text = "\(collection.itemCount)"
        }
        self.contentToBadgeConstraint.isActive = !self.badgeContainer.isHidden || !self.chevronButton.isHidden
        self.contentToRightConstraint.isActive = !self.contentToBadgeConstraint.isActive
    }

    private func setup(with collection: Collection) {
        self.iconImage.image = UIImage(named: collection.iconName)?.withRenderingMode(.alwaysTemplate)
        self.titleLabel.text = collection.name

        self.leftConstraint.constant = self.inset(for: collection.level) - (self.chevronButton.isHidden ? CollectionCell.levelOffset : 0)
        self.chevronButton.isHidden = !collection.hasChildren
        if !self.chevronButton.isHidden {
            let configuration = UIImage.SymbolConfiguration(scale: .small)
            let name = collection.collapsed ? "chevron.right" : "chevron.down"
            self.chevronButton.setImage(UIImage(systemName: name, withConfiguration: configuration), for: .normal)
            self.leftConstraint.constant -= collection.collapsed ? 43 : 48
        }

        self.updateBadgeView(for: collection)
    }

    private func shouldShowCount(for collection: Collection) -> Bool {
        if collection.itemCount == 0 {
            return false
        }

        if Defaults.shared.showCollectionItemCount {
            return true
        }

        switch collection.identifier {
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
        return 48 + (CGFloat(level) * offset)
    }

    private var badgeBackgroundColor: UIColor {
        return UIColor { traitCollection -> UIColor in
            return UIColor.systemGray.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.5 : 0.2)
        }
    }
}
