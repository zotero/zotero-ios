//
//  OnboardingPageView.swift
//  Zotero
//
//  Created by Michal Rentka on 09/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class OnboardingPageView: UIView {
    private static let smallSizeLimit: CGFloat = 768
    private static let bigTitleFont: UIFont = .systemFont(ofSize: 20)
    private static let smallTitleFont: UIFont = .systemFont(ofSize: 17)

    static func font(for size: CGSize) -> UIFont {
        return min(size.width, size.height) < smallSizeLimit ? smallTitleFont : bigTitleFont
    }

    @IBOutlet weak var textLabel: UILabel!
    @IBOutlet weak var spacer: UIView!
    @IBOutlet weak var imageView: UIImageView!

    private var isBig: Bool = false

    func set(string: String, image: UIImage, size: CGSize, htmlConverter: HtmlAttributedStringConverter) {
        self.isBig = min(size.width, size.height) >= OnboardingPageView.smallSizeLimit
        self.imageView.image = image
        self.update(to: self.isBig, string: string, htmlConverter: htmlConverter)
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
        let kern = font.pointSize * (bigLayout ? 0.025 : -0.01)

        self.textLabel.attributedText = htmlConverter.convert(text: string,
                                                              baseFont: font,
                                                              baseAttributes: [.paragraphStyle: paragraphStyle,
                                                                               .kern: kern,
                                                                               .foregroundColor: Asset.Colors.onboardingTitle.color])
    }
}
