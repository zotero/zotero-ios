//
//  AnnotationViewButton.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class AnnotationViewButton: UIButton {
    init(layout: AnnotationViewLayout) {
        super.init(frame: CGRect())
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setTitleColor(Asset.Colors.zoteroBlueWithDarkMode.color, for: .normal)
        self.titleLabel?.font = layout.font
        self.titleLabel?.adjustsFontForContentSizeCategory = true
        self.contentHorizontalAlignment = .leading
        
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: layout.buttonVerticalInset, leading: layout.horizontalInset, bottom: layout.buttonVerticalInset, trailing: layout.horizontalInset)
        config.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
        self.configuration = config
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
