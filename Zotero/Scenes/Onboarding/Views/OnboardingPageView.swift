//
//  OnboardingPageView.swift
//  Zotero
//
//  Created by Michal Rentka on 09/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class OnboardingPageView: UIView {
    @IBOutlet weak var textLabel: UILabel!
    @IBOutlet weak var textWidth: NSLayoutConstraint!
    @IBOutlet weak var spacer: UIView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var imageViewWidth: NSLayoutConstraint!

    private(set) var layout: OnboardingLayout = .small

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    func set(string: String, image: UIImage, size: CGSize, htmlConverter: HtmlAttributedStringConverter) {
        self.layout = OnboardingLayout.from(size: size)
        self.imageView.image = image
        self.update(to: self.layout, string: string, htmlConverter: htmlConverter)
    }

    func updateIfNeeded(to size: CGSize, string: String, htmlConverter: HtmlAttributedStringConverter) {
        let layout = OnboardingLayout.from(size: size)
        guard self.layout != layout else { return }
        self.layout = layout
        self.update(to: layout, string: string, htmlConverter: htmlConverter)
    }

    private func update(to layout: OnboardingLayout, string: String, htmlConverter: HtmlAttributedStringConverter) {
        let font = layout.titleFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = font.pointSize * 1.5
        paragraphStyle.maximumLineHeight = paragraphStyle.minimumLineHeight
        paragraphStyle.alignment = .center
        let kern = font.pointSize * layout.kern

        self.textLabel.attributedText = htmlConverter.convert(text: string,
                                                              baseAttributes: [.font: font,
                                                                               .paragraphStyle: paragraphStyle,
                                                                               .kern: kern,
                                                                               .foregroundColor: Asset.Colors.onboardingTitle.color])

        let imageSize = layout.imageSize
        self.imageViewWidth.constant = imageSize
        self.textWidth.constant = layout.textWidth
    }
}

extension OnboardingLayout {
    var titleFont: UIFont {
        switch self {
        case .big: return .systemFont(ofSize: 27)
        case .medium: return .systemFont(ofSize: 20)
        case .small: return .systemFont(ofSize: 17)
        }
    }

    fileprivate var kern: CGFloat {
        switch self {
        case .big, .medium: return 0.025
        case .small: return -0.01
        }
    }

    fileprivate var imageSize: CGFloat {
        switch self {
        case .big: return 416
        case .medium, .small: return 312
        }
    }

    fileprivate var textWidth: CGFloat {
        switch self {
        case .big: return 426
        case .medium, .small: return 320
        }
    }
}
