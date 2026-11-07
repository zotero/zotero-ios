//
//  PDFPlainReaderViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 01.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import PSPDFKitUI

final class PDFPlainReaderViewController: PSPDFKitUI.ReaderViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let primaryAction = UIAction(image: UIImage(systemName: "chevron.left")) { [weak self] _ in
            self?.navigationController?.presentingViewController?.dismiss(animated: true)
        }
        let closeButton = UIBarButtonItem(primaryAction: primaryAction)
        navigationItem.leftBarButtonItem = closeButton
    }
}
