//
//  TagColorsView.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class TagColorsView: UIView {
    // Variables
    var colors: [UIColor] = [] {
        didSet {
            if let sublayers = self.layer.sublayers {
                sublayers.forEach({ $0.removeFromSuperlayer() })
            }
            self.createLayers(for: self.colors).forEach { self.layer.addSublayer($0) }
            self.setNeedsUpdateConstraints()
        }
    }

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setupView()
    }

    override var intrinsicContentSize: CGSize {
        let height = self.bounds.height
        var width = height
        if self.colors.count > 1 {
            width += height * CGFloat(self.colors.count - 1) * 0.5
        }
        return CGSize(width: width, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let height = self.layer.frame.height
        let halfHeight = height / 2.0
        var xPos = self.layer.frame.width - height
        self.layer.sublayers?.forEach { circle in
            circle.frame = CGRect(x: xPos, y: 0, width: height, height: height)
            circle.cornerRadius = halfHeight
            xPos -= halfHeight
        }
    }

    // MARK: - Actions

    private func createLayers(for colors: [UIColor]) -> [CALayer] {
        return colors.map { color in
            let layer = CALayer()
            layer.backgroundColor = color.cgColor
            layer.borderWidth = 1.0
            layer.borderColor = UIColor.white.cgColor
            layer.masksToBounds = true
            return layer
        }
    }

    // MARK: - Setups

    private func setupView() {
        self.backgroundColor = .clear
    }
}
