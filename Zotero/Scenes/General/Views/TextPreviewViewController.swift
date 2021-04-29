//
//  TextPreviewViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 29.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class TextPreviewViewController: UIViewController {
    @IBOutlet private weak var textView: UITextView!

    private let text: String
    private let disposeBag: DisposeBag

    init(text: String, title: String) {
        self.text = text
        self.disposeBag = DisposeBag()

        super.init(nibName: "TextPreviewViewController", bundle: nil)

        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()
        self.textView.isEditable = false
        self.textView.text = self.text
    }

    private func setupNavigationBar() {
        let closeItem = UIBarButtonItem(title: L10n.close, style: .plain, target: nil, action: nil)
        closeItem.rx
                 .tap
                 .observeOn(MainScheduler.instance)
                 .subscribe(onNext: { [weak self] in
                     self?.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
                 })
                 .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = closeItem
    }
}
