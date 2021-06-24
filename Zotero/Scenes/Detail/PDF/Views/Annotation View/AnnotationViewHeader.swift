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
    private weak var typeImageView: UIImageView!
    private weak var pageLabel: UILabel!
    private weak var authorLabel: UILabel!
    private weak var menuButton: UIButton!
    private weak var doneButton: UIButton?
    private weak var rightBarButtonsStackView: UIStackView!

    private var authorTrailingToContainer: NSLayoutConstraint!
    private var authorTrailingToButton: NSLayoutConstraint!

    var menuTap: Observable<UIButton> {
        return self.menuButton.rx.tap.flatMap({ Observable.just(self.menuButton) })
    }

    var doneTap: ControlEvent<Void>? {
        return self.doneButton?.rx.tap
    }

    init(layout: AnnotationViewLayout) {
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
        }
    }

    private func setup(type: AnnotationType, color: UIColor, pageLabel: String, author: String, showsMenuButton: Bool, showsDoneButton: Bool) {
        self.typeImageView.image = self.image(for: type)?.withRenderingMode(.alwaysTemplate)
        self.typeImageView.tintColor = color
        self.pageLabel.text = L10n.page + " " + pageLabel
        self.authorLabel.text = author
        self.menuButton.isHidden = !showsMenuButton
        self.authorTrailingToButton.isActive = showsMenuButton
        self.authorTrailingToContainer.isActive = !showsMenuButton
    }

    func setup(with annotation: Annotation, isEditable: Bool, showDoneButton: Bool) {
        let color = UIColor(hex: annotation.color)
        let author = annotation.isAuthor ? "" : annotation.author
        self.setup(type: annotation.type, color: color, pageLabel: annotation.pageLabel, author: author, showsMenuButton: isEditable, showsDoneButton: showDoneButton)
    }

    private func setupView(with layout: AnnotationViewLayout) {
        let typeImageView = UIImageView()
        typeImageView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        typeImageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        typeImageView.contentMode = .scaleAspectFit
        typeImageView.translatesAutoresizingMaskIntoConstraints = false

        let pageLabel = UILabel()
        pageLabel.font = layout.pageLabelFont
        pageLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        pageLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        let authorLabel = UILabel()
        authorLabel.font = layout.font
        authorLabel.textColor = .systemGray
        authorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        authorLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        let menuButton = UIButton()
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        menuButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: layout.horizontalInset, bottom: 0, right: (layout.horizontalInset / 2))
        menuButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        menuButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        var rightButtons = [menuButton]

        if layout.showDoneButton {
            let doneButton = UIButton()
            doneButton.setTitle(L10n.done, for: .normal)
            doneButton.setTitleColor(Asset.Colors.zoteroBlueWithDarkMode.color, for: .normal)
            doneButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: (layout.horizontalInset / 2), bottom: 0, right: layout.horizontalInset)
            doneButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            doneButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            rightButtons.append(doneButton)
            self.doneButton = doneButton
        }

        let rightBarButtons = UIStackView(arrangedSubviews: rightButtons)
        rightBarButtons.spacing = 0
        rightBarButtons.axis = .horizontal
        rightBarButtons.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        rightBarButtons.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        rightBarButtons.translatesAutoresizingMaskIntoConstraints = false

        self.typeImageView = typeImageView
        self.pageLabel = pageLabel
        self.authorLabel = authorLabel
        self.menuButton = menuButton
        self.rightBarButtonsStackView = rightBarButtons

        self.addSubview(typeImageView)
        self.addSubview(pageLabel)
        self.addSubview(authorLabel)
        self.addSubview(rightBarButtons)

        self.authorTrailingToContainer = authorLabel.trailingAnchor.constraint(greaterThanOrEqualTo: self.trailingAnchor, constant: -layout.horizontalInset)
        self.authorTrailingToButton = authorLabel.trailingAnchor.constraint(greaterThanOrEqualTo: rightBarButtons.leadingAnchor, constant: layout.horizontalInset)
        let authorCenter = authorLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        authorCenter.priority = UILayoutPriority(rawValue: 750)

        NSLayoutConstraint.activate([
            // Vertical
            typeImageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            authorLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            rightBarButtons.topAnchor.constraint(equalTo: self.topAnchor),
            rightBarButtons.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            // Height
            self.heightAnchor.constraint(equalToConstant: layout.headerHeight),
            // Horizontal
            typeImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: layout.horizontalInset),
            pageLabel.leadingAnchor.constraint(equalTo: typeImageView.trailingAnchor, constant: layout.pageLabelLeadingOffset),
            authorCenter,
            authorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: pageLabel.trailingAnchor, constant: layout.horizontalInset),
            rightBarButtons.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }
}
