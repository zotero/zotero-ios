//
//  UnlockPdfViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 07.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import RxSwift

class UnlockPdfViewController: UIViewController {
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var input: UITextField!
    private weak var additionalLabel: UILabel!
    private weak var containerCenterY: NSLayoutConstraint!

    init(viewModel: ViewModel<PDFReaderActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupViews()
        self.setupObserving()
    }

    // MARK: - Actions

    private func update(state: PDFReaderState) {
        if let success = state.unlockSuccessful, !success {
            self.additionalLabel.text = L10n.Pdf.Locked.failed
            self.additionalLabel.textColor = .red
            self.input.text = ""
            self.input.becomeFirstResponder()
        }
    }

    private func setupKeyboardOffset(with keyboardData: KeyboardData) {
        self.containerCenterY.constant = keyboardData.visibleHeight / 2
        UIView.animate(withDuration: keyboardData.animationDuration, delay: 0, options: keyboardData.animationOptions, animations: {
            self.view.layoutIfNeeded()
        })
    }

    private func resetAdditionalLabelIfNeeded() {
        guard self.additionalLabel.textColor == .red else { return }
        self.additionalLabel.text = L10n.Pdf.Locked.enterPassword
        self.additionalLabel.textColor = .darkGray
    }
    
    // MARK: - Setups

    private func setupViews() {
        self.view.backgroundColor = .systemGray6

        let icon = UIImageView(image: UIImage(systemName: "lock.doc", withConfiguration: UIImage.SymbolConfiguration(weight: .ultraLight)))
        icon.tintColor = .gray

        let lockedLabel = UILabel()
        lockedLabel.font = .preferredFont(forTextStyle: .headline)
        lockedLabel.textColor = .gray
        lockedLabel.text = L10n.Pdf.Locked.locked

        let topContainer = UIStackView(arrangedSubviews: [icon, lockedLabel])
        topContainer.alignment = .center
        topContainer.axis = .vertical
        topContainer.spacing = 8

        let input = UITextField()
        input.translatesAutoresizingMaskIntoConstraints = false
        input.isSecureTextEntry = true
        input.backgroundColor = .systemBackground
        input.font = .preferredFont(forTextStyle: .body)
        input.returnKeyType = .done
        input.rx.controlEvent(.editingDidEndOnExit)
                .subscribe(with: self, onNext: { `self`, _ in
                    self.viewModel.process(action: .unlock(self.input.text ?? ""))
                })
                .disposed(by: self.disposeBag)
        input.rx.controlEvent(.editingChanged)
                .subscribe(with: self, onNext: { `self`, _ in
                    self.resetAdditionalLabelIfNeeded()
                })
                .disposed(by: self.disposeBag)
        self.input = input

        let inputContainer = UIView()
        inputContainer.backgroundColor = .systemBackground
        inputContainer.layer.cornerRadius = 8
        inputContainer.layer.masksToBounds = true
        inputContainer.addSubview(input)

        let additionalLabel = UILabel()
        additionalLabel.font = .preferredFont(forTextStyle: .footnote)
        additionalLabel.textAlignment = .center
        additionalLabel.textColor = .darkGray
        additionalLabel.text = L10n.Pdf.Locked.enterPassword
        self.additionalLabel = additionalLabel

        let bottomContainer = UIStackView(arrangedSubviews: [inputContainer, additionalLabel])
        bottomContainer.axis = .vertical
        bottomContainer.spacing = 8

        let container = UIStackView(arrangedSubviews: [topContainer, bottomContainer])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.spacing = 12
        container.alignment = .center
        container.axis = .vertical
        self.view.addSubview(container)

        let centerY = self.view.centerYAnchor.constraint(equalTo: container.centerYAnchor)

        NSLayoutConstraint.activate([
            self.view.safeAreaLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            container.trailingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.trailingAnchor),
            container.topAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.view.safeAreaLayoutGuide.bottomAnchor.constraint(greaterThanOrEqualTo: container.bottomAnchor),
            container.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            centerY,
            input.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 4),
            input.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 8),
            inputContainer.bottomAnchor.constraint(equalTo: input.bottomAnchor, constant: 4),
            inputContainer.trailingAnchor.constraint(equalTo: input.trailingAnchor, constant: 8),
            inputContainer.heightAnchor.constraint(equalToConstant: 40),
            inputContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            icon.heightAnchor.constraint(equalToConstant: 80),
            icon.widthAnchor.constraint(equalToConstant: 80)
        ])

        self.containerCenterY = centerY
    }

    private func setupObserving() {
        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(with: self, onNext: { `self`, notification in
                              if let data = notification.keyboardData {
                                  self.setupKeyboardOffset(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(with: self, onNext: { `self`, notification in
                              if let data = notification.keyboardData {
                                  self.setupKeyboardOffset(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }

}

#endif
