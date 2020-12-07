//
//  AnnotationViewImageContent.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationViewImageContent: UIView {
    private weak var imageView: UIImageView!
    private var imageViewHeight: NSLayoutConstraint!
    private weak var bottomInsetConstraint: NSLayoutConstraint!

    private let layout: AnnotationViewLayout

    init(layout: AnnotationViewLayout) {
        self.layout = layout

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
            return traitCollection.userInterfaceStyle == .dark ? .black : .white
        })
        self.setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(with image: UIImage?, height: CGFloat? = nil, halfBottomInset: Bool? = nil) {
        self.imageView.image = image
        if let height = height {
            self.imageViewHeight.constant = height
        }
        if let halfInset = halfBottomInset {
            self.bottomInsetConstraint.constant = halfInset ? (self.layout.verticalSpacerHeight / 2) : self.layout.verticalSpacerHeight
        }
    }

    private func setupView() {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(imageView)

        let height = imageView.heightAnchor.constraint(equalToConstant: 0)
        let bottomInset = self.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: self.layout.verticalSpacerHeight)

        NSLayoutConstraint.activate([
            // Horizontal
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: self.layout.horizontalInset),
            self.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: self.layout.horizontalInset),
            // Vertical
            imageView.topAnchor.constraint(equalTo: self.topAnchor, constant: self.layout.verticalSpacerHeight),
            bottomInset,
            height
        ])

        self.imageView = imageView
        self.imageViewHeight = height
        self.bottomInsetConstraint = bottomInset
    }
}
