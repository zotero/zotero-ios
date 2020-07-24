//
//  TagCirclesView.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class TagCirclesView: UIView {
    private static let borderWidth: CGFloat = 1
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

        let mainHeight = self.layer.frame.height
        let mainHalfHeight = mainHeight / 2.0
        var mainXPos = self.layer.frame.width - mainHeight

        let borderHeight = mainHeight + (TagCirclesView.borderWidth * 2)
        let borderHalfHeight = mainHalfHeight + TagCirclesView.borderWidth

        self.layer.sublayers?.enumerated().forEach { index, circle in
            let mainLayer = index % 2 == 1
            let height = mainLayer ? mainHeight : borderHeight
            let yPos = mainLayer ? 0 : -TagCirclesView.borderWidth
            let xPos = mainLayer ? mainXPos : (mainXPos - TagCirclesView.borderWidth)
            let halfHeight = mainLayer ? mainHalfHeight : borderHalfHeight

            circle.frame = CGRect(x: xPos, y: yPos, width: height, height: height)
            circle.cornerRadius = halfHeight

            if mainLayer {
                mainXPos -= mainHalfHeight
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    // MARK: - Actions

    private func createLayers(for colors: [UIColor]) -> [CALayer] {
        var layers: [CALayer] = []
        for color in colors {
            // Border layer
            let border = CALayer()
            border.backgroundColor = UIColor.white.cgColor
            border.masksToBounds = true
            layers.append(border)
            // Main circle layer
            let main = CALayer()
            main.backgroundColor = color.cgColor
            main.masksToBounds = true
            layers.append(main)
        }
        return layers
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
