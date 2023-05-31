//
//  DashedView.swift
//  Zotero
//
//  Created by Michal Rentka on 07.11.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class DashedView: UIView {
    private var dashLayer: CAShapeLayer? {
        return (self.layer.sublayers ?? []).compactMap({ $0 as? CAShapeLayer }).first
    }

    var dashColor: UIColor {
        didSet {
            guard let layer = self.dashLayer else { return }
            layer.strokeColor = self.dashColor.cgColor
        }
    }

    init() {
        self.dashColor = .black
        super.init(frame: CGRect())
        self.addDashedBorder(color: .black)
    }

    required init?(coder: NSCoder) {
        self.dashColor = .black
        super.init(coder: coder)
        self.addDashedBorder(color: .black)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let layer = self.dashLayer else { return }

        layer.frame = self.bounds
        layer.path = UIBezierPath(roundedRect: self.bounds, cornerRadius: self.layer.cornerRadius).cgPath
    }

    private func addDashedBorder(color: UIColor) {
        let shapeLayer = CAShapeLayer()
        shapeLayer.frame = self.bounds
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineWidth = 3
        shapeLayer.lineJoin = CAShapeLayerLineJoin.round
        shapeLayer.lineDashPattern = [6,3]
        shapeLayer.path = UIBezierPath(roundedRect: self.bounds, cornerRadius: self.layer.cornerRadius).cgPath
        self.layer.addSublayer(shapeLayer)
    }
}
