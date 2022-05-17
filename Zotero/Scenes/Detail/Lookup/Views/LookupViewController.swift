//
//  LookupViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 17.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import RxSwift

class LookupViewController: UIViewController {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var textField: UITextField!
    @IBOutlet private weak var webView: WKWebView!

    private let viewModel: ViewModel<LookupActionHandler>
    private let disposeBag: DisposeBag

    init(viewModel: ViewModel<LookupActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: "LookupViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setup()
        self.viewModel.process(action: .initialize(self.webView))
    }

    // MARK: - Setups

    private func setup() {
        self.preferredContentSize = CGSize(width: 500, height: 128)
        self.titleLabel.text = L10n.Lookup.title

        let doneItem = UIBarButtonItem(title: L10n.lookUp, style: .done, target: nil, action: nil)
        doneItem.rx.tap.subscribe(onNext: { [weak self] in
            guard let string = self?.textField.text else { return }
            self?.viewModel.process(action: .lookUp(string))
        }).disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = doneItem

        let cancelItem = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancelItem.rx.tap.subscribe(onNext: { [weak self] in
            self?.navigationController?.presentingViewController?.dismiss(animated: true)
        }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancelItem
    }
}
