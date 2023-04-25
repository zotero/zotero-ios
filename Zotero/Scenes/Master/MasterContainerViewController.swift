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
    func enablePanning()
    func disablePanning()
}

final class MasterContainerViewController: UIViewController {
    enum BottomPosition {
        case mostlyVisible
        case `default`
        case hidden
        case custom(CGFloat)

        func topOffset(availableHeight: CGFloat) -> CGFloat {
            switch self {
            case .mostlyVisible: return 202
            case .default: return availableHeight * 0.6
            case .hidden: return availableHeight - MasterContainerViewController.bottomControllerHandleHeight
            case .custom(let offset): return offset
            }
        }
    }

    private static let dragHandleTopOffset: CGFloat = 11
    private static let bottomControllerHandleHeight: CGFloat = 27
    private static let bottomContainerTappableHeight: CGFloat = 35
    private static let bottomContainerDraggableHeight: CGFloat = 55
    private static let minVisibleBottomHeight: CGFloat = 200
    let upperController: UIViewController
    let bottomController: DraggableViewController
    private let disposeBag: DisposeBag

    private weak var bottomContainer: UIView!
    private weak var bottomYConstraint: NSLayoutConstraint!
    private weak var bottomContainerBottomConstraint: NSLayoutConstraint!
    // Current position of bottom container
    private var bottomPosition: BottomPosition
    // Previous position of bottom container. Used to return to previous position when drag handle is tapped.
    private var previousBottomPosition: BottomPosition?
    private var didAppear: Bool
    // Used to calculate position and velocity when dragging
    private var initialBottomMinY: CGFloat?
    private var keyboardHeight: CGFloat = 0

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
        self.view.backgroundColor = .clear
        self.setupView()
        self.setupKeyboardObserving()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.didAppear = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !self.didAppear else { return }
        let visibleHeight = self.view.frame.height - self.keyboardHeight
        self.set(bottomPosition: self.bottomPosition, containerHeight: visibleHeight)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let visibleHeight = size.height - self.keyboardHeight
        self.set(bottomPosition: self.bottomPosition, containerHeight: visibleHeight)

        coordinator.animate(alongsideTransition: { _ in
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

    // MARK: - Actions

    private func toggleBottomPosition() {
        let visibleHeight = self.view.frame.height - self.keyboardHeight
        switch self.bottomPosition {
        case .hidden:
            self.set(bottomPosition: (self.previousBottomPosition ?? .default), containerHeight: visibleHeight)
            self.previousBottomPosition = nil
        default:
            self.previousBottomPosition = self.bottomPosition

            if let controller = self.bottomController as? TagFilterViewController, controller.searchBar.isFirstResponder {
                // If tag picker search bar is first responder and tag picker was toggled to hide, we should deselect the search bar
                self.bottomPosition = .hidden
                // Don't need to `set(bottomPosition:containerHeight:)` manually here, resigning search bar will send keyboard notifications and the UI will update there.
                controller.searchBar.resignFirstResponder()
                return
            }

            self.set(bottomPosition: .hidden, containerHeight: visibleHeight)
        }

        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut, animations: {
            self.view.layoutIfNeeded()
        })
    }

    private func setupKeyboard(with keyboardData: KeyboardData) {
        self.keyboardHeight = keyboardData.visibleHeight

        let visibleHeight = self.view.frame.height - keyboardData.visibleHeight
        self.set(bottomPosition: self.bottomPosition, containerHeight: visibleHeight)
        self.bottomContainerBottomConstraint.constant = keyboardData.visibleHeight
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut, animations: {
            self.view.layoutIfNeeded()
        })
    }

    // MARK: - Bottom panning

    private func set(bottomPosition: BottomPosition, containerHeight: CGFloat) {
        self.bottomYConstraint.constant = bottomPosition.topOffset(availableHeight: containerHeight)
        self.bottomPosition = bottomPosition
    }

    private func toolbarDidPan(recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.initialBottomMinY = self.bottomContainer.frame.minY
            self.bottomController.disablePanning()

        case .changed:
            guard let initialMinY = self.initialBottomMinY else { return }

            let translation = recognizer.translation(in: self.view)
            var minY = initialMinY + translation.y
            if minY < BottomPosition.mostlyVisible.topOffset(availableHeight: self.view.frame.height) {
                minY = BottomPosition.mostlyVisible.topOffset(availableHeight: self.view.frame.height)
            } else if minY > BottomPosition.hidden.topOffset(availableHeight: self.view.frame.height) {
                minY = BottomPosition.hidden.topOffset(availableHeight: self.view.frame.height)
            }

            self.bottomYConstraint.constant = minY
            self.view.layoutIfNeeded()

        case .ended, .failed:
            let availableHeight = self.view.frame.height - self.keyboardHeight
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
            self.bottomController.enablePanning()

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

        if yPos > (containerHeight - MasterContainerViewController.minVisibleBottomHeight) {
            return velocity.y > 0 ? .hidden : .default
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
        self.upperController.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)

        let bottomPanRecognizer = UIPanGestureRecognizer()
        bottomPanRecognizer.delegate = self
        bottomPanRecognizer.rx.event
                     .subscribe(with: self, onNext: { `self`, recognizer in
                         self.toolbarDidPan(recognizer: recognizer)
                     })
                    .disposed(by: self.disposeBag)

        let tapRecognizer = UITapGestureRecognizer()
        tapRecognizer.delegate = self
        tapRecognizer.require(toFail: bottomPanRecognizer)
        tapRecognizer.rx.event
                     .subscribe(with: self, onNext: { `self`, recognizer in
                         self.toggleBottomPosition()
                     })
                    .disposed(by: self.disposeBag)

        let bottomContainer = UIView()
        bottomContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomContainer.layer.masksToBounds = true
        bottomContainer.backgroundColor = .systemBackground
        bottomContainer.addGestureRecognizer(bottomPanRecognizer)
        bottomContainer.addGestureRecognizer(tapRecognizer)
        self.view.addSubview(bottomContainer)
        self.bottomContainer = bottomContainer

        self.bottomController.willMove(toParent: self)
        bottomContainer.addSubview(self.bottomController.view)
        self.addChild(self.bottomController)
        self.bottomController.didMove(toParent: self)

        let handleBackground = UIView()
        handleBackground.translatesAutoresizingMaskIntoConstraints = false
        handleBackground.backgroundColor = .systemBackground
        bottomContainer.addSubview(handleBackground)

        let dragIcon = UIImageView(image: Asset.Images.dragHandle.image.withRenderingMode(.alwaysTemplate))
        dragIcon.translatesAutoresizingMaskIntoConstraints = false
        dragIcon.tintColor = .gray.withAlphaComponent(0.6)
        bottomContainer.addSubview(dragIcon)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .opaqueSeparator
        bottomContainer.addSubview(separator)

        let bottomYConstraint = bottomContainer.topAnchor.constraint(equalTo: self.view.topAnchor)
        let bottomControllerHeight = self.bottomController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        bottomControllerHeight.priority = .required
        let bottomControllerBottom = self.bottomController.view.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor)
        bottomControllerBottom.priority = UILayoutPriority(999)
        let bottomContainerBottomConstraint = self.view.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor)

        NSLayoutConstraint.activate([
            self.view.topAnchor.constraint(equalTo: self.upperController.view.topAnchor),
            self.view.leadingAnchor.constraint(equalTo: self.upperController.view.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: self.upperController.view.trailingAnchor),
            bottomContainer.topAnchor.constraint(equalTo: self.upperController.view.bottomAnchor, constant: -16),
            bottomYConstraint,
            self.view.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            bottomContainerBottomConstraint,
            self.bottomController.view.topAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: MasterContainerViewController.bottomControllerHandleHeight),
            self.bottomController.view.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            self.bottomController.view.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            bottomControllerHeight,
            bottomControllerBottom,
            handleBackground.topAnchor.constraint(equalTo: bottomContainer.topAnchor),
            handleBackground.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            handleBackground.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            handleBackground.heightAnchor.constraint(equalToConstant: MasterContainerViewController.bottomControllerHandleHeight),
            dragIcon.centerXAnchor.constraint(equalTo: bottomContainer.centerXAnchor),
            dragIcon.topAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: MasterContainerViewController.dragHandleTopOffset),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.topAnchor.constraint(equalTo: bottomContainer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor)
        ])

        self.bottomYConstraint = bottomYConstraint
        self.bottomContainerBottomConstraint = bottomContainerBottomConstraint
    }

    private func setupKeyboardObserving() {
        NotificationCenter.default
                          .keyboardWillShow
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupKeyboard(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)

        NotificationCenter.default
                          .keyboardWillHide
                          .observe(on: MainScheduler.instance)
                          .subscribe(onNext: { [weak self] notification in
                              if let data = notification.keyboardData {
                                  self?.setupKeyboard(with: data)
                              }
                          })
                          .disposed(by: self.disposeBag)
    }
}

extension MasterContainerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let location = gestureRecognizer.location(in: self.bottomContainer)

        if gestureRecognizer is UITapGestureRecognizer {
            return location.y <= MasterContainerViewController.bottomContainerTappableHeight
        }

        if gestureRecognizer is UIPanGestureRecognizer {
            return location.y <= MasterContainerViewController.bottomContainerDraggableHeight
        }

        return false
    }

//    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//        guard let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer, let collectionView = otherGestureRecognizer.view as? UICollectionView else { return true }
//
//        let translation = panRecognizer.translation(in: self.view)
//
//        if collectionView.contentSize.height <= collectionView.frame.height {
//            return true
//        }
//        if translation.y > 0 {
//            return collectionView.contentOffset.y == 0
//        }
//        return false
//    }
}
