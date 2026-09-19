//
//  OnboardingPageView.swift
//  Zotero
//
//  Created by Michal Rentka on 09/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class OnboardingPageView: UIView {
    private(set) weak var textLabel: UILabel!
    private weak var textWidth: NSLayoutConstraint!
    private(set) weak var spacer: UIView!
    private(set) weak var imageView: UIImageView!
    private weak var imageViewWidth: NSLayoutConstraint!

    private(set) var layout: OnboardingLayout = .small

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()

        func setupUI() {
            backgroundColor = .systemBackground

            let textLabel = UILabel()
            textLabel.baselineAdjustment = .alignBaselines
            textLabel.font = layout.titleFont
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.numberOfLines = 0
            textLabel.textAlignment = .center
            textLabel.setContentHuggingPriority(.required, for: .horizontal)
            textLabel.setContentHuggingPriority(.init(999), for: .vertical)
            textLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            textLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textLabel)
            self.textLabel = textLabel

            let imageView = UIImageView()
            imageView.backgroundColor = .opaqueSeparator
            imageView.clipsToBounds = true
            imageView.contentMode = .scaleAspectFit
            imageView.setContentHuggingPriority(.init(999), for: .horizontal)
            imageView.setContentHuggingPriority(.init(999), for: .vertical)
            imageView.setContentCompressionResistancePriority(.init(998), for: .horizontal)
            imageView.setContentCompressionResistancePriority(.init(998), for: .vertical)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            self.imageView = imageView

            let spacer = UIView()
            spacer.isHidden = true
            spacer.backgroundColor = .systemOrange
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            spacer.setContentHuggingPriority(.init(1), for: .vertical)
            spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
            spacer.setContentCompressionResistancePriority(.init(1), for: .vertical)
            spacer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(spacer)
            self.spacer = spacer

            let textWidth = textLabel.widthAnchor.constraint(lessThanOrEqualToConstant: layout.textWidth)
            textWidth.priority = .init(999)
            self.textWidth = textWidth

            let imageViewWidth = imageView.widthAnchor.constraint(lessThanOrEqualToConstant: layout.imageSize)
            imageViewWidth.priority = .init(999)
            self.imageViewWidth = imageViewWidth

            let safeArea = safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                textLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                textLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
                trailingAnchor.constraint(greaterThanOrEqualTo: textLabel.trailingAnchor, constant: 24),
                spacer.topAnchor.constraint(equalTo: textLabel.lastBaselineAnchor),
                spacer.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
                spacer.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: spacer.bottomAnchor, constant: -10),
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 45),
                safeArea.trailingAnchor.constraint(greaterThanOrEqualTo: imageView.trailingAnchor, constant: 45),
                imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor),
                textWidth,
                imageViewWidth
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(string: String, image: UIImage, size: CGSize, htmlConverter: HtmlAttributedStringConverter) {
        layout = OnboardingLayout.from(size: size)
        imageView.image = image
        update(to: layout, string: string, htmlConverter: htmlConverter)
    }

    func updateIfNeeded(to size: CGSize, string: String, htmlConverter: HtmlAttributedStringConverter) {
        let layout = OnboardingLayout.from(size: size)
        guard self.layout != layout else { return }
        self.layout = layout
        update(to: layout, string: string, htmlConverter: htmlConverter)
    }

    private func update(to layout: OnboardingLayout, string: String, htmlConverter: HtmlAttributedStringConverter) {
        let font = layout.titleFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = font.pointSize * 1.5
        paragraphStyle.maximumLineHeight = paragraphStyle.minimumLineHeight
        paragraphStyle.alignment = .center
        let kern = font.pointSize * layout.kern

        textLabel.attributedText = htmlConverter.convert(
            text: string,
            baseAttributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
                .kern: kern,
                .foregroundColor: Asset.Colors.onboardingTitle.color
            ]
        )

        imageViewWidth.constant = layout.imageSize
        textWidth.constant = layout.textWidth
    }
}

extension OnboardingLayout {
    var titleFont: UIFont {
        switch self {
        case .big:
            return .systemFont(ofSize: 27)

        case .medium:
            return .systemFont(ofSize: 20)

        case .small:
            return .systemFont(ofSize: 17)
        }
    }

    fileprivate var kern: CGFloat {
        switch self {
        case .big, .medium:
            return 0.025

        case .small:
            return -0.01
        }
    }

    fileprivate var imageSize: CGFloat {
        switch self {
        case .big:
            return 416

        case .medium, .small:
            return 312
        }
    }

    fileprivate var textWidth: CGFloat {
        switch self {
        case .big:
            return 426

        case .medium, .small:
            return 320
        }
    }
}
