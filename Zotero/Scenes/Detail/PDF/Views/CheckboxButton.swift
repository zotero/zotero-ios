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

        configurationUpdateHandler = { button in
            guard let button = button as? CheckboxButton, var configuration = button.configuration else { return }
            let isSelected = button.isSelected
            var background = configuration.background
            background.backgroundColor = isSelected ? button.selectedBackgroundColor : button.deselectedBackgroundColor
            configuration.background = background
            configuration.baseForegroundColor = isSelected ? button.selectedTintColor : button.deselectedTintColor
            button.configuration = configuration
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
