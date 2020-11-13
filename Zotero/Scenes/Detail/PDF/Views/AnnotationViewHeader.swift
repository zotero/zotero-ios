//
//  AnnotationViewHeader.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationViewHeader: UIView {
    private weak var typeImageView: UIImageView!
    private weak var pageLabel: UILabel!
    private weak var authorLabel: UILabel!
    private weak var menuButton: UIButton!

    private var authorTrailingToContainer: NSLayoutConstraint!
    private var authorTrailingToButton: NSLayoutConstraint!

    init() {
        let typeImageView = UIImageView()
        typeImageView.translatesAutoresizingMaskIntoConstraints = false

        let pageLabel = UILabel()
        pageLabel.font = PDFReaderLayout.pageLabelFont
        pageLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        let authorLabel = UILabel()
        authorLabel.font = PDFReaderLayout.font
        authorLabel.textColor = .systemGray
        authorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        let menuButton = UIButton()
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        menuButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: PDFReaderLayout.horizontalInset, bottom: 0, right: PDFReaderLayout.horizontalInset)
        menuButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        self.typeImageView = typeImageView
        self.pageLabel = pageLabel
        self.authorLabel = authorLabel
        self.menuButton = menuButton

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white

        self.addSubview(typeImageView)
        self.addSubview(pageLabel)
        self.addSubview(authorLabel)
        self.addSubview(menuButton)

        self.authorTrailingToContainer = authorLabel.trailingAnchor.constraint(greaterThanOrEqualTo: self.trailingAnchor, constant: PDFReaderLayout.horizontalInset)
        self.authorTrailingToButton = menuButton.leadingAnchor.constraint(greaterThanOrEqualTo: authorLabel.trailingAnchor, constant: PDFReaderLayout.horizontalInset)
        let authorCenter = authorLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        authorCenter.priority = UILayoutPriority(rawValue: 750)

        NSLayoutConstraint.activate([
            // Vertical
            typeImageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            authorLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            menuButton.topAnchor.constraint(equalTo: self.topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            // Height
            self.heightAnchor.constraint(equalToConstant: PDFReaderLayout.annotationHeaderHeight),
            // Horizontal
            typeImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: PDFReaderLayout.horizontalInset),
            pageLabel.leadingAnchor.constraint(equalTo: typeImageView.trailingAnchor, constant: PDFReaderLayout.annotationHeaderPageLeadingOffset),
            authorCenter,
            authorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: pageLabel.trailingAnchor, constant: PDFReaderLayout.horizontalInset),
            menuButton.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(type: AnnotationType, color: UIColor, pageLabel: String, author: String, showsMenuButton: Bool) {
        self.typeImageView.image = self.image(for: type)
        self.typeImageView.tintColor = color
        self.pageLabel.text = pageLabel
        self.authorLabel.text = author
        self.menuButton.isHidden = !showsMenuButton
        self.authorTrailingToButton.isActive = showsMenuButton
        self.authorTrailingToContainer.isActive = !showsMenuButton
    }

    private func image(for type: AnnotationType) -> UIImage? {
        switch type {
        case .image: return Asset.Images.Annotations.area.image
        case .highlight: return Asset.Images.Annotations.highlight.image
        case .note: return Asset.Images.Annotations.note.image
        }
    }
}
