//
//  CheckboxButton.swift
//  Zotero
//
//  Created by Michal Rentka on 14/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CheckboxButton: UIButton {
    var selectedBackgroundColor: UIColor = .clear
    var deselectedBackgroundColor: UIColor = .clear
    var selectedTintColor: UIColor = .black
    var deselectedTintColor: UIColor = Asset.Colors.zoteroBlue.color

    override var isSelected: Bool {
        didSet {
            setNeedsUpdateConfiguration()
        }
    }

    init(image: UIImage, contentInsets: NSDirectionalEdgeInsets) {
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.plain()
        var background = configuration.background
        background.cornerRadius = 4
        configuration.image = image
        configuration.contentInsets = contentInsets
        self.configuration = configuration

        self.configurationUpdateHandler = { [weak self] button in
            let isSelected = self?.isSelected ?? false
            var configuration = button.configuration
            var background = configuration?.background
            background?.backgroundColor = isSelected ? self?.selectedBackgroundColor : self?.deselectedBackgroundColor
            if let background {
                configuration?.background = background
            }
            configuration?.baseForegroundColor = isSelected ? self?.selectedTintColor : self?.deselectedTintColor
            button.configuration = configuration
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
