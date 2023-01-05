//
//  AnnotationViewButton.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

final class AnnotationViewButton: UIButton {

    init(layout: AnnotationViewLayout) {
        super.init(frame: CGRect())
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setTitleColor(Asset.Colors.zoteroBlueWithDarkMode.color, for: .normal)
        self.titleLabel?.font = layout.font
        self.titleLabel?.adjustsFontForContentSizeCategory = true
        self.contentHorizontalAlignment = .leading
        self.contentEdgeInsets = UIEdgeInsets(top: layout.buttonVerticalInset, left: layout.horizontalInset, bottom: layout.buttonVerticalInset, right: layout.horizontalInset)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#endif
