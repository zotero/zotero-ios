//
//  AnnotationViewButton.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationViewButton: UIButton {

    init() {
        super.init(frame: CGRect())
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setTitleColor(Asset.Colors.zoteroBlueWithDarkMode.color, for: .normal)
        self.contentEdgeInsets = UIEdgeInsets(top: 0, left: PDFReaderLayout.horizontalInset, bottom: 0, right: PDFReaderLayout.horizontalInset)
        self.heightAnchor.constraint(equalToConstant: PDFReaderLayout.annotationHeaderHeight).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
