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
import RxSwift

final class PDFPlainReaderViewController: ReaderViewController {
    private let disposeBag: DisposeBag = DisposeBag()

    override func viewDidLoad() {
        super.viewDidLoad()

        let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
        closeButton.rx.tap
                   .subscribe(with: self, onNext: { `self`, _ in self.navigationController?.presentingViewController?.dismiss(animated: true) })
                   .disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = closeButton
    }
}
