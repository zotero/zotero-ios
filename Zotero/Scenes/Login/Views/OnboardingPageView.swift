//
//  OnboardingPageView.swift
//  Zotero
//
//  Created by Michal Rentka on 09/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class OnboardingPageView: UIView {
    private unowned let textLabel: UILabel
    unowned let spacer: UIView
    private unowned let imageView: UIImageView

    private let titleHeightConstraint: NSLayoutConstraint

    private static let smallSizeLimit: CGFloat = 768
    private static let bigTitleFont: UIFont = .systemFont(ofSize: 20)
    private static let smallTitleFont: UIFont = .systemFont(ofSize: 17)

    static func font(for size: CGSize) -> UIFont {
        return min(size.width, size.height) < smallSizeLimit ? smallTitleFont : bigTitleFont
    }

    private var isBig: Bool

    init(string: String, image: UIImage, size: CGSize, htmlConverter: HtmlAttributedStringConverter) {
        self.isBig = min(size.width, size.height) >= OnboardingPageView.smallSizeLimit

        let textLabel = UILabel()
        textLabel.numberOfLines = 0
        textLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        self.textLabel = textLabel

        self.titleHeightConstraint = textLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)

        let spacer = UIView()
        spacer.backgroundColor = .clear
        self.spacer = spacer

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        self.imageView = imageView

        super.init(frame: CGRect())

        self.update(to: self.isBig, string: string, htmlConverter: htmlConverter)
        self.titleHeightConstraint.isActive = true
        self.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView(arrangedSubviews: [textLabel, spacer, imageView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.isBaselineRelativeArrangement = true
        self.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(greaterThanOrEqualTo: self.trailingAnchor, constant: 24),
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

    func updateIfNeeded(to size: CGSize, string: String, htmlConverter: HtmlAttributedStringConverter) {
        let isBig = min(size.width, size.height) >= OnboardingPageView.smallSizeLimit
        guard self.isBig != isBig else { return }
        self.isBig = isBig
        self.update(to: isBig, string: string, htmlConverter: htmlConverter)
    }

    private func update(to bigLayout: Bool, string: String, htmlConverter: HtmlAttributedStringConverter) {
        let font = bigLayout ? OnboardingPageView.bigTitleFont : OnboardingPageView.smallTitleFont

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.5
        paragraphStyle.alignment = .center
        let kern = font.pointSize * (bigLayout ? 0.025 : 0.01)

        // Require minimum height of 3 lines
        self.titleHeightConstraint.constant = font.pointSize * 3
        self.textLabel.attributedText = htmlConverter.convert(text: string,
                                                              baseFont: font,
                                                              baseAttributes: [.paragraphStyle: paragraphStyle,
                                                                               .kern: kern,
                                                                               .foregroundColor: Asset.Colors.onboardingTitle.color])
    }
}
