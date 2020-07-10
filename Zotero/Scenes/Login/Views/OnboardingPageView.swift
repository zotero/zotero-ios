//
//  OnboardingPageView.swift
//  Zotero
//
//  Created by Michal Rentka on 09/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class OnboardingPageView: UIView {
    unowned let textLabel: UILabel
    unowned let spacer: UIView
    unowned let imageView: UIImageView

    init(attributedString: NSAttributedString, image: UIImage) {
        let textLabel = UILabel()
        textLabel.font = UIFont.preferredFont(forTextStyle: .body)
        textLabel.attributedText = attributedString
        textLabel.numberOfLines = 3
        textLabel.textAlignment = .center
        textLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        self.textLabel = textLabel

        let spacer = UIView()
        spacer.backgroundColor = .clear
        self.spacer = spacer

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        self.imageView = imageView

        super.init(frame: CGRect())
        self.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView(arrangedSubviews: [textLabel, spacer, imageView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        self.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(greaterThanOrEqualTo: self.trailingAnchor, constant: 20),
            stackView.topAnchor.constraint(equalTo: self.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        let width = stackView.widthAnchor.constraint(equalToConstant: 320)
        width.priority = .required
        width.isActive = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
