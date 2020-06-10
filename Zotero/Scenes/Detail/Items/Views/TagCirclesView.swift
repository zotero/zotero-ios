//
//  TagCirclesView.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class TagCirclesView: UIView {
    private var aspectRatioConstraint: NSLayoutConstraint?

    var colors: [UIColor] = [] {
        didSet {
            if let sublayers = self.layer.sublayers {
                sublayers.forEach({ $0.removeFromSuperlayer() })
            }
            self.createLayers(for: self.colors).forEach { self.layer.addSublayer($0) }
            self.updateAspectRatio()
            self.setNeedsLayout()
        }
    }

    private var aspectRatioMultiplier: CGFloat {
        guard !self.colors.isEmpty else { return 0 }
        guard self.colors.count > 1 else { return 1 }
        return 1 / (1 + (CGFloat(self.colors.count - 1) * 0.5))
    }

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
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

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    // MARK: - Actions

    private func createLayers(for colors: [UIColor]) -> [CALayer] {
        return colors.map { color in
            let layer = CALayer()
            layer.backgroundColor = color.cgColor
            layer.borderWidth = 1.5
            layer.borderColor = UIColor.white.cgColor
            layer.masksToBounds = true
            return layer
        }
    }

    private func updateAspectRatio() {
        let newMultiplier = self.aspectRatioMultiplier
        guard newMultiplier > 0 && self.aspectRatioConstraint?.multiplier != newMultiplier else { return }

        if let constraint = self.aspectRatioConstraint {
            self.removeConstraint(constraint)
        }

        self.aspectRatioConstraint = self.heightAnchor.constraint(equalTo: self.widthAnchor, multiplier: newMultiplier, constant: 0)
        self.aspectRatioConstraint?.isActive = true
    }

    // MARK: - Setups

    private func setup() {
        self.backgroundColor = .clear
        self.translatesAutoresizingMaskIntoConstraints = false
    }
}
