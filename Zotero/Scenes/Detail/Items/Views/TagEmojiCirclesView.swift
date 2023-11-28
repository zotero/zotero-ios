//
//  TagEmojiCirclesView.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class TagEmojiCirclesView: UIView {
    private static let borderWidth: CGFloat = 1
    private static let circleSize: CGFloat = 12
    private static let emojisToCirclesSpacing: CGFloat = 8
    private static let emojiSpacing: CGFloat = 6
    private static let emojiLayerName = "emoji"
    private static let circleLayerName = "circle"
    private static let borderLayerName = "circleBorder"

    private var height: CGFloat = 0
    private var width: CGFloat = 0

    var borderColor: CGColor = UIColor.white.cgColor {
        didSet {
            self.updateBorderColors()
        }
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

        guard let layers = layer.sublayers, !layers.isEmpty else { return }

        let firstCircleIndex = layers.firstIndex(where: { $0.name == Self.borderLayerName })
        var xPos: CGFloat = 0

        for idx in 0..<(firstCircleIndex ?? layers.count) {
            let layer = layers[idx]
            layer.frame = CGRect(origin: CGPoint(x: xPos, y: (height - layer.frame.height) / 2), size: layer.frame.size)
            xPos += layer.frame.width + Self.emojiSpacing
        }

        guard let firstCircleIndex else { return }

        if xPos > 0 && firstCircleIndex != layers.count {
            xPos += Self.emojisToCirclesSpacing - Self.emojiSpacing
        }

        for idx in 0..<(layers.count - firstCircleIndex) {
            let layer = layers[layers.count - idx - 1]
            let isMain = layer.name == Self.circleLayerName
            layer.frame = CGRect(origin: CGPoint(x: xPos + (isMain ? Self.borderWidth : 0), y: (height - layer.frame.height) / 2), size: layer.frame.size)
            if !isMain {
                xPos += layer.frame.width / 2
            }
        }
    }

    private func updateBorderColors() {
        guard let layers = layer.sublayers else { return }
        for layer in layers {
            guard layer.name == "circleBorder" else { continue }
            layer.backgroundColor = borderColor
        }
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: width, height: height)
    }

    // MARK: - Actions

    func set(emojis: [String], colors: [UIColor]) {
        if let sublayers = self.layer.sublayers {
            sublayers.forEach({ $0.removeFromSuperlayer() })
        }

        let font = UIFont.preferredFont(forTextStyle: .body)
        var height: CGFloat = 0
        var width: CGFloat = 0

        for emoji in emojis {
            let attributedText = NSAttributedString(string: emoji, attributes: [.font: font])
            let size = attributedText.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                context: nil
            ).integral.size

            if size.height > height {
                height = size.height
            }
            width += size.width + Self.emojiSpacing

            let text = CATextLayer()
            text.frame = CGRect(origin: .zero, size: size)
            text.string = emoji
            text.font = CTFontCreateUIFontForLanguage(.system, font.pointSize, nil)
            text.fontSize = font.pointSize
            text.alignmentMode = .center
            text.shouldRasterize = true
            text.rasterizationScale = UIScreen.main.scale
            text.contentsScale = text.rasterizationScale
            text.masksToBounds = true
            text.name = Self.emojiLayerName
            self.layer.addSublayer(text)
        }

        let borderSize = Self.circleSize + (2 * Self.borderWidth)

        for color in colors.reversed() {
            // Border layer
            let border = CALayer()
            border.frame = CGRect(origin: .zero, size: CGSize(width: borderSize, height: borderSize))
            border.backgroundColor = self.borderColor
            border.masksToBounds = true
            border.shouldRasterize = true
            border.cornerRadius = borderSize / 2
            border.rasterizationScale = UIScreen.main.scale
            border.actions = ["backgroundColor": NSNull()]
            border.name = Self.borderLayerName
            self.layer.addSublayer(border)
            // Main circle layer
            let main = CALayer()
            main.frame = CGRect(origin: .zero, size: CGSize(width: Self.circleSize, height: Self.circleSize))
            main.backgroundColor = color.cgColor
            main.cornerRadius = Self.circleSize / 2
            main.shouldRasterize = true
            main.rasterizationScale = UIScreen.main.scale
            main.masksToBounds = true
            main.name = Self.circleLayerName
            self.layer.addSublayer(main)
        }

        if !colors.isEmpty {
            if width > 0 {
                width += Self.emojisToCirclesSpacing
            }
            width += ((borderSize / 2) * CGFloat(colors.count)) + (borderSize / 2)
        }

        self.width = width
        self.height = max(height, borderSize)

        self.invalidateIntrinsicContentSize()
    }

    // MARK: - Setups

    private func setup() {
        self.backgroundColor = .clear
        self.translatesAutoresizingMaskIntoConstraints = false
        self.layer.masksToBounds = true
    }
}
