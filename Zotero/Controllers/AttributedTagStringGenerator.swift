//
//  AttributedTagStringGenerator.swift
//  Zotero
//
//  Created by Michal Rentka on 23.01.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AttributedTagStringGenerator {
    static func attributedString(from tags: [Tag], limit: Int? = nil) -> NSMutableAttributedString {
        let wholeString = NSMutableAttributedString()
        for (index, tag) in tags.enumerated() {
            if let limit = limit, index == limit {
                break
            }

            let tagInfo = TagColorGenerator.uiColor(for: tag.color)
            let color: UIColor
            switch tagInfo.style {
            case .border:
                // Overwrite default gray color
                color = UIColor(dynamicProvider: { traitCollection -> UIColor in
                    return traitCollection.userInterfaceStyle == .dark ? .white : .darkText
                })
            case .filled:
                color = tagInfo.color
            }
            let string = NSAttributedString(string: tag.name, attributes: [.foregroundColor: color])
            wholeString.append(string)
            if index != (tags.count - 1) {
                wholeString.append(NSAttributedString(string: ", "))
            }
        }
        return wholeString
    }
}
