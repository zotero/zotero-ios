//
//  ContainerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 20.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ContainerViewController: UIViewController {
    let rootViewController: UIViewController
    private let disposeBag: DisposeBag

    private weak var containerHeight: NSLayoutConstraint?
    private weak var containerWidth: NSLayoutConstraint?
    private weak var containerCenterY: NSLayoutConstraint?
    private var didAppear = false

    // MARK: - Lifecycle

    init(rootViewController: UIViewController) {
        self.rootViewController = rootViewController
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .formSheet
        self.isModalInPresentation = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.preferredContentSize = UIScreen.main.bounds.size
        self.view.backgroundColor = .clear
        self.setupRootViewController()
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.setupForPad()
        } else {
            self.setupForPhone()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)

        guard let height = self.containerHeight, let width = self.containerWidth else { return }

        height.constant = container.preferredContentSize.height
        width.constant = container.preferredContentSize.width

        guard self.didAppear else { return }

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Actions

    @objc private func hide() {
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    private func moveToKeyboard(_ data: KeyboardData, willShow: Bool) {
        guard let centerY = self.containerCenterY else { return }

        centerY.constant = willShow ? data.endFrame.height / 2 : 0

        guard self.isViewLoaded else { return }

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Setups

    private func setupForPad() {
        self.setupTappableBackground()
        self.setupKeyboardObserving()

        self.rootViewController.view.layer.cornerRadius = 8
        self.rootViewController.view.layer.masksToBounds = true

        let height = self.rootViewController.view.heightAnchor.constraint(equalToConstant: 100)
        height.priority = UILayoutPriority(rawValue: 700)
        self.containerHeight = height

        let width = self.rootViewController.view.widthAnchor.constraint(equalToConstant: 100)
        width.priority = UILayoutPriority(rawValue: 700)
        self.containerWidth = width

        let centerY = self.view.centerYAnchor.constraint(equalTo: self.rootViewController.view.centerYAnchor)
        centerY.priority = .defaultLow
        self.containerCenterY = centerY

        NSLayoutConstraint.activate([
            self.view.centerXAnchor.constraint(equalTo: self.rootViewController.view.centerXAnchor),
            centerY,
            self.rootViewController.view.heightAnchor.constraint(lessThanOrEqualTo: self.view.heightAnchor),
            height,
            width,
            self.view.topAnchor.constraint(lessThanOrEqualTo: self.rootViewController.view.topAnchor),
            self.view.leadingAnchor.constraint(lessThanOrEqualTo: self.rootViewController.view.leadingAnchor),
            self.rootViewController.view.trailingAnchor.constraint(lessThanOrEqualTo: self.view.trailingAnchor),
            self.rootViewController.view.bottomAnchor.constraint(lessThanOrEqualTo: self.view.bottomAnchor)
        ])
    }

    private func setupForPhone() {
        NSLayoutConstraint.activate([
            self.rootViewController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.rootViewController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.rootViewController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.rootViewController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }

    private func setupRootViewController() {
        self.rootViewController.willMove(toParent: self)
        self.addChild(self.rootViewController)
        self.rootViewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.rootViewController.view)
        self.rootViewController.didMove(toParent: self)
    }

    private func setupTappableBackground() {
        let button = UIButton()
        button.addTarget(self, action: #selector(ContainerViewController.hide), for: .touchDown)

        button.frame = self.view.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.insertSubview(button, at: 0)
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.moveToKeyboard(data, willShow: true)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.moveToKeyboard(data, willShow: false)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }
}
