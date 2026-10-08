//
//  UIFont+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UIFont {
    static func preferredFont(for style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        // Get the font descriptor for the default Dynamic Type setting value, which is large.
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: traits)
        // Then create the system font with the desired weight at that default size.
        let font = UIFont.systemFont(ofSize: fontDescriptor.pointSize, weight: weight)
        // Finally apply metrics so it scales according to the current Dynamic Type setting.
        let metrics = UIFontMetrics(forTextStyle: style)
        return metrics.scaledFont(for: font)
    }

    func with(traits: UIFontDescriptor.SymbolicTraits, attributes: [UIFontDescriptor.AttributeName: Any]) -> UIFont {
        guard !traits.isEmpty || !attributes.isEmpty else { return self }
        var fontDescriptor = self.fontDescriptor
        if !attributes.isEmpty {
            fontDescriptor = fontDescriptor.addingAttributes(attributes)
        }
        if !traits.isEmpty, let descriptor = fontDescriptor.withSymbolicTraits(traits) {
            fontDescriptor = descriptor
        }
        return UIFont(descriptor: fontDescriptor, size: self.pointSize)
    }

    func size(_ size: CGFloat) -> UIFont {
        return UIFont(descriptor: self.fontDescriptor, size: size)
    }
}
