//
//  PDFAnnotationToolbarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 31.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class PDFAnnotationToolbarViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            self.view.widthAnchor.constraint(equalToConstant: 44),
            self.view.heightAnchor.constraint(equalToConstant: 200)
        ])
    }

}
