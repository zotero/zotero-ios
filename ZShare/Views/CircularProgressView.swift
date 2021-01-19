//
//  CircularProgressView.swift
//  ZShare
//
//  Created by Michal Rentka on 18.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class CircularProgressView: UIView {
    private static let size: CGFloat = 20
    private static let lineWidth: CGFloat = 1.5

    private var circleLayer: CAShapeLayer!
    private var progressLayer: CAShapeLayer!

    var progress: CGFloat {
        get {
            return self.progressLayer.strokeEnd
        }

        set {
            self.progressLayer.strokeEnd = newValue
        }
    }

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let center = CGPoint(x: self.bounds.width / 2, y: self.bounds.height / 2)

        // CAShapeLayer draws from center of path, so radius needs to be smaller to achieve outer size of `CircularProgressView.size`
        let path = UIBezierPath(arcCenter: center,
                                radius: ((CircularProgressView.size - CircularProgressView.lineWidth) / 2),
                                startAngle: -.pi / 2,
                                endAngle: 3 * .pi / 2,
                                clockwise: true).cgPath

        self.circleLayer.path = path
        self.progressLayer.path = path
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: CircularProgressView.size, height: CircularProgressView.size)
    }

    // MARK: - Setups

    private func setup() {
        self.backgroundColor = .clear

        let circleLayer = self.createCircleLayer()
        self.layer.addSublayer(circleLayer)
        self.circleLayer = circleLayer

        let progressLayer = self.createProgressLayer()
        self.layer.addSublayer(progressLayer)
        self.progressLayer = progressLayer
    }

    private func createCircleLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.5
        layer.strokeColor = UIColor.systemGray5.cgColor
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        return layer
    }

    private func createProgressLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.5
        layer.strokeColor = Asset.Colors.zoteroBlue.color.cgColor
        layer.strokeStart = 0
        layer.strokeEnd = 0
        return layer
    }
}
