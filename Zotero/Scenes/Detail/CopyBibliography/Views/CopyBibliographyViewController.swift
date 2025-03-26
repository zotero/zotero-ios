//
//  CopyBibliographyViewController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 27/12/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

class CopyBibliographyViewController: UIViewController {
    // MARK: - Types
    private enum OverlayState {
        case processing
        case error(String)
    }

    // MARK: - Properties
    private weak var overlayBody: UIView!
    private weak var overlayActivityIndicator: UIActivityIndicatorView!
    private weak var overlayErrorIcon: UIImageView!
    private weak var overlayText: UILabel!

    private let viewModel: ViewModel<CopyBibliographyActionHandler>
    private let disposeBag = DisposeBag()

    weak var coordinatorDelegate: DetailCopyBibliographyCoordinatorDelegate?

    // MARK: - Object Lifecycle
    init(viewModel: ViewModel<CopyBibliographyActionHandler>) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        viewModel.process(action: .cleanup)
        DDLogInfo("CopyBibliographyViewController deinitialized")
    }

    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0, alpha: 0.1)
        view.alpha = 0
        setupView()
        setupObserving()
        viewModel.process(action: .preload)

        func setupView() {
            let overlayBody = UIView()
            overlayBody.layer.cornerRadius = 16
            overlayBody.backgroundColor = UIColor(white: 0, alpha: 0.8)
            overlayBody.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(overlayBody)
            self.overlayBody = overlayBody

            let stackView = UIStackView()
            stackView.axis = .vertical
            stackView.alignment = .fill
            stackView.distribution = .fill
            stackView.spacing = 12
            stackView.translatesAutoresizingMaskIntoConstraints = false
            overlayBody.addSubview(stackView)

            let overlayActivityIndicator = UIActivityIndicatorView(style: .medium)
            overlayActivityIndicator.color = .white
            overlayActivityIndicator.isHidden = true
            self.overlayActivityIndicator = overlayActivityIndicator
            stackView.addArrangedSubview(overlayActivityIndicator)

            let overlayErrorIcon = UIImageView(image: UIImage(systemName: "exclamationmark.circle", withConfiguration: UIImage.SymbolConfiguration(scale: .large)))
            overlayErrorIcon.tintColor = .systemRed
            overlayErrorIcon.isHidden = true
            self.overlayErrorIcon = overlayErrorIcon
            stackView.addArrangedSubview(overlayErrorIcon)

            let overlayText = UILabel()
            overlayText.text = L10n.Items.generatingBib
            overlayText.textColor = .white
            overlayText.font = .preferredFont(forTextStyle: .body)
            overlayText.setContentCompressionResistancePriority(.required, for: .horizontal)
            overlayText.setContentCompressionResistancePriority(.required, for: .vertical)
            self.overlayText = overlayText
            stackView.addArrangedSubview(overlayText)

            NSLayoutConstraint.activate([
                overlayBody.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                overlayBody.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                overlayBody.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 60),
                view.trailingAnchor.constraint(greaterThanOrEqualTo: overlayBody.trailingAnchor, constant: 60),
                stackView.topAnchor.constraint(equalTo: overlayBody.topAnchor, constant: 20),
                stackView.leadingAnchor.constraint(equalTo: overlayBody.leadingAnchor, constant: 20),
                overlayBody.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 20),
                overlayBody.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 20)
            ])
        }

        func setupObserving() {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(with: self, onNext: { `self`, state in
                    self.update(state: state)
                })
                .disposed(by: disposeBag)
        }
    }

    // MARK: - Actions
    private func update(state: CopyBibliographyState) {
        if state.processingBibliography {
            showOverlay(state: .processing)
        } else if let error = state.error {
            if let error = error as? CitationController.Error, error == .styleOrLocaleMissing {
                dismiss(animated: true) {
                    self.coordinatorDelegate?.showMissingStyleError(using: nil)
                }
            } else {
                showOverlay(state: .error(L10n.Errors.Items.generatingBib))
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1500)) {
                    self.dismiss(animated: true)
                }
            }
        } else {
            dismiss(animated: true)
        }

        func showOverlay(state: OverlayState) {
            switch state {
            case .processing:
                overlayText.text = L10n.Items.generatingBib
                overlayActivityIndicator.isHidden = false
                overlayActivityIndicator.startAnimating()
                overlayErrorIcon.isHidden = true

            case .error(let message):
                overlayText.text = message
                overlayActivityIndicator.stopAnimating()
                overlayErrorIcon.isHidden = false
            }

            view.layoutIfNeeded()

            guard view.alpha != 1 else { return }
            UIView.animate(withDuration: 0.2) {
                self.view.alpha = 1
            }
        }
    }
}
