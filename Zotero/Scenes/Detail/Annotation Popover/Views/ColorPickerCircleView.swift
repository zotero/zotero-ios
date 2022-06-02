//
//  ColorPickerCircleView.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class ColorPickerCircleView: UIView {
    private let circleLayer: CAShapeLayer
    private let selectionLayer: CAShapeLayer
    let tap: PublishSubject<String>

    var contentInsets: UIEdgeInsets = UIEdgeInsets() {
        didSet {
            self.setNeedsLayout()
        }
    }

    var circleSize: CGSize = CGSize(width: 22, height: 22) {
        didSet {
            self.setNeedsLayout()
        }
    }

    var selectionLineWidth: CGFloat = 1.5 {
        didSet {
            self.setNeedsLayout()
        }
    }

    var selectionInset = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2) {
        didSet {
            self.setNeedsLayout()
        }
    }

    var isSelected: Bool {
        get {
            return !self.selectionLayer.isHidden
        }

        set {
            self.selectionLayer.isHidden = !newValue
        }
    }

    override var backgroundColor: UIColor? {
        didSet {
            self.selectionLayer.strokeColor = self.backgroundColor?.cgColor
        }
    }

    var hexColor: String {
        guard let color = self.circleLayer.fillColor else { return "" }
        return UIColor(cgColor: color).hexString
    }

    // MARK: - Lifecycle

    init(hexColor: String) {
        self.circleLayer = CAShapeLayer()
        self.selectionLayer = CAShapeLayer()
        self.tap = PublishSubject()

        super.init(frame: CGRect())

        self.layer.addSublayer(self.circleLayer)
        self.layer.addSublayer(self.selectionLayer)

        let color = UIColor(hex: hexColor)
        self.setupCircleLayer(color: color)
        self.setupSelectionLayer(color: color)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.selectionLayer.strokeColor = self.backgroundColor?.cgColor
    }

    override func layoutSubviews() {
        super.layoutIfNeeded()

        // Circle
        let frame = CGRect(origin: CGPoint(x: self.contentInsets.left, y: self.contentInsets.top), size: self.circleSize)
        self.circleLayer.frame = frame
        self.circleLayer.path = UIBezierPath(ovalIn: CGRect(origin: CGPoint(), size: self.circleSize)).cgPath

        // Selection
        let lineWidthInset = self.selectionLineWidth / 2
        let inset = UIEdgeInsets(top: self.selectionInset.top + lineWidthInset,
                                 left: self.selectionInset.left + lineWidthInset,
                                 bottom: self.selectionInset.bottom + lineWidthInset,
                                 right: self.selectionInset.right + lineWidthInset)
        let selectionFrame = frame.inset(by: inset)
        self.selectionLayer.frame = selectionFrame
        self.selectionLayer.lineWidth = self.selectionLineWidth
        self.selectionLayer.path = UIBezierPath(ovalIn: CGRect(origin: CGPoint(), size: selectionFrame.size)).cgPath
    }

    override var intrinsicContentSize: CGSize {
        let width = self.circleSize.width + self.contentInsets.left + self.contentInsets.right
        let height = self.circleSize.height + self.contentInsets.top + self.contentInsets.bottom
        return CGSize(width: width, height: height)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        self.tap.on(.next(self.hexColor))
    }

    // MARK: - Setups

    private func setupCircleLayer(color: UIColor) {
        self.circleLayer.fillColor = color.cgColor
        self.circleLayer.shouldRasterize = true
        self.circleLayer.rasterizationScale = UIScreen.main.scale
    }

    private func setupSelectionLayer(color: UIColor) {
        self.selectionLayer.strokeColor = self.backgroundColor?.cgColor
        self.selectionLayer.fillColor = color.cgColor
        self.selectionLayer.lineWidth = self.selectionLineWidth
        self.selectionLayer.shouldRasterize = true
        self.selectionLayer.rasterizationScale = UIScreen.main.scale
        self.selectionLayer.actions = ["hidden": NSNull()]
    }
}
