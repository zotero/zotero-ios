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

    init() {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white

        self.addSubview(imageView)

        let height = imageView.heightAnchor.constraint(equalToConstant: 100)
        let bottomInset = self.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: PDFReaderLayout.annotationsCellSeparatorHeight)

        NSLayoutConstraint.activate([
            // Horizontal
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            self.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            // Vertical
            imageView.topAnchor.constraint(equalTo: self.topAnchor, constant: PDFReaderLayout.annotationsCellSeparatorHeight),
            bottomInset,
            height
        ])

        self.imageView = imageView
        self.imageViewHeight = height
        self.bottomInsetConstraint = bottomInset
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
            self.bottomInsetConstraint.constant = halfInset ? (PDFReaderLayout.annotationsCellSeparatorHeight / 2) : PDFReaderLayout.annotationsCellSeparatorHeight
        }
    }
}
