//
//  DashedView.swift
//  Zotero
//
//  Created by Michal Rentka on 07.11.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class DashedView: UIView {
    struct Sides: OptionSet {
        typealias RawValue = Int8

        let rawValue: Int8

        init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        static let left = Sides(rawValue: 1 << 0)
        static let top = Sides(rawValue: 1 << 1)
        static let right = Sides(rawValue: 1 << 2)
        static let bottom = Sides(rawValue: 1 << 3)

        static var all: Sides {
            return [.left, .top, .right, .bottom]
        }
    }

    enum Kind {
        case rounded(cornerRadius: CGFloat)
        case partialStraight(sides: Sides)
    }

    static let dashWidth: CGFloat = 3
    private let type: Kind

    private var dashLayer: CAShapeLayer? {
        return (self.layer.sublayers ?? []).compactMap({ $0 as? CAShapeLayer }).first
    }

    var dashColor: UIColor {
        didSet {
            guard let layer = self.dashLayer else { return }
            layer.strokeColor = self.dashColor.cgColor
        }
    }

    init(type: Kind) {
        self.dashColor = .black
        self.type = type
        super.init(frame: CGRect())
        switch type {
        case .rounded(let cornerRadius):
            self.layer.cornerRadius = cornerRadius
            
        case .partialStraight:
            break
        }
        self.addDashedBorder(color: .black)
    }

    required init?(coder: NSCoder) {
        self.dashColor = .black
        self.type = .rounded(cornerRadius: 8)
        super.init(coder: coder)
        self.addDashedBorder(color: .black)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let layer = self.dashLayer else { return }

        layer.frame = self.bounds
        layer.path = self.createPath(forType: self.type)
    }

    private func addDashedBorder(color: UIColor) {
        let shapeLayer = CAShapeLayer()
        shapeLayer.frame = self.bounds
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineWidth = DashedView.dashWidth
        shapeLayer.lineJoin = CAShapeLayerLineJoin.round
        shapeLayer.lineDashPattern = [6, 3]
        shapeLayer.path = self.createPath(forType: self.type)
        self.layer.addSublayer(shapeLayer)
    }

    private func createPath(forType type: Kind) -> CGPath {
        switch type {
        case .rounded(let cornerRadius):
            return UIBezierPath(roundedRect: self.bounds, cornerRadius: cornerRadius).cgPath

        case .partialStraight(let sides):
            let path = CGMutablePath()
            if sides.contains(.left) {
                path.addLines(between: [CGPoint(x: self.bounds.minX, y: self.bounds.minY), CGPoint(x: self.bounds.minX, y: self.bounds.maxY)])
            }
            if sides.contains(.right) {
                path.addLines(between: [CGPoint(x: self.bounds.maxX, y: self.bounds.minY), CGPoint(x: self.bounds.maxX, y: self.bounds.maxY)])
            }
            if sides.contains(.top) {
                path.addLines(between: [CGPoint(x: self.bounds.minX, y: self.bounds.minY), CGPoint(x: self.bounds.maxX, y: self.bounds.minY)])
            }
            if sides.contains(.bottom) {
                path.addLines(between: [CGPoint(x: self.bounds.minX, y: self.bounds.maxY), CGPoint(x: self.bounds.maxX, y: self.bounds.maxY)])
            }
            return path
        }
    }
}
