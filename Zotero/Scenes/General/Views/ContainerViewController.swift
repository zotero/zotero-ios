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
    // MARK: - Properties
    let rootViewController: UIViewController
    private let disposeBag: DisposeBag

    private weak var containerHeight: NSLayoutConstraint?
    private weak var containerWidth: NSLayoutConstraint?
    private weak var containerCenterY: NSLayoutConstraint?
    private var didAppear = false

    // MARK: - Object Lifecycle
    init(rootViewController: UIViewController) {
        self.rootViewController = rootViewController
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        preferredContentSize = UIScreen.main.bounds.size
        view.backgroundColor = .clear
        setupRootViewController()
        if UIDevice.current.userInterfaceIdiom == .pad {
            setupForPad()
        } else {
            setupForPhone()
        }

        func setupRootViewController() {
            rootViewController.willMove(toParent: self)
            addChild(rootViewController)
            rootViewController.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(rootViewController.view)
            rootViewController.didMove(toParent: self)
        }

        func setupForPad() {
            setupTappableBackground()
            setupKeyboardObserving()

            rootViewController.view.layer.cornerRadius = 8
            rootViewController.view.layer.masksToBounds = true

            let height = rootViewController.view.heightAnchor.constraint(equalToConstant: 100)
            height.priority = UILayoutPriority(rawValue: 700)
            containerHeight = height

            let width = rootViewController.view.widthAnchor.constraint(equalToConstant: 100)
            width.priority = UILayoutPriority(rawValue: 700)
            containerWidth = width

            let centerY = view.centerYAnchor.constraint(equalTo: rootViewController.view.centerYAnchor)
            centerY.priority = .defaultLow
            containerCenterY = centerY

            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: rootViewController.view.centerXAnchor),
                centerY,
                rootViewController.view.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor),
                height,
                width,
                view.topAnchor.constraint(lessThanOrEqualTo: rootViewController.view.topAnchor),
                view.leadingAnchor.constraint(lessThanOrEqualTo: rootViewController.view.leadingAnchor),
                rootViewController.view.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
                rootViewController.view.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
            ])

            func setupTappableBackground() {
                let button = UIButton()
                button.addTarget(self, action: #selector(Self.hide), for: .touchDown)

                button.frame = view.bounds
                button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.insertSubview(button, at: 0)
            }

            func setupKeyboardObserving() {
                NotificationCenter.default
                    .keyboardWillShow
                    .observe(on: MainScheduler.instance)
                    .subscribe(onNext: { [weak self] notification in
                        guard let self, let data = notification.keyboardData else { return }
                        moveToKeyboard(self, data, willShow: true)
                    })
                    .disposed(by: disposeBag)

                NotificationCenter.default
                    .keyboardWillHide
                    .observe(on: MainScheduler.instance)
                    .subscribe(onNext: { [weak self] notification in
                        guard let self, let data = notification.keyboardData else { return }
                        moveToKeyboard(self, data, willShow: false)
                    })
                    .disposed(by: disposeBag)

                func moveToKeyboard(_ self: ContainerViewController, _ data: KeyboardData, willShow: Bool) {
                    guard let containerCenterY = self.containerCenterY else { return }
                    
                    containerCenterY.constant = willShow ? data.endFrame.height / 2 : 0
                    
                    guard self.isViewLoaded else { return }

                    UIView.animate(withDuration: 0.2) {
                        self.view.layoutIfNeeded()
                    }
                }
            }
        }

        func setupForPhone() {
            NSLayoutConstraint.activate([
                rootViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                rootViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                rootViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                rootViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)

        guard let containerHeight, let containerWidth else { return }

        containerHeight.constant = container.preferredContentSize.height
        containerWidth.constant = container.preferredContentSize.width

        guard didAppear else { return }

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Actions
    @objc private func hide() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}
