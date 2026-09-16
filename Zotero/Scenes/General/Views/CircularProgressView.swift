//
//  CircularProgressView.swift
//  ZShare
//
//  Created by Michal Rentka on 18.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CircularProgressView: UIView {
    private static let size: CGFloat = 20
    private static let lineWidth: CGFloat = 1.5

    private let size: CGFloat
    private let lineWidth: CGFloat

    private static let indeterminateAnimationKey = "indeterminateRotation"
    /// Fraction of the circle drawn by the spinning arc while indeterminate.
    private static let indeterminateArcLength: CGFloat = 0.25

    private var circleLayer: CAShapeLayer!
    private var progressLayer: CAShapeLayer!
    private(set) var isIndeterminate = false

    var progress: CGFloat {
        get {
            return self.progressLayer.strokeEnd
        }

        set {
            self.progressLayer.strokeEnd = newValue
        }
    }

    // MARK: - Lifecycle

    init(size: CGFloat, lineWidth: CGFloat) {
        self.size = size
        self.lineWidth = lineWidth
        super.init(frame: CGRect())
        self.setup()
    }

    override init(frame: CGRect) {
        self.size = CircularProgressView.size
        self.lineWidth = CircularProgressView.lineWidth
        super.init(frame: frame)
        self.setup()
    }

    required init?(coder: NSCoder) {
        self.size = CircularProgressView.size
        self.lineWidth = CircularProgressView.lineWidth
        super.init(coder: coder)
        self.setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let center = CGPoint(x: self.bounds.width / 2, y: self.bounds.height / 2)

        // CAShapeLayer draws from center of path, so radius needs to be smaller to achieve outer size of `size`
        let path = UIBezierPath(arcCenter: center,
                                radius: ((self.size - self.lineWidth) / 2),
                                startAngle: -.pi / 2,
                                endAngle: 3 * .pi / 2,
                                clockwise: true).cgPath

        self.circleLayer.path = path
        self.progressLayer.path = path
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: self.size, height: self.size)
    }

    // MARK: - Indeterminate animation

    /// Switches the view to an indeterminate spinner: a fixed-length arc rotating continuously. Used while progress is
    /// not yet known (e.g. before the first progress report arrives).
    func startIndeterminateAnimation() {
        guard !isIndeterminate else { return }
        isIndeterminate = true
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = CircularProgressView.indeterminateArcLength
        // Rotate the view's own layer (anchored at its center) so the arc spins around the circle center.
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = 2 * CGFloat.pi
        rotation.duration = 1
        rotation.repeatCount = .infinity
        layer.add(rotation, forKey: CircularProgressView.indeterminateAnimationKey)
    }

    /// Stops the indeterminate spinner and resets the arc so a determinate `progress` value can be shown.
    func stopIndeterminateAnimation() {
        guard isIndeterminate else { return }
        isIndeterminate = false
        layer.removeAnimation(forKey: CircularProgressView.indeterminateAnimationKey)
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0
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
        layer.lineWidth = self.lineWidth
        layer.strokeColor = UIColor.systemGray5.cgColor
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        return layer
    }

    private func createProgressLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = self.lineWidth
        layer.strokeColor = Asset.Colors.zoteroBlue.color.cgColor
        layer.strokeStart = 0
        layer.strokeEnd = 0
        return layer
    }
}
