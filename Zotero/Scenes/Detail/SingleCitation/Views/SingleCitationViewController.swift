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

    // MARK: - Object Lifecycle
    init(viewModel: ViewModel<SingleCitationActionHandler>) {
        self.viewModel = viewModel
        disposeBag = DisposeBag()
        super.init(nibName: "SingleCitationViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        viewModel.process(action: .cleanup)
    }

    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        title = L10n.Citation.title
        previewTitleLabel.text = L10n.Citation.preview
        omitAuthorTitle.text = L10n.Citation.omitAuthor
        locatorButton.setTitle(localized(locator: viewModel.state.locator), for: .normal)
        omitAuthorSwitch.setOn(viewModel.state.omitAuthor, animated: false)
        setupPreview()
        setupNavigationBar()
        setupButton()
        setupObserving()

        viewModel.process(action: .preload(previewWebView))

        func setupPreview() {
            previewContainer.layer.cornerRadius = 4
            previewContainer.layer.masksToBounds = true

            switch UIDevice.current.userInterfaceIdiom {
            case .pad:
                view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 12).isActive = true

            case .phone:
                view.safeAreaLayoutGuide.bottomAnchor.constraint(greaterThanOrEqualTo: container.bottomAnchor, constant: 12).isActive = true

            default:
                break
            }

            previewWebView.scrollView.isScrollEnabled = false
            previewWebView.backgroundColor = .clear
            previewWebView.scrollView.backgroundColor = .clear
            previewWebView.configuration.userContentController.add(self, name: "heightHandler")
        }

        func setupNavigationBar() {
            let cancel = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
            cancel.rx.tap.subscribe(onNext: { [weak self] in
                self?.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
            })
            .disposed(by: disposeBag)
            navigationItem.leftBarButtonItem = cancel

            setupRightButtonItem(isLoading: false)
            navigationItem.rightBarButtonItem?.isEnabled = false
        }

        func setupButton() {
            let locatorElements: [UIMenuElement] = SingleCitationState.locators.compactMap { [weak self] locator in
                guard let self else { return nil }
                return UIAction(title: localized(locator: locator), state: (viewModel.state.locator == locator) ? .on : .off) { [weak self] _ in
                    self?.viewModel.process(action: .setLocator(locator))
                }
            }
            locatorButton.menu = UIMenu(children: locatorElements)
            locatorButton.showsMenuAsPrimaryAction = true
            locatorButton.changesSelectionAsPrimaryAction = true
        }

        func setupObserving() {
            viewModel.stateObservable
                .subscribe(with: self, onNext: { `self`, state in
                    self.update(state: state)
                })
                .disposed(by: disposeBag)

            locatorTextField.rx.controlEvent(.editingChanged)
                .flatMap({ [weak self] in
                    Observable.just(self?.locatorTextField.text ?? "")
                })
                .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                .subscribe(onNext: { [weak self] value in
                    self?.viewModel.process(action: .setLocatorValue(value))
                })
                .disposed(by: disposeBag)

            omitAuthorSwitch.rx.controlEvent(.valueChanged)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    viewModel.process(action: .setOmitAuthor(omitAuthorSwitch.isOn))
                })
                .disposed(by: disposeBag)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updatePreferredContentSize()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        previewWebView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // MARK: - Actions
    private func update(state: SingleCitationState) {
        if state.changes.contains(.locator) {
            locatorButton.setTitle(localized(locator: state.locator), for: .normal)
        }

        updatePreview(isLoading: state.loadingPreview)
        setupRightButtonItem(isLoading: state.loadingCopy)
        navigationItem.rightBarButtonItem?.isEnabled = !state.loadingPreview

        if let error = state.error, let coordinatorDelegate {
            switch error {
            case .styleMissing:
                coordinatorDelegate.showMissingStyleError(using: nil)

            case .cantPreloadWebView:
                if let navigationController {
                    coordinatorDelegate.showCitationPreviewError(using: navigationController, errorMessage: L10n.Errors.citationPreview)
                }
            }
        }

        if state.changes.contains(.preview) {
            updatePreferredContentSize()
        }

        if state.changes.contains(.copied) {
            navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
        }

        func updatePreview(isLoading: Bool) {
            guard previewContainer.isHidden != isLoading else { return }

            activityIndicatorContainer.isHidden = !isLoading
            previewContainer.isHidden = isLoading
            locatorButton.isEnabled = !isLoading
            locatorTextField.isEnabled = !isLoading
        }
    }

    private func setupRightButtonItem(isLoading: Bool) {
        guard navigationItem.rightBarButtonItem == nil || isLoading == (navigationItem.rightBarButtonItem?.customView == nil) else { return }

        if isLoading {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        } else {
            let copy = UIBarButtonItem(title: L10n.copy, style: .done, target: nil, action: nil)
            copy.rx.tap.subscribe(onNext: { [weak self] in
                self?.viewModel.process(action: .copy)
            })
            .disposed(by: disposeBag)
            navigationItem.rightBarButtonItem = copy
        }
    }

    // MARK: - Helpers
    private func localized(locator: String) -> String {
        return NSLocalizedString("citation.locator.\(locator)", comment: "")
    }

    private func updatePreferredContentSize() {
        let size = view.systemLayoutSizeFitting(CGSize(width: SingleCitationViewController.width, height: .greatestFiniteMagnitude))
        preferredContentSize = CGSize(width: SingleCitationViewController.width, height: size.height - view.safeAreaInsets.top)
        navigationController?.preferredContentSize = preferredContentSize
    }
}

extension SingleCitationViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "heightHandler", let height = message.body as? CGFloat else { return }
        webViewHeight.constant = height
    }
}

extension SingleCitationViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
