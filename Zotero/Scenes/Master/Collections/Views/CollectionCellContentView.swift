//
//  CollectionCellContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 07.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CollectionCellContentView: UIView {
    private weak var chevronButton: UIButton!
    private weak var chevronButtonHeightConstraint: NSLayoutConstraint!
    private weak var iconImageView: UIImageView!
    private weak var iconImageViewLeadingConstraint: NSLayoutConstraint!
    private weak var titleLabel: UILabel!
    private weak var badgeContainer: UIView!
    private weak var badgeLabel: UILabel!
    private weak var separatorView: UIView!
    // These 2 need to be strong because they are being activated/deactivated
    private var titleLabelTrailingConstraint: NSLayoutConstraint!
    private var badgeContainerLeadingConstraint: NSLayoutConstraint!

    private var toggleCollapsedAction: (() -> Void)?
    private var chevronCollapsed: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupViews()

        func setupViews() {
            let chevronButton = UIButton(type: .custom, primaryAction: UIAction { [weak self] _ in
                self?.toggleCollapsedAction?()
            })
            var chevronButtonConfiguration = UIButton.Configuration.plain()
            chevronButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            chevronButton.configuration = chevronButtonConfiguration
            chevronButton.configurationUpdateHandler = { [weak self] button in
                let collapsed = self?.chevronCollapsed ?? false
                var configuration = button.configuration
                configuration?.image = UIImage(systemName: collapsed ? "chevron.right" : "chevron.down")?.applyingSymbolConfiguration(.init(scale: .small))
                button.configuration = configuration
            }
            chevronButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(chevronButton)
            self.chevronButton = chevronButton

            let iconImageView = UIImageView()
            iconImageView.tintColor = Asset.Colors.zoteroBlue.color
            iconImageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconImageView)
            self.iconImageView = iconImageView

            let titleLabel = UILabel()
            titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(titleLabel)
            self.titleLabel = titleLabel

            let badgeContainer = UIView()
            if #available(iOS 26.0.0, *) {
                badgeContainer.backgroundColor = .clear
                badgeContainer.layer.masksToBounds = false
            } else {
                badgeContainer.backgroundColor = badgeBackgroundColor
                badgeContainer.layer.masksToBounds = true
            }
            badgeContainer.setContentHuggingPriority(.required, for: .horizontal)
            badgeContainer.setContentCompressionResistancePriority(.required, for: .horizontal)
            badgeContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badgeContainer)
            self.badgeContainer = badgeContainer

            let badgeLabel = UILabel()
            if #available(iOS 26.0.0, *) {
                badgeLabel.font = UIFont.preferredFont(forTextStyle: .body)
                badgeLabel.textAlignment = .right
                badgeLabel.textColor = .secondaryLabel
            } else {
                badgeLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
                badgeLabel.textAlignment = .center
            }
            badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
            badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            badgeContainer.addSubview(badgeLabel)
            self.badgeLabel = badgeLabel

            let separatorView = UIView()
            separatorView.backgroundColor = UIColor.separator
            separatorView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(separatorView)
            self.separatorView = separatorView

            let chevronButtonHeightConstraint = chevronButton.heightAnchor.constraint(equalToConstant: 52)
            let iconImageViewLeadingConstraint = iconImageView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 32)
            let titleLabelTrailingConstraint = safeAreaLayoutGuide.trailingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16)
            let badgeContainerLeadingConstraint = badgeContainer.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16)
            self.chevronButtonHeightConstraint = chevronButtonHeightConstraint
            self.iconImageViewLeadingConstraint = iconImageViewLeadingConstraint
            self.titleLabelTrailingConstraint = titleLabelTrailingConstraint
            self.badgeContainerLeadingConstraint = badgeContainerLeadingConstraint

            if #available(iOS 26.0.0, *) {
                NSLayoutConstraint.activate([
                    chevronButton.topAnchor.constraint(equalTo: topAnchor),
                    bottomAnchor.constraint(equalTo: chevronButton.bottomAnchor),
                    chevronButton.widthAnchor.constraint(equalToConstant: 48),
                    chevronButtonHeightConstraint,
                    iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    iconImageViewLeadingConstraint,
                    iconImageView.leadingAnchor.constraint(equalTo: chevronButton.trailingAnchor, constant: -4),
                    iconImageView.widthAnchor.constraint(equalToConstant: 28),
                    iconImageView.heightAnchor.constraint(equalToConstant: 28),
                    titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                    titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
                    badgeContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                    layoutMarginsGuide.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: 8),
                    badgeContainerLeadingConstraint,
                    badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor),
                    badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor),
                    badgeContainer.trailingAnchor.constraint(equalTo: badgeLabel.trailingAnchor),
                    badgeContainer.bottomAnchor.constraint(equalTo: badgeLabel.bottomAnchor),
                    separatorView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                    layoutMarginsGuide.trailingAnchor.constraint(equalTo: separatorView.trailingAnchor, constant: 8),
                    separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
                    separatorView.heightAnchor.constraint(equalToConstant: 1)
                ])
            } else {
                chevronButtonHeightConstraint.constant = 44
                NSLayoutConstraint.activate([
                    chevronButton.topAnchor.constraint(equalTo: topAnchor),
                    bottomAnchor.constraint(equalTo: chevronButton.bottomAnchor),
                    chevronButton.widthAnchor.constraint(equalToConstant: 48),
                    chevronButtonHeightConstraint,
                    iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                    iconImageViewLeadingConstraint,
                    iconImageView.leadingAnchor.constraint(equalTo: chevronButton.trailingAnchor, constant: -4),
                    iconImageView.widthAnchor.constraint(equalToConstant: 28),
                    iconImageView.heightAnchor.constraint(equalToConstant: 28),
                    titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                    titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 16),
                    badgeContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
                    layoutMarginsGuide.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor),
                    badgeContainerLeadingConstraint,
                    badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor, constant: 2),
                    badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 8),
                    badgeContainer.trailingAnchor.constraint(equalTo: badgeLabel.trailingAnchor, constant: 8),
                    badgeContainer.bottomAnchor.constraint(equalTo: badgeLabel.bottomAnchor, constant: 2),
                    separatorView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                    separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
                    separatorView.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
                ])
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if #unavailable(iOS 26.0.0) {
            badgeContainer.layer.cornerRadius = badgeContainer.frame.height / 2.0
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if #available(iOS 26.0.0, *) {
            switch traitCollection.splitViewControllerLayoutEnvironment {
            case .expanded:
                chevronButtonHeightConstraint.constant = 52
                separatorView.isHidden = true

            case .collapsed:
                chevronButtonHeightConstraint.constant = 44
                separatorView.isHidden = false

            case .none:
                break

            @unknown default:
                break
            }
        }
    }

    private func set(collapsed: Bool) {
        chevronCollapsed = collapsed
        chevronButton.setNeedsUpdateConfiguration()
        chevronButton.accessibilityLabel = collapsed ? L10n.Accessibility.Collections.expand : L10n.Accessibility.Collections.collapse
    }

    func set(collection: Collection, hasChildren: Bool, isCollapsed: Bool, accessories: CollectionCell.Accessories, toggleCollapsed: (() -> Void)?) {
        toggleCollapsedAction = toggleCollapsed
        iconImageViewLeadingConstraint.constant = accessories.contains(.chevron) ? 32 : 8

        setup(with: collection)
        updateBadgeView(for: accessories.contains(.badge) ? collection.itemCount : 0)
        setupChevron(visible: (accessories.contains(.chevron) && hasChildren), isCollapsed: isCollapsed)
    }

    func set(libraryName: String, isCollapsed: Bool, accessories: CollectionCell.Accessories, toggleCollapsed: (() -> Void)?) {
        toggleCollapsedAction = toggleCollapsed
        iconImageViewLeadingConstraint.constant = accessories.contains(.chevron) ? 32 : 8

        iconImageView.image = Asset.Images.Cells.library.image.withRenderingMode(.alwaysTemplate)
        titleLabel.text = libraryName

        updateBadgeView(for: 0)
        setupChevron(visible: accessories.contains(.chevron), isCollapsed: isCollapsed)
    }

    func updateBadgeView(for itemCount: Int) {
        badgeContainer.isHidden = (itemCount == 0)
        if !badgeContainer.isHidden {
            badgeLabel.text = "\(itemCount)"
            badgeLabel.accessibilityLabel = "\(itemCount) \(L10n.Accessibility.Collections.items)"
        }
        badgeContainerLeadingConstraint.isActive = !badgeContainer.isHidden || !chevronButton.isHidden
        titleLabelTrailingConstraint.isActive = !badgeContainerLeadingConstraint.isActive
    }

    private func setupChevron(visible: Bool, isCollapsed: Bool) {
        chevronButton.isHidden = !visible
        if visible {
            set(collapsed: isCollapsed)
        }
    }

    private func setup(with collection: Collection) {
        iconImageView.image = UIImage(named: collection.iconName)?.withRenderingMode(.alwaysTemplate)
        titleLabel.text = collection.name
        titleLabel.accessibilityLabel = collection.name
    }

    private var badgeBackgroundColor: UIColor {
        return UIColor { traitCollection -> UIColor in
            return .systemGray.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.5 : 0.2)
        }
    }

    func updateTitleLabel(emphasized: Bool) {
        if emphasized {
            titleLabel.textColor = Asset.Colors.zoteroBlueWithDarkMode.color
            var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            descriptor = descriptor.withSymbolicTraits(.traitBold) ?? descriptor
            titleLabel.font = UIFont(descriptor: descriptor, size: 0)
        } else {
            titleLabel.textColor = nil
            titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        }
    }
}
