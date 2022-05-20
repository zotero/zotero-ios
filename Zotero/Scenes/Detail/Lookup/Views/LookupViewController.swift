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
    @IBOutlet private weak var errorLabel: UILabel!

    private static let width: CGFloat = 500
    private let viewModel: ViewModel<LookupActionHandler>
    private let disposeBag: DisposeBag

    init(viewModel: ViewModel<LookupActionHandler>, remoteDownloadObserver: PublishSubject<RemoteAttachmentDownloader.Update>) {
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

        self.viewModel.stateObservable
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .initialize(self.webView))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.updatePreferredContentSize()
        self.textField.becomeFirstResponder()
    }

    // MARK: - Actions

    private func update(state: LookupState) {

        switch state.state {
        case .loading, .input:
            self.errorLabel.isHidden = true
        case .done(let data):
            self.errorLabel.isHidden = true
            self.show(data: data)
        case .failed:
            self.errorLabel.isHidden =  false
        }

        self.setupBarButtons(to: state.state)
        self.updatePreferredContentSize()
    }

    private func show(data: [LookupState.LookupData]) {

    }

    private func process(update: RemoteAttachmentDownloader.Update) {
        guard update.libraryId == self.viewModel.state.libraryId else { return }

        
    }

    private func setupBarButtons(to state: LookupState.State) {
        switch state {
        case .failed, .input:
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

        case .done:
            self.navigationItem.rightBarButtonItem = nil

            let cancelItem = UIBarButtonItem(title: L10n.close, style: .plain, target: nil, action: nil)
            cancelItem.rx.tap.subscribe(onNext: { [weak self] in
                self?.navigationController?.presentingViewController?.dismiss(animated: true)
            }).disposed(by: self.disposeBag)
            self.navigationItem.leftBarButtonItem = cancelItem

        case .loading:
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)

            let cancelItem = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
            cancelItem.rx.tap.subscribe(onNext: { [weak self] in
                self?.navigationController?.presentingViewController?.dismiss(animated: true)
            }).disposed(by: self.disposeBag)
            self.navigationItem.leftBarButtonItem = cancelItem
        }
    }

    private func updatePreferredContentSize() {
        let size = self.view.systemLayoutSizeFitting(CGSize(width: LookupViewController.width, height: .greatestFiniteMagnitude))
        self.preferredContentSize = CGSize(width: LookupViewController.width, height: size.height - self.view.safeAreaInsets.top)
        self.navigationController?.preferredContentSize = self.preferredContentSize
    }

    // MARK: - Setups

    private func setup() {
        self.titleLabel.text = L10n.Lookup.title
        self.errorLabel.text = L10n.Errors.lookup
        self.setupBarButtons(to: self.viewModel.state.state)
    }

    private func setupAttachmentObserving(observer: PublishSubject<RemoteAttachmentDownloader.Update>) {
        observer.subscribe(on: MainScheduler.instance)
                .subscribe(with: self, onNext: { `self`, update in
                    self.process(update: update)
                })
                .disposed(by: self.disposeBag)
    }
}
