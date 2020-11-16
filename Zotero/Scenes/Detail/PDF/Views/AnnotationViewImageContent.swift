//
//  AnnotationViewImageContent.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationViewImageContent: UIView {
    private var imageView: UIImageView!
    private var imageViewHeight: NSLayoutConstraint!

    init() {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white

        self.addSubview(imageView)

        let height = imageView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            // Horizontal
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            self.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            // Vertical
            imageView.topAnchor.constraint(equalTo: self.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.imageView = imageView
        self.imageViewHeight = height
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(with image: UIImage?, height: CGFloat? = nil) {
        self.imageView.image = image
        if let height = height {
            self.imageViewHeight.constant = height
        }
    }
}
