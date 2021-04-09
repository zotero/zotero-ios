//
//  RightButton.swift
//  ZShare
//
//  Created by Michal Rentka on 09.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class RightButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        self.alignImageToRight()
    }

    private func alignImageToRight() {
        guard let imageView = self.imageView else { return }

        let imageOffset = self.frame.width - imageView.frame.size.width

        self.titleEdgeInsets = UIEdgeInsets(top: 0, left: -1 * imageView.frame.size.width, bottom: 0, right: imageView.frame.size.width)
        self.imageEdgeInsets = UIEdgeInsets(top: 0, left: imageOffset, bottom: 0, right: -1 * imageOffset)
    }
}
