//
//  ManualLookupViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 23.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

class ManualLookupViewController: UIViewController {
    @IBOutlet private weak var webView: WKWebView!
    @IBOutlet private weak var container: UIStackView!
    @IBOutlet private weak var roundedContainer: UIView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var inputContainer: UIStackView!
    @IBOutlet private weak var textView: UITextView!
    @IBOutlet private weak var scanButton: UIButton!
    @IBOutlet private weak var topConstraint: NSLayoutConstraint!
    @IBOutlet private var padBottomConstraint: NSLayoutConstraint!
    @IBOutlet private var phoneBottomConstraint: NSLayoutConstraint!

    private static let width: CGFloat = 500
    private let viewModel: ViewModel<ManualLookupActionHandler>
    private let disposeBag: DisposeBag

    private weak var lookupController: LookupViewController?
    weak var coordinatorDelegate: LookupCoordinatorDelegate?
    private var liveTextResponder: LiveTextResponder?

    init(viewModel: ViewModel<ManualLookupActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: "ManualLookupViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setup()
        self.textView.becomeFirstResponder()

        self.viewModel.stateObservable
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !self.inputContainer.isHidden {
            self.textView.becomeFirstResponder()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.updatePreferredContentSize()
    }

    deinit {
        DDLogInfo("ManualLookupViewController: deinitialized")
    }

    // MARK: - Actions

    private func close() {
        self.liveTextResponder = nil
        self.navigationController?.presentingViewController?.dismiss(animated: true)
    }

    private func lookup(text: String) {
        guard !text.isEmpty, let controller = self.lookupController else { return }
        controller.viewModel.process(action: .lookUp(text))
    }

    private func update(state: ManualLookupState) {
        if let text = state.scannedText {
            var newText = self.textView.text ?? ""
            if newText.isEmpty {
                newText = text
            } else {
                newText += ", " + text
            }
            self.textView.text = newText
            self.textView.resignFirstResponder()
        }
    }

    private func update(state: LookupState) {
        self.lookupController?.view.isHidden = false

        switch state.lookupState {
        case .failed:
            self.titleLabel.isHidden = false
            self.inputContainer.isHidden = false

            self.textView.isUserInteractionEnabled = true
            self.scanButton.isEnabled = true
            self.textView.becomeFirstResponder()

        case .loadingIdentifiers, .lookup:
            self.titleLabel.isHidden = true
            self.inputContainer.isHidden = true

            self.textView.isUserInteractionEnabled = false
            self.scanButton.isEnabled = false

            if self.textView.isFirstResponder {
                self.textView.resignFirstResponder()
            }
        }

        switch state.lookupState {
        case .failed:
            self.setupCancelDoneBarButtons()

        case .loadingIdentifiers:
            self.setupCloseBarButton(title: L10n.cancel)

        case .lookup(let data):
            let didTranslateAll = !data.contains(where: { data in
                switch data.state {
                case .enqueued, .inProgress: return true
                case .failed, .translated: return false
                }
            })
            self.setupCloseBarButton(title: didTranslateAll ? L10n.close : L10n.cancel)
        }
    }

    private func setupCloseBarButton(title: String) {
        self.navigationItem.rightBarButtonItem = nil

        let cancelItem = UIBarButtonItem(title: title, style: .plain, target: nil, action: nil)
        cancelItem.rx.tap.subscribe(onNext: { [weak self] in
            self?.close()
        }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancelItem
    }

    private func setupCancelDoneBarButtons() {
        let doneItem = UIBarButtonItem(title: L10n.lookUp, style: .done, target: nil, action: nil)
        doneItem.rx.tap.subscribe(onNext: { [weak self] in
            self?.lookup(text: self?.textView.text ?? "")
        }).disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = doneItem

        let cancelItem = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancelItem.rx.tap.subscribe(onNext: { [weak self] in
            self?.close()
        }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancelItem
    }

    private func updatePreferredContentSize() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let size = self.view.systemLayoutSizeFitting(CGSize(width: ManualLookupViewController.width, height: .greatestFiniteMagnitude))
        self.preferredContentSize = CGSize(width: ManualLookupViewController.width, height: size.height - self.view.safeAreaInsets.top)
        self.navigationController?.preferredContentSize = self.preferredContentSize
    }

    private func updateKeyboardSize(_ data: KeyboardData) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        self.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: data.endFrame.height, right: 0)
    }

    // MARK: - Setups

    private func setup() {
        self.view.backgroundColor = .systemGroupedBackground
        self.titleLabel.text = L10n.Lookup.title
        self.roundedContainer.layer.cornerRadius = 10
        self.roundedContainer.layer.masksToBounds = true

        let responder = LiveTextResponder(viewModel: self.viewModel)

        if responder.canPerformAction(#selector(UIResponder.captureTextFromCamera), withSender: self.scanButton) {
            var configuration = self.scanButton.configuration ?? UIButton.Configuration.bordered()
            configuration.title = L10n.scanText
            configuration.image = UIImage(systemName: "text.viewfinder")
            configuration.imagePadding = 8
            configuration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
            self.scanButton.configuration = configuration

            self.scanButton.addAction(.captureTextFromCamera(responder: responder, identifier: nil), for: .touchUpInside)
            self.liveTextResponder = responder
        }

        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        self.phoneBottomConstraint.isActive = isPhone
        self.padBottomConstraint.isActive = !isPhone
        self.textView.heightAnchor.constraint(equalToConstant: 80).isActive = true

        self.setupKeyboardObserving()
        self.setupCancelDoneBarButtons()
        self.setupLookupController()
    }

    private func setupLookupController() {
        guard let controller = self.coordinatorDelegate?.lookupController(multiLookupEnabled: false, hasDarkBackground: false) else { return }
        controller.webView = self.webView
        controller.view.isHidden = true
        self.lookupController = controller

        controller.willMove(toParent: self)
        self.addChild(controller)
        self.container.addArrangedSubview(controller.view)
        controller.didMove(toParent: self)

        controller.activeLookupsFinished = { [weak self] in
            self?.close()
        }
        controller.dataReloaded = { [weak self] in
            self?.topConstraint.constant = 0
            self?.updatePreferredContentSize()
        }
        controller.viewModel.stateObservable
                  .subscribe(with: self, onNext: { `self`, state in
                      self.update(state: state)
                  })
                  .disposed(by: self.disposeBag)
    }

    private func setupKeyboardObserving() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.updateKeyboardSize(data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.updateKeyboardSize(data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }
}

private final class LiveTextResponder: UIResponder, UIKeyInput {
    private weak var viewModel: ViewModel<ManualLookupActionHandler>?

    init(viewModel: ViewModel<ManualLookupActionHandler>) {
        self.viewModel = viewModel
    }

    func insertText(_ text: String) {
        self.viewModel?.process(action: .processScannedText(text))
    }

    var hasText: Bool {
        return false
    }

    func deleteBackward() {}

    deinit {
        DDLogInfo("LiveTextResponder: deinitialized")
    }
}
