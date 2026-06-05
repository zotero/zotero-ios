//
//  CheckboxButton.swift
//  Zotero
//
//  Created by Michal Rentka on 14/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CheckboxButton: UIButton {
    static let standardNavigationBarButtonSize: CGFloat = 46

    var selectedBackgroundColor: UIColor = .clear
    var deselectedBackgroundColor: UIColor = .clear
    var selectedTintColor: UIColor = .black
    var deselectedTintColor: UIColor = Asset.Colors.zoteroBlue.color

    private let useLayerBackground: Bool

    override var isSelected: Bool {
        didSet {
            setNeedsUpdateConfiguration()
        }
    }

    init(image: UIImage, contentInsets: NSDirectionalEdgeInsets, cornerStyle: UIButton.Configuration.CornerStyle = .fixed) {
        // Capsule-styled buttons use the view's own layer for the background so callers can control `layer.maskedCorners` to round individual corners.
        useLayerBackground = (cornerStyle == .capsule)
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.plain()
        if useLayerBackground {
            configuration.cornerStyle = .fixed
            layer.masksToBounds = true
        } else {
            configuration.cornerStyle = cornerStyle
            if cornerStyle == .fixed {
                var background = configuration.background
                background.cornerRadius = 4
                configuration.background = background
            }
        }
        configuration.image = image
        configuration.contentInsets = contentInsets
        self.configuration = configuration

        self.configurationUpdateHandler = { [weak self] button in
            guard let self else { return }
            let bgColor = self.isSelected ? self.selectedBackgroundColor : self.deselectedBackgroundColor
            let tintColor = self.isSelected ? self.selectedTintColor : self.deselectedTintColor
            if self.useLayerBackground {
                self.layer.backgroundColor = bgColor.cgColor
                var configuration = button.configuration
                configuration?.baseForegroundColor = tintColor
                button.configuration = configuration
            } else {
                var configuration = button.configuration
                var background = configuration?.background
                background?.backgroundColor = bgColor
                if let background {
                    configuration?.background = background
                }
                configuration?.baseForegroundColor = tintColor
                button.configuration = configuration
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if useLayerBackground {
            layer.cornerRadius = bounds.height / 2
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension UIBarButtonItem {
    /// The `CheckboxButton` backing a custom-view bar button, whether the custom view is the checkbox itself or a
    /// container wrapping it (e.g. when padded to the standard bar button footprint).
    var checkboxButton: CheckboxButton? {
        if let checkbox = customView as? CheckboxButton { return checkbox }
        return customView?.subviews.compactMap({ $0 as? CheckboxButton }).first
    }
}
