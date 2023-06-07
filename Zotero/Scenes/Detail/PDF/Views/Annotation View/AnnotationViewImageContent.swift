//
//  AnnotationViewImageContent.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class AnnotationViewImageContent: UIView {
    private weak var imageView: UIImageView!
    private var imageViewHeight: NSLayoutConstraint!
    private weak var bottomInsetConstraint: NSLayoutConstraint!

    init(layout: AnnotationViewLayout) {
        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = layout.backgroundColor
        self.setupView(layout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(with image: UIImage?, height: CGFloat? = nil, bottomInset: CGFloat? = nil) {
        self.imageView.image = image
        if let height = height {
            self.imageViewHeight.constant = height
        }
        if let inset = bottomInset {
            self.bottomInsetConstraint.constant = inset
        }
    }

    private func setupView(layout: AnnotationViewLayout) {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(imageView)

        let height = imageView.heightAnchor.constraint(equalToConstant: 0)
        let bottomInset = self.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: layout.verticalSpacerHeight)

        NSLayoutConstraint.activate([
            // Horizontal
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: layout.horizontalInset),
            self.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: layout.horizontalInset),
            // Vertical
            imageView.topAnchor.constraint(equalTo: self.topAnchor, constant: layout.verticalSpacerHeight),
            bottomInset,
            height
        ])

        self.imageView = imageView
        self.imageViewHeight = height
        self.bottomInsetConstraint = bottomInset
    }
}
