//
//  MasterContainerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 08.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

final class MasterContainerViewController: UIViewController {
    private static let handleHeight: CGFloat = 40
    private static let minTopHeight: CGFloat = 256
    private static let minBottomHeight: CGFloat = 88
    let upperController: UIViewController
    let bottomController: UIViewController
    private let disposeBag: DisposeBag

    private var didAppear: Bool
    private var dragHandleFrame: CGRect?
    private weak var dragHandleCenterYConstraint: NSLayoutConstraint!

    init(topController: UIViewController, bottomController: UIViewController) {
        self.upperController = topController
        self.bottomController = bottomController
        self.didAppear = false
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !self.didAppear else { return }
        self.dragHandleCenterYConstraint.constant = self.view.frame.height / 4
    }

    private func toolbarDidPan(recognizer: UIPanGestureRecognizer) {
        guard let dragHandle = recognizer.view else { return }

        switch recognizer.state {
        case .began:
            self.dragHandleFrame = dragHandle.frame

        case .changed:
            guard let originalFrame = self.dragHandleFrame else { return }

            let translation = recognizer.translation(in: dragHandle)
            var newFrame = originalFrame
            newFrame.origin.y = originalFrame.minY + translation.y
            if newFrame.minY < MasterContainerViewController.minTopHeight {
                newFrame.origin.y = MasterContainerViewController.minTopHeight
            } else if newFrame.maxY > self.view.frame.height - MasterContainerViewController.minBottomHeight {
                newFrame.origin.y = self.view.frame.height - MasterContainerViewController.minBottomHeight - newFrame.height
            }

            self.dragHandleCenterYConstraint.constant = (newFrame.minY + (newFrame.height / 2)) - (self.view.frame.height / 2)
            self.view.layoutIfNeeded()

        case .ended, .failed:
            self.dragHandleFrame = nil

        case .cancelled, .possible: break
        @unknown default: break
        }
    }

    private func setupGestureRecognizer(for dragHandle: UIView) {
        let panRecognizer = UIPanGestureRecognizer()
        panRecognizer.rx.event
                     .subscribe(with: self, onNext: { `self`, recognizer in
                         self.toolbarDidPan(recognizer: recognizer)
                     })
                    .disposed(by: self.disposeBag)
        dragHandle.addGestureRecognizer(panRecognizer)
    }

    private func setupView() {
        self.upperController.view.translatesAutoresizingMaskIntoConstraints = false
        self.bottomController.view.translatesAutoresizingMaskIntoConstraints = false

        self.upperController.willMove(toParent: self)
        self.view.addSubview(self.upperController.view)
        self.addChild(self.upperController)
        self.upperController.didMove(toParent: self)

        self.bottomController.willMove(toParent: self)
        self.view.addSubview(self.bottomController.view)
        self.addChild(self.bottomController)
        self.bottomController.didMove(toParent: self)

        let dragHandle = UIView()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        dragHandle.backgroundColor = .secondarySystemBackground
        self.view.addSubview(dragHandle)

        self.setupGestureRecognizer(for: dragHandle)

        let dragIcon = UIImageView(image: Asset.Images.dragHandle.image.withRenderingMode(.alwaysTemplate))
        dragIcon.translatesAutoresizingMaskIntoConstraints = false
        dragIcon.tintColor = .gray.withAlphaComponent(0.6)
        dragHandle.addSubview(dragIcon)

        let dragYConstraint = dragHandle.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)

        NSLayoutConstraint.activate([
            self.view.topAnchor.constraint(equalTo: self.upperController.view.topAnchor),
            self.view.bottomAnchor.constraint(equalTo: self.bottomController.view.bottomAnchor),
            self.view.leadingAnchor.constraint(equalTo: self.upperController.view.leadingAnchor),
            self.view.leadingAnchor.constraint(equalTo: self.bottomController.view.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: self.upperController.view.trailingAnchor),
            self.view.trailingAnchor.constraint(equalTo: self.bottomController.view.trailingAnchor),
            dragYConstraint,
            dragHandle.heightAnchor.constraint(equalToConstant: MasterContainerViewController.handleHeight),
            dragHandle.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            dragHandle.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            dragHandle.topAnchor.constraint(equalTo: self.upperController.view.bottomAnchor),
            dragHandle.bottomAnchor.constraint(equalTo: self.bottomController.view.topAnchor),
            dragIcon.centerXAnchor.constraint(equalTo: dragHandle.centerXAnchor),
            dragIcon.centerYAnchor.constraint(equalTo: dragHandle.centerYAnchor)
        ])

        self.dragHandleCenterYConstraint = dragYConstraint
    }
}
