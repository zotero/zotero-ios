//
//  AnnotationViewSpacer.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationViewSpacer: UIView {

    init() {
        super.init(frame: CGRect())
        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white
        self.heightAnchor.constraint(equalToConstant: PDFReaderLayout.annotationVerticalSpacerHeight).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
