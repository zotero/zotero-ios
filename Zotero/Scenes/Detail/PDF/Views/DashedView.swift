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
        return (layer.sublayers ?? []).compactMap({ $0 as? CAShapeLayer }).first
    }

    var dashColor: UIColor {
        didSet {
            dashLayer?.strokeColor = dashColor.cgColor
        }
    }

    init(type: Kind) {
        dashColor = .black
        self.type = type
        super.init(frame: CGRect())
        switch type {
        case .rounded(let cornerRadius):
            layer.cornerRadius = cornerRadius
            
        case .partialStraight:
            break
        }
        addDashedBorder(color: dashColor)
    }
    
    required init?(coder: NSCoder) {
        dashColor = .black
        let cornerRadius: CGFloat = 8
        type = .rounded(cornerRadius: cornerRadius)
        super.init(coder: coder)
        layer.cornerRadius = cornerRadius
        addDashedBorder(color: dashColor)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let dashLayer else { return }

        dashLayer.frame = bounds
        dashLayer.path = createPath(forType: type)
    }

    private func addDashedBorder(color: UIColor) {
        let shapeLayer = CAShapeLayer()
        shapeLayer.frame = bounds
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineWidth = Self.dashWidth
        shapeLayer.lineJoin = CAShapeLayerLineJoin.round
        shapeLayer.lineDashPattern = [6, 3]
        shapeLayer.path = createPath(forType: type)
        layer.addSublayer(shapeLayer)
    }

    private func createPath(forType type: Kind) -> CGPath {
        switch type {
        case .rounded(let cornerRadius):
            return UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath

        case .partialStraight(let sides):
            let path = CGMutablePath()
            if sides.contains(.left) {
                path.addLines(between: [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.minX, y: bounds.maxY)])
            }
            if sides.contains(.right) {
                path.addLines(between: [CGPoint(x: bounds.maxX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.maxY)])
            }
            if sides.contains(.top) {
                path.addLines(between: [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY)])
            }
            if sides.contains(.bottom) {
                path.addLines(between: [CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)])
            }
            return path
        }
    }
}
