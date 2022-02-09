//
//  CollectionCellContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 07.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CollectionCellContentView: UIView {
    @IBOutlet private weak var iconImage: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var badgeContainer: UIView!
    @IBOutlet private weak var badgeLabel: UILabel!
    @IBOutlet private weak var chevronButton: UIButton!
    @IBOutlet private weak var leftConstraint: NSLayoutConstraint!
    @IBOutlet private weak var separatorHeight: NSLayoutConstraint!
    // These 2 need to be strong because they are being activated/deactivated
    @IBOutlet private var contentToRightConstraint: NSLayoutConstraint!
    @IBOutlet private var contentToBadgeConstraint: NSLayoutConstraint!

    private var toggleCollapsedAction: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()

        self.badgeContainer.layer.masksToBounds = true
        self.badgeContainer.backgroundColor = self.badgeBackgroundColor
        self.contentToRightConstraint.isActive = false
        self.chevronButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        self.separatorHeight.constant = 1 / UIScreen.main.scale
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.badgeContainer.layer.cornerRadius = self.badgeContainer.frame.height / 2.0
    }

    @IBAction private func toggleCollapsed() {
        self.toggleCollapsedAction?()
    }

    func set(collapsed: Bool) {
        let configuration = UIImage.SymbolConfiguration(scale: .small)
        let name = collapsed ? "chevron.right" : "chevron.down"
        self.chevronButton.setImage(UIImage(systemName: name, withConfiguration: configuration), for: .normal)
        self.chevronButton.accessibilityLabel = collapsed ? L10n.Accessibility.Collections.expand : L10n.Accessibility.Collections.collapse
    }

    func set(collection: Collection, hasChildren: Bool, isCollapsed: Bool, toggleCollapsed: (() -> Void)?) {
        self.leftConstraint.constant = 32
        self.toggleCollapsedAction = toggleCollapsed
        self.setup(with: collection, hasChildren: hasChildren, isCollapsed: isCollapsed, chevronButtonVisible: hasChildren)
    }

    func set(collection: Collection, hasChildren: Bool, isActive: Bool) {
        self.leftConstraint.constant = 8
        self.toggleCollapsedAction = nil
        self.setup(with: collection, hasChildren: hasChildren, isCollapsed: false, chevronButtonVisible: false)
        self.alpha = isActive ? 1 : 0.4
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

    private func setup(with collection: Collection, hasChildren: Bool, isCollapsed: Bool, chevronButtonVisible: Bool) {
        self.iconImage.image = UIImage(named: collection.iconName(hasChildren: hasChildren))?.withRenderingMode(.alwaysTemplate)
        self.titleLabel.text = collection.name
        self.titleLabel.accessibilityLabel = collection.name

        self.chevronButton.isHidden = !chevronButtonVisible
        if !self.chevronButton.isHidden {
            self.set(collapsed: isCollapsed)
        }

        self.updateBadgeView(for: collection)
    }

    private var badgeBackgroundColor: UIColor {
        return UIColor { traitCollection -> UIColor in
            return UIColor.systemGray.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.5 : 0.2)
        }
    }
}
