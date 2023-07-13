//
//  UIFont+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UIFont {
    static func preferredFont(for style: TextStyle, weight: Weight) -> UIFont {
        let metrics = UIFontMetrics(forTextStyle: style)
        let desc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        let font = UIFont.systemFont(ofSize: desc.pointSize, weight: weight)
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
