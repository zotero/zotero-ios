//
//  SingleCitationViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 15.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

final class SingleCitationViewController: UIViewController {
    @IBOutlet private weak var container: UIStackView!
    @IBOutlet private weak var locatorButton: UIButton!
    @IBOutlet private weak var locatorTextField: UITextField!
    @IBOutlet private weak var omitAuthorTitle: UILabel!
    @IBOutlet private weak var omitAuthorSwitch: UISwitch!
    @IBOutlet private weak var previewTitleLabel: UILabel!
    @IBOutlet private weak var previewContainer: UIView!
    @IBOutlet private weak var previewWebView: WKWebView!
    @IBOutlet private weak var webViewHeight: NSLayoutConstraint!
    @IBOutlet private weak var activityIndicatorContainer: UIView!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!

    static let width: CGFloat = 500
    private let viewModel: ViewModel<SingleCitationActionHandler>
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: DetailCitationCoordinatorDelegate?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<SingleCitationActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: "SingleCitationViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = L10n.Citation.title
        self.previewTitleLabel.text = L10n.Citation.preview
        self.omitAuthorTitle.text = L10n.Citation.omitAuthor
        self.locatorButton.setTitle(self.localized(locator: self.viewModel.state.locator), for: .normal)
        self.omitAuthorSwitch.setOn(self.viewModel.state.omitAuthor, animated: false)
        self.setupPreview()
        self.setupNavigationBar()
        self.setupObserving()

        self.viewModel.process(action: .preload(self.previewWebView))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.updatePreferredContentSize()
    }

    deinit {
        self.viewModel.process(action: .cleanup)
    }

    // MARK: - Actions

    private func update(state: SingleCitationState) {
        if state.changes.contains(.locator) {
            self.locatorButton.setTitle(self.localized(locator: state.locator), for: .normal)
        }

        self.updatePreview(isLoading: state.loadingPreview)
        self.setupRightButtonItem(isLoading: state.loadingCopy)
        self.navigationItem.rightBarButtonItem?.isEnabled = !state.loadingPreview

        if let error = state.error {
            switch error {
            case .styleMissing:
                self.coordinatorDelegate?.showMissingStyleError()

            case .cantPreloadWebView:
                self.coordinatorDelegate?.showCitationPreview(errorMessage: L10n.Errors.citationPreview)
            }
        }

        if state.changes.contains(.preview) {
//            do {
//                if let data = state.preview.data(using: .utf8) {
//                    let attr = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf, .characterEncoding: String.Encoding.utf8], documentAttributes: nil)
//                    self.previewTitleLabel.numberOfLines = 0
//                    self.previewTitleLabel.attributedText = attr
//                }
//            } catch let error {
//                NSLog("ERROR: \(error)")
//            }
            self.updatePreferredContentSize()
        }

        if state.changes.contains(.copied) {
            self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }

    private func updatePreview(isLoading: Bool) {
        guard self.previewContainer.isHidden != isLoading else { return }

        self.activityIndicatorContainer.isHidden = !isLoading
        self.previewContainer.isHidden = isLoading
        self.locatorButton.isEnabled = !isLoading
        self.locatorTextField.isEnabled = !isLoading
    }

    private func setupRightButtonItem(isLoading: Bool) {
        guard self.navigationItem.rightBarButtonItem == nil || isLoading == (self.navigationItem.rightBarButtonItem?.customView == nil) else { return }

        if isLoading {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        } else {
            let copy = UIBarButtonItem(title: L10n.copy, style: .done, target: nil, action: nil)
            copy.rx.tap.subscribe(onNext: { [weak self] in
                self?.viewModel.process(action: .copy)
            })
            .disposed(by: self.disposeBag)
            self.navigationItem.rightBarButtonItem = copy
        }
    }

    @IBAction private func showLocatorPicker() {
        let values = SingleCitationState.locators.map({ SinglePickerModel(id: $0, name: self.localized(locator: $0)) })
        self.coordinatorDelegate?.showLocatorPicker(for: values, selected: self.viewModel.state.locator, picked: { [weak self] locator in
            self?.viewModel.process(action: .setLocator(locator))
        })
    }

    // MARK: - Helpers

    private func localized(locator: String) -> String {
        return NSLocalizedString("citation.locator.\(locator)", comment: "")
    }

    private func updatePreferredContentSize() {
        let size = self.view.systemLayoutSizeFitting(CGSize(width: SingleCitationViewController.width, height: .greatestFiniteMagnitude))
        self.preferredContentSize = CGSize(width: SingleCitationViewController.width, height: size.height - self.view.safeAreaInsets.top)
        self.navigationController?.preferredContentSize = self.preferredContentSize
    }

    // MARK: - Setups

    private func setupPreview() {
        self.previewContainer.layer.cornerRadius = 4
        self.previewContainer.layer.masksToBounds = true

        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            self.view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: self.container.bottomAnchor, constant: 12).isActive = true

        case .phone:
            self.view.safeAreaLayoutGuide.bottomAnchor.constraint(greaterThanOrEqualTo: self.container.bottomAnchor, constant: 12).isActive = true
        default: break
        }

        self.previewWebView.scrollView.isScrollEnabled = false
        self.previewWebView.backgroundColor = .clear
        self.previewWebView.scrollView.backgroundColor = .clear
        self.previewWebView.configuration.userContentController.add(self, name: "heightHandler")
    }

    private func setupNavigationBar() {
        let cancel = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancel.rx.tap.subscribe(onNext: { [weak self] in
            self?.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
        })
        .disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancel

        self.setupRightButtonItem(isLoading: false)
    }

    private func setupObserving() {
        self.viewModel.stateObservable
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.locatorTextField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.locatorTextField.text ?? "") })
                             .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                             .subscribe(onNext: { [weak self] value in
                                 self?.viewModel.process(action: .setLocatorValue(value))
                             })
                             .disposed(by: self.disposeBag)

        self.omitAuthorSwitch.rx.controlEvent(.valueChanged)
                                .subscribe(onNext: { [weak self] _ in
                                    guard let self = self else { return }
                                    self.viewModel.process(action: .setOmitAuthor(self.omitAuthorSwitch.isOn))
                                })
                                .disposed(by: self.disposeBag)
    }
}

extension SingleCitationViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "heightHandler", let height = message.body as? CGFloat else { return }
        self.webViewHeight.constant = height
    }
}
