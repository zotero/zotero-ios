//
//  DocumentPickerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 20/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class DocumentPickerViewController: UIDocumentPickerViewController {
    let observable: PublishSubject<[URL]> = PublishSubject()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self
    }

}

extension DocumentPickerViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.observable.on(.next(urls))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.dismiss(animated: true, completion: nil)
    }
}
