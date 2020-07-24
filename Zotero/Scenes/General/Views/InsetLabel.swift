//
//  InsetLabel.swift
//  Zotero
//
//  Created by Michal Rentka on 24/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

@IBDesignable class InsetLabel: UILabel {
    @IBInspectable var topInset: CGFloat = 0.0
    @IBInspectable var bottomInset: CGFloat = 0.0
    @IBInspectable var leftInset: CGFloat = 0.0
    @IBInspectable var rightInset: CGFloat = 0.0

    override func drawText(in rect: CGRect) {
        let insets = UIEdgeInsets(top: self.topInset, left: self.leftInset,
                                  bottom: self.bottomInset, right: self.rightInset)
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let contentSize = super.intrinsicContentSize
        return CGSize(width: contentSize.width + self.leftInset + self.rightInset,
                      height: contentSize.height + self.topInset + self.bottomInset)
    }

    override var bounds: CGRect {
        didSet {
            self.preferredMaxLayoutWidth = self.bounds.width - (self.leftInset + self.rightInset)
        }
    }
}
