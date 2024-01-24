//
//  AnnotationViewHeader.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

final class AnnotationViewHeader: UIView {
    let layout: AnnotationViewLayout
    
    private weak var typeImageView: UIImageView!
    private weak var pageLabel: UILabel!
    private weak var authorLabel: UILabel!
    private weak var shareButton: UIButton!
    private weak var menuButton: UIButton!
    private weak var doneButton: UIButton?
    private weak var lockIcon: UIImageView?
    private weak var rightBarButtonsStackView: UIStackView!

    private var pageTrailingToAuthor: NSLayoutConstraint!
    private var authorTrailingToContainer: NSLayoutConstraint!
    private var authorTrailingToButton: NSLayoutConstraint!

    var menuTap: Observable<UIButton?> {
        return menuButton.rx.tap.flatMap({ [weak self] in Observable.just(self?.menuButton) })
    }

    var doneTap: ControlEvent<Void>? {
        return self.doneButton?.rx.tap
    }

    init(layout: AnnotationViewLayout) {
        self.layout = layout
        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = layout.backgroundColor
        self.setupView(with: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func image(for type: AnnotationType) -> UIImage? {
        switch type {
        case .image: return Asset.Images.Annotations.areaMedium.image
        case .highlight: return Asset.Images.Annotations.highlighterMedium.image
        case .note: return Asset.Images.Annotations.noteMedium.image
        case .ink: return Asset.Images.Annotations.inkMedium.image
        }
    }

    private func accessibilityLabel(for type: AnnotationType, pageLabel: String) -> String {
        let annotationName: String
        switch type {
        case .highlight:
            annotationName = L10n.Accessibility.Pdf.highlightAnnotation

        case .image:
            annotationName = L10n.Accessibility.Pdf.imageAnnotation

        case .note:
            annotationName = L10n.Accessibility.Pdf.noteAnnotation

        case .ink:
            annotationName = L10n.Accessibility.Pdf.inkAnnotation
        }
        return annotationName + ", " + L10n.page + " " + pageLabel
    }

    private func setup(
        type: AnnotationType,
        color: UIColor,
        pageLabel: String,
        author: String,
        shareMenu: UIMenu?,
        showsMenuButton: Bool,
        showsLock: Bool,
        accessibilityType: AnnotationView.AccessibilityType
    ) {
        self.typeImageView.image = self.image(for: type)?.withRenderingMode(.alwaysTemplate)
        self.typeImageView.tintColor = color
        self.pageLabel.text = L10n.page + " " + pageLabel
        self.authorLabel.text = author
        
        if let shareMenu {
            shareButton.isHidden = false
            shareButton.showsMenuAsPrimaryAction = true
            shareButton.menu = shareMenu
        } else {
            shareButton.isHidden = true
            shareButton.showsMenuAsPrimaryAction = false
            shareButton.menu = nil
        }
        self.menuButton.isHidden = !showsMenuButton
        self.lockIcon?.isHidden = !showsLock

        pageTrailingToAuthor.constant = author.isEmpty ? 0 : layout.horizontalInset
        
        let hasRightItems = !self.rightBarButtonsStackView.arrangedSubviews.filter({ !$0.isHidden }).isEmpty
        self.authorTrailingToButton.isActive = hasRightItems
        self.authorTrailingToContainer.isActive = !hasRightItems

        self.setupAccessibility(type: type, pageLabel: pageLabel, author: author, accessibilityType: accessibilityType)
    }

    func setup(
        type: AnnotationType,
        authorName: String,
        pageLabel: String,
        colorHex: String,
        shareMenuProvider: @escaping ((UIButton) -> UIMenu?),
        isEditable: Bool,
        showsLock: Bool,
        accessibilityType: AnnotationView.AccessibilityType
    ) {
        let color = UIColor(hex: colorHex)
        self.setup(
            type: type,
            color: color,
            pageLabel: pageLabel,
            author: authorName,
            shareMenu: shareMenuProvider(shareButton),
            showsMenuButton: isEditable,
            showsLock: showsLock,
            accessibilityType: accessibilityType
        )
    }

    private func setupAccessibility(type: AnnotationType, pageLabel: String, author: String, accessibilityType: AnnotationView.AccessibilityType) {
        switch accessibilityType {
        case .view:
            self.pageLabel.accessibilityLabel = self.accessibilityLabel(for: type, pageLabel: pageLabel)
            self.authorLabel.accessibilityLabel = author.isEmpty ? nil : L10n.Accessibility.Pdf.author + ": " + author

        case .cell:
            self.pageLabel.isAccessibilityElement = false
            self.authorLabel.isAccessibilityElement = false
        }

        self.menuButton.accessibilityLabel = L10n.Accessibility.Pdf.editAnnotation
        self.menuButton.isAccessibilityElement = true
        self.shareButton.accessibilityLabel = L10n.Accessibility.Pdf.shareAnnotation
        self.shareButton.isAccessibilityElement = true
    }

    private func setupView(with layout: AnnotationViewLayout) {
        let typeImageView = UIImageView()
        typeImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        typeImageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        typeImageView.contentMode = .scaleAspectFit
        typeImageView.translatesAutoresizingMaskIntoConstraints = false

        let pageLabel = UILabel()
        pageLabel.font = layout.pageLabelFont
        pageLabel.adjustsFontForContentSizeCategory = true
        pageLabel.setContentCompressionResistancePriority(.init(999), for: .horizontal)
        pageLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        let authorLabel = UILabel()
        authorLabel.font = layout.font
        authorLabel.adjustsFontForContentSizeCategory = true
        authorLabel.textColor = .systemGray
        authorLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        authorLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        var shareConfig = UIButton.Configuration.plain()
        shareConfig.image = UIImage(systemName: "square.and.arrow.up")
        shareConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: layout.horizontalInset, bottom: 0, trailing: (layout.horizontalInset / 2))
        let shareButton = UIButton()
        shareButton.configuration = shareConfig
        shareButton.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        shareButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        shareButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        var menuConfig = UIButton.Configuration.plain()
        menuConfig.image = UIImage(systemName: "ellipsis")
        menuConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: (layout.horizontalInset / 2), bottom: 0, trailing: (layout.horizontalInset / 2))
        let menuButton = UIButton()
        menuButton.configuration = menuConfig
        menuButton.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        menuButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        menuButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        var rightButtons: [UIView] = [shareButton, menuButton]

        if layout.showDoneButton {
            var doneConfig = UIButton.Configuration.plain()
            doneConfig.title = L10n.done
            doneConfig.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
            doneConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: (layout.horizontalInset / 2), bottom: 0, trailing: layout.horizontalInset)
            let doneButton = UIButton()
            doneButton.configuration = doneConfig
            doneButton.titleLabel?.adjustsFontForContentSizeCategory = true
            doneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            doneButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            rightButtons.append(doneButton)
            self.doneButton = doneButton
        }

        let lock = UIImageView(image: UIImage(systemName: "lock")?.withAlignmentRectInsets(UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -4)))
        lock.tintColor = .systemGray
        lock.contentMode = .scaleAspectFit
        lock.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        rightButtons.append(lock)

        let rightBarButtons = UIStackView(arrangedSubviews: rightButtons)
        rightBarButtons.spacing = 0
        rightBarButtons.axis = .horizontal
        rightBarButtons.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        rightBarButtons.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        rightBarButtons.translatesAutoresizingMaskIntoConstraints = false

        self.typeImageView = typeImageView
        self.pageLabel = pageLabel
        self.authorLabel = authorLabel
        self.shareButton = shareButton
        self.menuButton = menuButton
        self.lockIcon = lock
        self.rightBarButtonsStackView = rightBarButtons

        self.addSubview(typeImageView)
        self.addSubview(pageLabel)
        self.addSubview(authorLabel)
        self.addSubview(rightBarButtons)

        pageTrailingToAuthor = authorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: pageLabel.trailingAnchor)
        self.authorTrailingToContainer = self.trailingAnchor.constraint(greaterThanOrEqualTo: authorLabel.trailingAnchor, constant: layout.horizontalInset)
        self.authorTrailingToButton = rightBarButtons.leadingAnchor.constraint(greaterThanOrEqualTo: authorLabel.trailingAnchor, constant: layout.horizontalInset)
        let authorCenter = authorLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        authorCenter.priority = UILayoutPriority(rawValue: 750)

        NSLayoutConstraint.activate([
            // Vertical
            typeImageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            pageLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: layout.headerVerticalInsets),
            self.bottomAnchor.constraint(equalTo: pageLabel.bottomAnchor, constant: layout.headerVerticalInsets),
            authorLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            rightBarButtons.topAnchor.constraint(equalTo: self.topAnchor),
            rightBarButtons.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            // Horizontal
            typeImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: layout.horizontalInset),
            pageLabel.leadingAnchor.constraint(equalTo: typeImageView.trailingAnchor, constant: layout.pageLabelLeadingOffset),
            authorCenter,
            pageTrailingToAuthor,
            rightBarButtons.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }
}
