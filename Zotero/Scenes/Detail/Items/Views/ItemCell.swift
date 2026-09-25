//
//  ItemCell.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

protocol ItemCellActionDelegate: AnyObject {
    func itemCellDidTapDetail(_ cell: ItemCell)
    func itemCellDidRequestOpen(_ cell: ItemCell) -> Bool
}

final class ItemCell: UICollectionViewListCell {
    private weak var typeImageView: UIImageView!
    private weak var titleLabel: UILabel!
    private weak var subtitleLabel: InsetLabel!
    private weak var tagCircles: TagEmojiCirclesView!
    private weak var noteIcon: UIImageView!
    private weak var accessoryContainer: UIView!
    private weak var fileView: FileAttachmentView!
    private weak var accessoryImageView: UIImageView!
    private weak var accessoryContainerRight: NSLayoutConstraint!

    private static let noAccessoryTrailingInset: CGFloat = 16
    private static let accessoryContainerHeight: CGFloat = 60
    private let accessoryContainerWidth: CGFloat

    weak var actionDelegate: ItemCellActionDelegate?
    var key: String = ""
    private var subtitleAnimator: UIViewPropertyAnimator?
    private var subtitlePrefix: String = ""
    private var subtitleAnimationSuffixDotCount = 0

    override func prepareForReuse() {
        super.prepareForReuse()
        actionDelegate = nil
        key = ""
        accessories = []
        subtitlePrefix = ""
        stopAnimatingSubtitle()
    }

    override init(frame: CGRect) {
        if #available(iOS 26.0.0, *) {
            accessoryContainerWidth = 56
        } else {
            accessoryContainerWidth = 60
        }
        super.init(frame: frame)

        setupViews()
        setupAccessibilityActions()

        if #available(iOS 26.0.0, *) {
            tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        }

        func setupViews() {
            let subtitleTextStyle: UIFont.TextStyle
            let horizontalSpacing: CGFloat
            if #available(iOS 26.0.0, *) {
                subtitleTextStyle = .subheadline
                horizontalSpacing = 12
            } else {
                subtitleTextStyle = .body
                horizontalSpacing = 16
            }

            clipsToBounds = true
            preservesSuperviewLayoutMargins = true
            indentationWidth = 10
            contentView.clipsToBounds = true
            contentView.contentMode = .center
            contentView.isMultipleTouchEnabled = true
            contentView.preservesSuperviewLayoutMargins = true
            contentView.insetsLayoutMarginsFromSafeArea = false

            let typeImageView = UIImageView()
            typeImageView.clipsToBounds = true
            typeImageView.contentMode = .scaleAspectFit
            typeImageView.adjustsImageSizeForAccessibilityContentSizeCategory = true
            typeImageView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(typeImageView)
            self.typeImageView = typeImageView

            let titleLabel = CapHeightLabel()
            titleLabel.text = " "
            titleLabel.font = .preferredFont(forTextStyle: .headline)
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.setContentHuggingPriority(.init(750), for: .horizontal)
            titleLabel.setContentHuggingPriority(.required, for: .vertical)
            titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            self.titleLabel = titleLabel

            let subtitleLabel = InsetLabel()
            subtitleLabel.text = " "
            subtitleLabel.font = .preferredFont(forTextStyle: subtitleTextStyle)
            subtitleLabel.textColor = .systemGray
            subtitleLabel.adjustsFontForContentSizeCategory = true
            subtitleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.setContentHuggingPriority(.required, for: .horizontal)
            subtitleLabel.setContentHuggingPriority(.required, for: .vertical)
            subtitleLabel.setContentCompressionResistancePriority(.init(250), for: .horizontal)
            subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            self.subtitleLabel = subtitleLabel

            let tagCircles = TagEmojiCirclesView()
            tagCircles.isHidden = true
            tagCircles.borderColor = tagBorderColor(for: configurationState)
            tagCircles.setContentHuggingPriority(.required, for: .horizontal)
            tagCircles.setContentCompressionResistancePriority(.required, for: .vertical)
            self.tagCircles = tagCircles

            let noteIcon = UIImageView(image: Asset.Images.Cells.note.image)
            noteIcon.isHidden = true
            noteIcon.clipsToBounds = true
            noteIcon.contentMode = .scaleAspectFit
            noteIcon.setContentHuggingPriority(.required, for: .horizontal)
            noteIcon.setContentHuggingPriority(.required, for: .vertical)
            noteIcon.setContentCompressionResistancePriority(.required, for: .horizontal)
            noteIcon.setContentCompressionResistancePriority(.required, for: .vertical)
            noteIcon.translatesAutoresizingMaskIntoConstraints = false
            self.noteIcon = noteIcon

            let subtitleStackView = UIStackView(arrangedSubviews: [subtitleLabel, tagCircles, noteIcon])
            subtitleStackView.alignment = .center
            subtitleStackView.spacing = 5
            subtitleStackView.setContentHuggingPriority(.init(750), for: .horizontal)
            subtitleStackView.setContentHuggingPriority(.required, for: .vertical)
            subtitleStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
            subtitleStackView.setContentCompressionResistancePriority(.required, for: .vertical)
            subtitleStackView.translatesAutoresizingMaskIntoConstraints = false

            let labelsContainer = UIView()
            labelsContainer.setContentHuggingPriority(.required, for: .vertical)
            labelsContainer.translatesAutoresizingMaskIntoConstraints = false
            labelsContainer.addSubview(titleLabel)
            labelsContainer.addSubview(subtitleStackView)
            contentView.addSubview(labelsContainer)

            let accessoryContainer = UIView()
            accessoryContainer.backgroundColor = .clear
            accessoryContainer.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(accessoryContainer)
            self.accessoryContainer = accessoryContainer

            let accessoryImageView = UIImageView(image: Asset.Images.Attachments.listWebPageSnapshot.image)
            accessoryImageView.clipsToBounds = true
            accessoryImageView.contentMode = .scaleAspectFit
            accessoryImageView.translatesAutoresizingMaskIntoConstraints = false
            accessoryContainer.addSubview(accessoryImageView)
            self.accessoryImageView = accessoryImageView

            let fileView = FileAttachmentView()
            fileView.isHidden = true
            fileView.contentInsets = UIEdgeInsets(top: 16, left: horizontalSpacing, bottom: 16, right: 16)
            fileView.translatesAutoresizingMaskIntoConstraints = false
            accessoryContainer.addSubview(fileView)
            self.fileView = fileView

            let accessoryContainerRight = contentView.trailingAnchor.constraint(equalTo: accessoryContainer.trailingAnchor)
            self.accessoryContainerRight = accessoryContainerRight

            var constraints = [
                typeImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
                typeImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                typeImageView.widthAnchor.constraint(equalToConstant: 28),
                typeImageView.heightAnchor.constraint(equalToConstant: 28),

                labelsContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
                labelsContainer.leadingAnchor.constraint(equalTo: typeImageView.trailingAnchor, constant: horizontalSpacing),
                contentView.bottomAnchor.constraint(equalTo: labelsContainer.bottomAnchor, constant: 12 + ItemDetailLayout.separatorHeight),
                accessoryContainer.leadingAnchor.constraint(equalTo: labelsContainer.trailingAnchor),

                titleLabel.topAnchor.constraint(equalTo: labelsContainer.topAnchor),
                titleLabel.leadingAnchor.constraint(equalTo: labelsContainer.leadingAnchor),
                labelsContainer.trailingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor),
                subtitleStackView.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor),
                subtitleStackView.leadingAnchor.constraint(equalTo: labelsContainer.leadingAnchor),
                labelsContainer.trailingAnchor.constraint(greaterThanOrEqualTo: subtitleStackView.trailingAnchor),
                subtitleLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor, constant: 24),
                labelsContainer.bottomAnchor.constraint(equalTo: subtitleLabel.lastBaselineAnchor),

                accessoryContainerRight,
                accessoryContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                accessoryContainer.widthAnchor.constraint(equalToConstant: accessoryContainerWidth),
                accessoryContainer.heightAnchor.constraint(equalToConstant: Self.accessoryContainerHeight),

                accessoryImageView.centerXAnchor.constraint(equalTo: accessoryContainer.centerXAnchor),
                accessoryImageView.centerYAnchor.constraint(equalTo: accessoryContainer.centerYAnchor),

                fileView.topAnchor.constraint(equalTo: accessoryContainer.topAnchor),
                fileView.leadingAnchor.constraint(equalTo: accessoryContainer.leadingAnchor),
                accessoryContainer.trailingAnchor.constraint(equalTo: fileView.trailingAnchor),
                accessoryContainer.bottomAnchor.constraint(equalTo: fileView.bottomAnchor)
            ]
            if #available(iOS 26.0.0, *) {
                constraints.append(contentView.heightAnchor.constraint(equalToConstant: 68))
            }
            NSLayoutConstraint.activate(constraints)
        }

        func setupAccessibilityActions() {
            let openItemAction = UIAccessibilityCustomAction(name: L10n.Accessibility.Items.openItem, actionHandler: { [weak self] _ in
                guard let self else { return false }
                return actionDelegate?.itemCellDidRequestOpen(self) ?? false
            })
            accessibilityCustomActions = [openItemAction]
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)

        let configuration = makeBackgroundConfiguration(for: state)
        backgroundConfiguration = configuration

        guard let fileView, let tagCircles else { return }
        fileView.set(backgroundColor: configuration.resolvedBackgroundColor(for: tintColor))
        tagCircles.borderColor = tagBorderColor(for: state)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        setNeedsUpdateConfiguration()
    }

    private func makeBackgroundConfiguration(for state: UICellConfigurationState) -> UIBackgroundConfiguration {
        var configuration = defaultBackgroundConfiguration().updated(for: state)
        if state.isSelected {
            if #available(iOS 26.0, *) {
                configuration.backgroundColor = .systemGray5
            } else {
                configuration.backgroundColor = state.isEditing ? Asset.Colors.cellSelected.color : Asset.Colors.cellHighlighted.color
            }
            configuration.backgroundColorTransformer = nil
        } else if state.isHighlighted, #unavailable(iOS 26.0) {
            configuration.backgroundColor = Asset.Colors.cellHighlighted.color
            configuration.backgroundColorTransformer = nil
        }
        return configuration
    }

    private func tagBorderColor(for state: UICellConfigurationState) -> CGColor {
        let color: UIColor
        if #available(iOS 26.0, *) {
            color = makeBackgroundConfiguration(for: state).resolvedBackgroundColor(for: tintColor)
        } else if state.isEditing {
            color = Asset.Colors.cellSelected.color
        } else {
            color = traitCollection.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
        }
        return color.cgColor
    }

    func set(item: ItemCellModel) {
        key = item.key

        var accessories: [UICellAccessory] = [.multiselect(displayed: .whenEditing)]
        if item.hasDetailButton {
            accessories.append(.detail(displayed: .whenNotEditing, actionHandler: { [weak self] in
                guard let self else { return }
                actionDelegate?.itemCellDidTapDetail(self)
            }))
        }
        self.accessories = accessories
        typeImageView.image = UIImage(named: item.typeIconName)?.withRenderingMode(item.iconRenderingMode)
        typeImageView.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        if item.title.string.isEmpty {
            titleLabel.text = " "
        } else {
            titleLabel.attributedText = item.title
        }
        titleLabel.accessibilityLabel = titleAccessibilityLabel(for: item)
        set(subtitle: item.subtitle)
        // The label adds extra horizontal spacing so there is a negative right inset so that the label ends where the text ends exactly.
        // The note icon is rectangular and has 1px white space on each side, so it needs an extra negative pixel when there are no tags.
        subtitleLabel.rightInset = item.tagColors.isEmpty ? -2 : -1
        noteIcon.isHidden = !item.hasNote
        noteIcon.isAccessibilityElement = false

        tagCircles.isHidden = item.tagColors.isEmpty && item.tagEmojis.isEmpty
        tagCircles.isAccessibilityElement = false
        if !tagCircles.isHidden {
            tagCircles.set(emojis: item.tagEmojis, colors: item.tagColors)
        }

        set(accessory: item.accessory)

        layoutIfNeeded()

        func titleAccessibilityLabel(for item: ItemCellModel) -> String {
            let title = item.title.string.isEmpty ? L10n.Accessibility.untitled : item.title.string
            return item.typeName + ", " + title
        }
    }

    func set(accessory: ItemCellModel.Accessory?) {
        guard let accessory else {
            accessoryContainer.isHidden = true
            accessoryContainerRight.constant = Self.noAccessoryTrailingInset - accessoryContainerWidth
            return
        }

        accessoryContainer.isHidden = false
        accessoryContainerRight.constant = 0

        switch accessory {
        case .attachment(let state):
            fileView.set(state: state, style: .list)
            fileView.isHidden = false
            accessoryImageView.isHidden = true

        case .doi, .url:
            fileView.isHidden = true
            accessoryImageView.isHidden = false
            accessoryImageView.image = Asset.Images.Attachments.listLink.image
        }
    }

    func set(subtitle: ItemCellModel.Subtitle?) {
        let text = subtitle?.text ?? ""
        let animated = subtitle?.animated ?? false
        subtitlePrefix = text
        if let subtitleAnimator, subtitleAnimator.isRunning {
            // Animator is already running.
            if !animated {
                // Stop animating subtitle, and the new subtitle prefix will be set in the label.
                stopAnimatingSubtitle()
            }
            // Otherwise do nothing as the animation will use the new subtitle prefix.
        } else {
            // Animator is not running. First set new text.
            subtitleLabel.text = text.isEmpty ? " " : text
            subtitleLabel.accessibilityLabel = text
            if !text.isEmpty, animated {
                // Start animating if needed.
                startAnimatingSubtitle()
            }
        }
        subtitleLabel.isHidden = text.isEmpty && (!noteIcon.isHidden || !tagCircles.isHidden)
    }

    private func startAnimatingSubtitle() {
        subtitleAnimator = UIViewPropertyAnimator(duration: 0.5, curve: .linear) { [weak self] in
            guard let self else { return }
            // Reduce subtitle label opacity to create a fade effect.
            subtitleLabel.alpha = 0.9
        }

        subtitleAnimator?.addCompletion { [weak self] _ in
            guard let self else { return }
            subtitleAnimationSuffixDotCount = (subtitleAnimationSuffixDotCount + 1) % 3
            subtitleLabel.text = subtitlePrefix + String(repeating: ".", count: subtitleAnimationSuffixDotCount + 1) + " "
            subtitleLabel.accessibilityLabel = subtitlePrefix
            // Restore opacity.
            subtitleLabel.alpha = 1
            // Repeat animation.
            startAnimatingSubtitle()
        }

        subtitleAnimator?.startAnimation()
    }

    private func stopAnimatingSubtitle() {
        subtitleAnimator?.stopAnimation(true)
        subtitleAnimator = nil
        subtitleAnimationSuffixDotCount = 0
        subtitleLabel.text = subtitlePrefix.isEmpty ? " " : subtitlePrefix
        subtitleLabel.accessibilityLabel = subtitlePrefix
        subtitleLabel.alpha = 1
    }
}
