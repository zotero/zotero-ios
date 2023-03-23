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

protocol DraggableViewController: UIViewController {
    func add(panRecognizer: UIPanGestureRecognizer)
}

final class MasterContainerViewController: UIViewController {
    enum BottomPosition {
        case mostlyVisible
        case `default`
        case hidden
        case custom(CGFloat)

        func topOffset(availableHeight: CGFloat) -> CGFloat {
            switch self {
            case .mostlyVisible: return 246
            case .default: return availableHeight * 0.6
            case .hidden: return availableHeight - MasterContainerViewController.handleHeight
            case .custom(let offset): return offset
            }
        }
    }

    private static let handleHeight: CGFloat = 40
    let upperController: UIViewController
    let bottomController: DraggableViewController
    private let disposeBag: DisposeBag

    private weak var bottomYConstraint: NSLayoutConstraint!
    // Current position of bottom container
    private var bottomPosition: BottomPosition
    // Previous position of bottom container. Used to return to previous position when drag handle is tapped.
    private var previousBottomPosition: BottomPosition?
    private var didAppear: Bool
    // Used to calculate position and velocity when dragging
    private var initialBottomMinY: CGFloat?

    init(topController: UIViewController, bottomController: DraggableViewController) {
        self.upperController = topController
        self.bottomController = bottomController
        self.bottomPosition = .default
        self.didAppear = false
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        self.setupView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !self.didAppear else { return }
        self.set(bottomPosition: self.bottomPosition, containerHeight: self.view.frame.height)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        self.set(bottomPosition: self.bottomPosition, containerHeight: size.height)

        coordinator.animate(alongsideTransition: { _ in
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

    // MARK: - Actions

    private func toggleBottomPosition() {
        switch self.bottomPosition {
        case .hidden:
            self.set(bottomPosition: (self.previousBottomPosition ?? .default), containerHeight: self.view.frame.height)
            self.previousBottomPosition = nil
        default:
            self.previousBottomPosition = self.bottomPosition
            self.set(bottomPosition: .hidden, containerHeight: self.view.frame.height)
        }

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut, animations: {
            self.view.layoutIfNeeded()
        })
    }

    // MARK: - Bottom panning

    private func set(bottomPosition: BottomPosition, containerHeight: CGFloat) {
        self.bottomYConstraint.constant = bottomPosition.topOffset(availableHeight: containerHeight)
        self.bottomPosition = bottomPosition
    }

    private func toolbarDidPan(recognizer: UIPanGestureRecognizer) {
        guard let bottomContainer = recognizer.view else { return }

        switch recognizer.state {
        case .began:
            self.initialBottomMinY = bottomContainer.frame.minY

        case .changed:
            guard let initialMinY = self.initialBottomMinY else { return }

            let translation = recognizer.translation(in: bottomContainer)
            var minY = initialMinY + translation.y
            if minY < BottomPosition.mostlyVisible.topOffset(availableHeight: self.view.frame.height) {
                minY = BottomPosition.mostlyVisible.topOffset(availableHeight: self.view.frame.height)
            } else if minY > BottomPosition.hidden.topOffset(availableHeight: self.view.frame.height) {
                minY = BottomPosition.hidden.topOffset(availableHeight: self.view.frame.height)
            }

            self.bottomYConstraint.constant = minY
            self.view.layoutIfNeeded()

        case .ended, .failed:
            let availableHeight = self.view.frame.height
            let dragVelocity = recognizer.velocity(in: self.view)
            let newPosition = self.position(fromYPos: self.bottomYConstraint.constant, containerHeight: availableHeight, velocity: dragVelocity)
            let velocity = self.velocity(from: dragVelocity, currentYPos: self.bottomYConstraint.constant, position: newPosition, availableHeight: availableHeight)

            self.set(bottomPosition: newPosition, containerHeight: availableHeight)

            switch newPosition {
            case .custom:
                self.view.layoutIfNeeded()
            case .mostlyVisible, .default, .hidden:
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [.curveEaseOut], animations: {
                    self.view.layoutIfNeeded()
                })
            }

            self.initialBottomMinY = nil

        case .cancelled, .possible: break
        @unknown default: break
        }
    }

    /// Return new position for given center and velocity of handle. If velocity > 1500, it's considered a swipe and the handle
    /// is moved in swipe direction. Otherwise the handle stays in place.
    private func position(fromYPos yPos: CGFloat, containerHeight: CGFloat, velocity: CGPoint) -> BottomPosition {
        if abs(velocity.y) > 1000 {
            // Swipe in direction of velocity
            if yPos > BottomPosition.default.topOffset(availableHeight: containerHeight) {
                return velocity.y > 0 ? .hidden : .default
            } else {
                return velocity.y > 0 ? .default : .mostlyVisible
            }
        }
        return .custom(yPos)
    }

    private func velocity(from dragVelocity: CGPoint, currentYPos: CGFloat, position: BottomPosition, availableHeight: CGFloat) -> CGFloat {
        return abs(dragVelocity.y / (position.topOffset(availableHeight: availableHeight) - currentYPos))
    }

    // MARK: - Setups

    private func setupView() {
        self.upperController.view.translatesAutoresizingMaskIntoConstraints = false
        self.bottomController.view.translatesAutoresizingMaskIntoConstraints = false

        self.upperController.willMove(toParent: self)
        self.view.addSubview(self.upperController.view)
        self.addChild(self.upperController)
        self.upperController.didMove(toParent: self)

        let panRecognizer = UIPanGestureRecognizer()
        panRecognizer.delegate = self
        panRecognizer.rx.event
                     .subscribe(with: self, onNext: { `self`, recognizer in
                         self.toolbarDidPan(recognizer: recognizer)
                     })
                    .disposed(by: self.disposeBag)

        let bottomContainer = UIView()
        bottomContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomContainer.backgroundColor = .secondarySystemBackground
        bottomContainer.layer.cornerRadius = 16
        bottomContainer.layer.masksToBounds = true
        bottomContainer.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
//        bottomContainer.addGestureRecognizer(panRecognizer)
        self.view.addSubview(bottomContainer)

        self.bottomController.willMove(toParent: self)
        bottomContainer.addSubview(self.bottomController.view)
        self.addChild(self.bottomController)
        self.bottomController.didMove(toParent: self)
        self.bottomController.add(panRecognizer: panRecognizer)

        let dragHandle = UIView()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(dragHandle)

        let tapRecognizer = UITapGestureRecognizer()
//        tapRecognizer.require(toFail: panRecognizer)
        tapRecognizer.rx.event
                     .subscribe(with: self, onNext: { `self`, recognizer in
                         self.toggleBottomPosition()
                     })
                    .disposed(by: self.disposeBag)

        dragHandle.addGestureRecognizer(tapRecognizer)
//        dragHandle.addGestureRecognizer(panRecognizer)

//        let whiteCorneredBorders = UIView()
//        whiteCorneredBorders.translatesAutoresizingMaskIntoConstraints = false
//        whiteCorneredBorders.backgroundColor = .systemBackground
//        whiteCorneredBorders.layer.cornerRadius = 8
//        whiteCorneredBorders.layer.masksToBounds = true
//        whiteCorneredBorders.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
//        dragHandle.addSubview(whiteCorneredBorders)

        let dragIcon = UIImageView(image: Asset.Images.dragHandle.image.withRenderingMode(.alwaysTemplate))
        dragIcon.translatesAutoresizingMaskIntoConstraints = false
        dragIcon.tintColor = .gray.withAlphaComponent(0.6)
        dragHandle.addSubview(dragIcon)

        let bottomYConstraint = bottomContainer.topAnchor.constraint(equalTo: self.view.topAnchor)

        NSLayoutConstraint.activate([
            self.view.topAnchor.constraint(equalTo: self.upperController.view.topAnchor),
            self.view.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor),
            self.view.leadingAnchor.constraint(equalTo: self.upperController.view.leadingAnchor),
            self.view.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: self.upperController.view.trailingAnchor),
            self.view.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            bottomContainer.topAnchor.constraint(equalTo: self.upperController.view.bottomAnchor),
            bottomYConstraint,
            dragHandle.heightAnchor.constraint(equalToConstant: MasterContainerViewController.handleHeight),
            dragHandle.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            dragHandle.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            dragHandle.topAnchor.constraint(equalTo: bottomContainer.topAnchor),
            dragHandle.bottomAnchor.constraint(equalTo: self.bottomController.view.topAnchor),
            self.bottomController.view.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            self.bottomController.view.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            self.bottomController.view.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor),
            dragIcon.centerXAnchor.constraint(equalTo: dragHandle.centerXAnchor),
            dragIcon.topAnchor.constraint(equalTo: dragHandle.topAnchor, constant: 10),
//            whiteCorneredBorders.leadingAnchor.constraint(equalTo: dragHandle.leadingAnchor, constant: 11),
//            dragHandle.trailingAnchor.constraint(equalTo: whiteCorneredBorders.trailingAnchor, constant: 11),
//            whiteCorneredBorders.bottomAnchor.constraint(equalTo: dragHandle.bottomAnchor),
//            whiteCorneredBorders.heightAnchor.constraint(equalToConstant: 8)
        ])

        self.bottomYConstraint = bottomYConstraint
    }
}

extension MasterContainerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
