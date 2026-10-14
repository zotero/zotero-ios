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

    private var carPlayImage: UIImageView!
    // Strong because they are being activated/deactivated
    private var carPlayToBadgeConstraint: NSLayoutConstraint!
    private var carPlayToRightConstraint: NSLayoutConstraint!
    private var contentToCarPlayConstraint: NSLayoutConstraint!
    private var toggleCollapsedAction: (() -> Void)?
    private var chevronCollapsed: Bool = false

    override func awakeFromNib() {
        super.awakeFromNib()

        badgeContainer.layer.masksToBounds = true
        badgeContainer.backgroundColor = badgeBackgroundColor
        contentToRightConstraint.isActive = false
        setupCarPlayImage()
        separatorHeight.constant = 1 / UIScreen.main.scale
        var chevronConfig = UIButton.Configuration.plain()
        chevronConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        chevronButton.configuration = chevronConfig
        chevronButton.configurationUpdateHandler = { [weak self] button in
            let collapsed = self?.chevronCollapsed ?? false
            var configuration = button.configuration
            configuration?.image = UIImage(systemName: collapsed ? "chevron.right" : "chevron.down")?.applyingSymbolConfiguration(.init(scale: .small))
            button.configuration = configuration
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        badgeContainer.layer.cornerRadius = badgeContainer.frame.height / 2.0
    }

    @IBAction private func toggleCollapsed() {
        toggleCollapsedAction?()
    }

    private func set(collapsed: Bool) {
        chevronCollapsed = collapsed
        chevronButton.setNeedsUpdateConfiguration()
        chevronButton.accessibilityLabel = collapsed ? L10n.Accessibility.Collections.expand : L10n.Accessibility.Collections.collapse
    }

    func set(collection: Collection, hasChildren: Bool, isCollapsed: Bool, accessories: CollectionCell.Accessories, toggleCollapsed: (() -> Void)?) {
        toggleCollapsedAction = toggleCollapsed
        leftConstraint.constant = (accessories.contains(.chevron) || accessories.contains(.chevronSpace)) ? 32 : 8

        setup(with: collection)
        updateBadgeView(for: accessories.contains(.badge) ? collection.itemCount : 0)
        updateCarPlayImage(isVisible: collection.showsInCarPlay)
        setupChevron(visible: (accessories.contains(.chevron) && hasChildren), isCollapsed: isCollapsed)
    }

    func set(libraryName: String, isCollapsed: Bool, accessories: CollectionCell.Accessories, toggleCollapsed: (() -> Void)?) {
        toggleCollapsedAction = toggleCollapsed
        leftConstraint.constant = (accessories.contains(.chevron) || accessories.contains(.chevronSpace)) ? 32 : 8

        iconImage.image = Asset.Images.Cells.library.image.withRenderingMode(.alwaysTemplate)
        titleLabel.text = libraryName

        updateBadgeView(for: 0)
        updateCarPlayImage(isVisible: false)
        setupChevron(visible: accessories.contains(.chevron), isCollapsed: isCollapsed)
    }

    func updateBadgeView(for itemCount: Int) {
        badgeContainer.isHidden = itemCount == 0
        if !badgeContainer.isHidden {
            badgeLabel.text = "\(itemCount)"
            badgeLabel.accessibilityLabel = "\(itemCount) \(L10n.Accessibility.Collections.items)"
        }
        contentToBadgeConstraint.isActive = !self.badgeContainer.isHidden || !self.chevronButton.isHidden
        contentToRightConstraint.isActive = !self.contentToBadgeConstraint.isActive
    }

    /// Shows the CarPlay icon left of the badge, or at the right edge when there is no badge.
    private func updateCarPlayImage(isVisible: Bool) {
        carPlayImage.isHidden = !isVisible
        carPlayToBadgeConstraint.isActive = isVisible && !badgeContainer.isHidden
        carPlayToRightConstraint.isActive = isVisible && badgeContainer.isHidden
        contentToCarPlayConstraint.isActive = isVisible
    }

    private func setupCarPlayImage() {
        let imageView = UIImageView(image: UIImage(systemName: "car.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote)))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemGray
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = L10n.Accessibility.Collections.shownInCarplay
        imageView.isHidden = true
        addSubview(imageView)
        carPlayImage = imageView

        imageView.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor).isActive = true
        carPlayToBadgeConstraint = badgeContainer.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8)
        carPlayToRightConstraint = layoutMarginsGuide.trailingAnchor.constraint(equalTo: imageView.trailingAnchor)
        if let content = titleLabel.superview {
            contentToCarPlayConstraint = imageView.leadingAnchor.constraint(greaterThanOrEqualTo: content.trailingAnchor, constant: 16)
        } else {
            contentToCarPlayConstraint = imageView.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16)
        }
    }

    private func setupChevron(visible: Bool, isCollapsed: Bool) {
        chevronButton.isHidden = !visible
        if visible {
            set(collapsed: isCollapsed)
        }
    }

    private func setup(with collection: Collection) {
        iconImage.image = UIImage(named: collection.iconName)?.withRenderingMode(.alwaysTemplate)
        iconImage.alpha = collection.isAvailable ? 1 : 0.6
        titleLabel.text = collection.name
        titleLabel.accessibilityLabel = collection.name
        titleLabel.alpha = collection.isAvailable ? 1 : 0.6
    }

    private var badgeBackgroundColor: UIColor {
        return UIColor { traitCollection -> UIColor in
            return UIColor.systemGray.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.5 : 0.2)
        }
    }
}
