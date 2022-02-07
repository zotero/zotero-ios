//
//  CollectionCellContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 07.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CollectionCellContentView: UIView {
    private static let imageWidth: CGFloat = 44
    private static let baseOffset: CGFloat = 36.0
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
        self.chevronButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: CollectionCellContentView.levelOffset, bottom: 0, right: CollectionCellContentView.levelOffset)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.badgeContainer.layer.cornerRadius = self.badgeContainer.frame.height / 2.0
    }

    @IBAction private func toggleCollapsed() {
        self.toggleCollapsedAction?()
    }

    func set(collection: Collection, hasChildren: Bool, isCollapsed: Bool, toggleCollapsed: (() -> Void)?) {
        self.toggleCollapsedAction = toggleCollapsed
        self.setup(with: collection, hasChildren: hasChildren, isCollapsed: isCollapsed)
//        self.separatorInset = UIEdgeInsets(top: 0, left: self.separatorInset(for: collection.level), bottom: 0, right: 0)
    }

    func set(collection: Collection, hasChildren: Bool, isActive: Bool) {
        self.toggleCollapsedAction = nil
        self.setup(with: collection, hasChildren: hasChildren, isCollapsed: false)
        self.alpha = isActive ? 1 : 0.4
//        self.separatorInset = UIEdgeInsets(top: 0, left: self.separatorInset(for: searchableCollection.collection.level), bottom: 0, right: 0)
    }

    func updateBadgeView(for collection: Collection) {
        self.badgeContainer.isHidden = collection.itemCount == 0
        if !self.badgeContainer.isHidden {
            self.badgeLabel.text = "\(collection.itemCount)"
            self.badgeLabel.accessibilityLabel = "\(collection.itemCount) \(L10n.Accessibility.Collections.items)"
        }
        self.contentToBadgeConstraint.isActive = !self.badgeContainer.isHidden || !self.chevronButton.isHidden
        self.contentToRightConstraint.isActive = !self.contentToBadgeConstraint.isActive
    }

    private func setup(with collection: Collection, hasChildren: Bool, isCollapsed: Bool) {
        self.iconImage.image = UIImage(named: collection.iconName(hasChildren: hasChildren))?.withRenderingMode(.alwaysTemplate)
        self.titleLabel.text = collection.name
        self.titleLabel.accessibilityLabel = collection.name

//        self.leftConstraint.constant = self.inset(for: collection.level)
        self.chevronButton.isHidden = !hasChildren
        if !self.chevronButton.isHidden {
            let configuration = UIImage.SymbolConfiguration(scale: .small)
            let name = isCollapsed ? "chevron.right" : "chevron.down"
            self.chevronButton.setImage(UIImage(systemName: name, withConfiguration: configuration), for: .normal)
            self.chevronButton.accessibilityLabel = isCollapsed ? L10n.Accessibility.Collections.expand : L10n.Accessibility.Collections.collapse
        }

        self.updateBadgeView(for: collection)
    }

//    private func separatorInset(for level: Int) -> CGFloat {
//        return self.inset(for: level) + CollectionCellContentView.imageWidth
//    }
//
//    private func inset(for level: Int) -> CGFloat {
//        return CollectionCellContentView.baseOffset + (CGFloat(level) * CollectionCellContentView.levelOffset)
//    }

    private var badgeBackgroundColor: UIColor {
        return UIColor { traitCollection -> UIColor in
            return UIColor.systemGray.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.5 : 0.2)
        }
    }
}
