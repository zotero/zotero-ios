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

protocol BottomSheetObserver: UIViewController {
    func bottomSheetUpdated(hidden: Bool, containerHeight: CGFloat, topOffset: CGFloat)
}

extension BottomSheetObserver {
    func bottomSheetUpdated(hidden: Bool, containerHeight: CGFloat, topOffset: CGFloat) {
        let bottomInset: CGFloat = hidden ? .zero : (containerHeight - topOffset)
        additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
    }
}

final class MasterContainerViewController: UINavigationController {
    enum BottomPosition {
        case mostlyVisible
        case `default`
        case hidden
        case custom(CGFloat)

        func topOffset(availableHeight: CGFloat) -> CGFloat {
            switch self {
            case .mostlyVisible:
                return 202

            case .default:
                return availableHeight * 0.6

            case .hidden:
                return availableHeight - MasterContainerViewController.bottomControllerHandleHeight

            case .custom(let offset):
                return availableHeight - offset < MasterContainerViewController.minVisibleBottomHeight ? MasterContainerViewController.minVisibleBottomHeight : offset
            }
        }
    }

    private static let dragHandleTopOffset: CGFloat = 11
    private static let bottomControllerHandleHeight: CGFloat = 27
    private static let bottomContainerTappableHeight: CGFloat = 35
    private static let bottomContainerDraggableHeight: CGFloat = 55
    private static let minVisibleBottomHeight: CGFloat = 200
    private let disposeBag: DisposeBag

    lazy var bottomController: DraggableViewController? = {
        return coordinatorDelegate?.createBottomController()
    }()
    private weak var bottomContainer: UIView?
    private weak var bottomYConstraint: NSLayoutConstraint?
    private weak var bottomContainerBottomConstraint: NSLayoutConstraint?
    // Current position of bottom container
    private var bottomPosition: BottomPosition
    // Previous position of bottom container. Used to return to previous position when drag handle is tapped.
    private var previousBottomPosition: BottomPosition?
    // Used to calculate position and velocity when dragging
    private var initialBottomMinY: CGFloat?
    private var keyboardHeight: CGFloat = 0

    weak var coordinatorDelegate: MasterContainerCoordinatorDelegate?

    init() {
        self.bottomPosition = .default
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        delegate = self
        setupView()
        setupKeyboardObserving()
        setBottomSheet(hidden: true)

        func setupView() {
            guard let bottomController else { return }

            let bottomContainer = UIView()
            bottomContainer.translatesAutoresizingMaskIntoConstraints = false
            bottomContainer.layer.masksToBounds = true
            bottomContainer.backgroundColor = .systemBackground
            view.addSubview(bottomContainer)

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

            bottomController.view.translatesAutoresizingMaskIntoConstraints = false
            // Since the instance keeps a strong reference to the bottomController, its view is simply added as a subview.
            // Adding bottomController as a child view controller, would mess up the navigation stack.
            bottomContainer.addSubview(bottomController.view)

            let bottomControllerHeight = bottomController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
            bottomControllerHeight.priority = .required
            let bottomControllerBottom = bottomController.view.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor)
            bottomControllerBottom.priority = UILayoutPriority(999)
            let bottomYConstraint = bottomContainer.topAnchor.constraint(equalTo: view.topAnchor)
            let bottomContainerBottomConstraint = view.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor)

            // bottom container contains from top to bottom:
            // --- handle background (drag icon) - bottom controller view
            //  \- separator
            NSLayoutConstraint.activate([
                bottomYConstraint,
                view.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
                bottomContainerBottomConstraint,
                // handle background
                handleBackground.topAnchor.constraint(equalTo: bottomContainer.topAnchor),
                handleBackground.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
                handleBackground.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
                handleBackground.heightAnchor.constraint(equalToConstant: Self.bottomControllerHandleHeight),
                // drag icon
                dragIcon.centerXAnchor.constraint(equalTo: bottomContainer.centerXAnchor),
                dragIcon.topAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: Self.dragHandleTopOffset),
                // separator
                separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                separator.topAnchor.constraint(equalTo: bottomContainer.topAnchor),
                separator.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
                // bottom controller view
                bottomController.view.topAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: Self.bottomControllerHandleHeight),
                bottomController.view.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
                bottomController.view.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
                bottomControllerHeight,
                bottomControllerBottom
            ])

            self.bottomContainer = bottomContainer
            self.bottomYConstraint = bottomYConstraint
            self.bottomContainerBottomConstraint = bottomContainerBottomConstraint

            let bottomPanRecognizer = UIPanGestureRecognizer()
            bottomPanRecognizer.delegate = self
            bottomPanRecognizer.rx.event
                .subscribe(with: self, onNext: { _, recognizer in
                    toolbarDidPan(recognizer: recognizer)
                })
                .disposed(by: disposeBag)

            let tapRecognizer = UITapGestureRecognizer()
            tapRecognizer.delegate = self
            tapRecognizer.require(toFail: bottomPanRecognizer)
            tapRecognizer.rx.event
                .subscribe(with: self, onNext: { _, _ in
                    toggleBottomPosition()
                })
                .disposed(by: disposeBag)

            bottomContainer.addGestureRecognizer(bottomPanRecognizer)
            bottomContainer.addGestureRecognizer(tapRecognizer)

            func toolbarDidPan(recognizer: UIPanGestureRecognizer) {
                switch recognizer.state {
                case .began:
                    initialBottomMinY = bottomContainer.frame.minY
                    bottomController.disablePanning()

                case .changed:
                    guard let initialBottomMinY else { return }

                    let translation = recognizer.translation(in: self.view)
                    let availableHeight = view.frame.height
                    var minY = initialBottomMinY + translation.y
                    let mostlyVisibleTopOffset = BottomPosition.mostlyVisible.topOffset(availableHeight: availableHeight)
                    let hiddenTopOffset = BottomPosition.hidden.topOffset(availableHeight: availableHeight)
                    if minY < mostlyVisibleTopOffset {
                        minY = mostlyVisibleTopOffset
                    } else if minY > hiddenTopOffset {
                        minY = hiddenTopOffset
                    }

                    bottomYConstraint.constant = minY
                    view.layoutIfNeeded()

                case .ended, .failed:
                    let availableHeight = view.frame.height - keyboardHeight
                    let dragVelocity = recognizer.velocity(in: view)
                    let newPosition = position(fromYPos: bottomYConstraint.constant, containerHeight: availableHeight, velocity: dragVelocity)
                    let velocity = velocity(from: dragVelocity, currentYPos: bottomYConstraint.constant, position: newPosition, availableHeight: availableHeight)

                    set(bottomPosition: newPosition, containerHeight: view.frame.height, keyboardHeight: keyboardHeight)

                    switch newPosition {
                    case .custom:
                        view.layoutIfNeeded()

                    case .mostlyVisible, .default, .hidden:
                        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [.curveEaseOut], animations: {
                            self.view.layoutIfNeeded()
                        })
                    }

                    initialBottomMinY = nil
                    bottomController.enablePanning()

                case .cancelled, .possible:
                    break

                @unknown default:
                    break
                }

                /// Return new position for given center and velocity of handle. If velocity > 1500, it's considered a swipe and the handle
                /// is moved in swipe direction. Otherwise the handle stays in place.
                func position(fromYPos yPos: CGFloat, containerHeight: CGFloat, velocity: CGPoint) -> BottomPosition {
                    if abs(velocity.y) > 1000 {
                        // Swipe in direction of velocity
                        if yPos > BottomPosition.default.topOffset(availableHeight: containerHeight) {
                            return velocity.y > 0 ? .hidden : .default
                        } else {
                            return velocity.y > 0 ? .default : .mostlyVisible
                        }
                    }

                    if yPos > (containerHeight - Self.minVisibleBottomHeight) {
                        return velocity.y > 0 ? .hidden : .default
                    }

                    return .custom(yPos)
                }

                func velocity(from dragVelocity: CGPoint, currentYPos: CGFloat, position: BottomPosition, availableHeight: CGFloat) -> CGFloat {
                    return abs(dragVelocity.y / (position.topOffset(availableHeight: availableHeight) - currentYPos))
                }
            }

            func toggleBottomPosition() {
                switch bottomPosition {
                case .hidden:
                    set(bottomPosition: previousBottomPosition ?? .default)
                    previousBottomPosition = nil

                default:
                    previousBottomPosition = bottomPosition

                    if let controller = bottomController as? TagFilterViewController, controller.searchBar.isFirstResponder {
                        // If tag picker search bar is first responder and tag picker was toggled to hide, we should deselect the search bar
                        bottomPosition = .hidden
                        // Don't need to `set(bottomPosition:containerHeight:keyboardHeight:)` manually here, resigning search bar will send keyboard notifications and the UI will update there.
                        controller.searchBar.resignFirstResponder()
                        return
                    }

                    set(bottomPosition: .hidden)
                }

                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut, animations: {
                    self.view.layoutIfNeeded()
                })
            }
        }

        func setupKeyboardObserving() {
            NotificationCenter.default
                .keyboardWillShow
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { notification in
                    if let data = notification.keyboardData {
                        setupKeyboard(with: data)
                    }
                })
                .disposed(by: disposeBag)

            NotificationCenter.default
                .keyboardWillHide
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { notification in
                    if let data = notification.keyboardData {
                        setupKeyboard(with: data)
                    }
                })
                .disposed(by: disposeBag)

            func setupKeyboard(with keyboardData: KeyboardData) {
                keyboardHeight = keyboardData.visibleHeight

                updateBottomPosition()
                bottomContainerBottomConstraint?.constant = keyboardData.visibleHeight
                UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut, animations: {
                    self.view.layoutIfNeeded()
                })
            }
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        updateBottomPosition()
        if let splitViewController {
            // Split view controller collapsed status when the app launches is correct here, so it's used to show/hide bottom sheet for the first appearance.
            // The app may be launched in collapsed mode, if it was in such mode the last time it was moved to background.
            setBottomSheet(hidden: splitViewController.isCollapsed)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        set(bottomPosition: bottomPosition, containerHeight: size.height, keyboardHeight: keyboardHeight)

        coordinator.animate { _ in
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.updateBottomPosition()
        }
    }

    override func collapseSecondaryViewController(_ secondaryViewController: UIViewController, for splitViewController: UISplitViewController) {
        setBottomSheet(hidden: true)
        super.collapseSecondaryViewController(secondaryViewController, for: splitViewController)
    }

    override func separateSecondaryViewController(for splitViewController: UISplitViewController) -> UIViewController? {
        setBottomSheet(hidden: false)
        guard topViewController?.isKind(of: UINavigationController.self) == true else {
            // When separating from an initially collapsed split view controller, the detail view controller is not yet set.
            coordinatorDelegate?.showDefaultCollection()
            return nil
        }
        return super.separateSecondaryViewController(for: splitViewController)
    }

    // MARK: - Bottom Panning
    var isBottomSheetHidden: Bool {
        bottomContainer?.isHidden ?? true
    }

    private func setBottomSheet(hidden: Bool) {
        bottomContainer?.isHidden = hidden
        updateBottomPosition()
    }

    private func set(bottomPosition: BottomPosition, containerHeight: CGFloat, keyboardHeight: CGFloat) {
        let availableHeight = containerHeight - keyboardHeight
        let topOffset = bottomPosition.topOffset(availableHeight: availableHeight)
        bottomYConstraint?.constant = topOffset
        self.bottomPosition = bottomPosition
        for viewController in viewControllers {
            (viewController as? BottomSheetObserver)?.bottomSheetUpdated(hidden: isBottomSheetHidden, containerHeight: containerHeight, topOffset: topOffset)
        }
    }

    private func set(bottomPosition: BottomPosition) {
        set(bottomPosition: bottomPosition, containerHeight: view.frame.height, keyboardHeight: keyboardHeight)
    }

    private func updateBottomPosition() {
        set(bottomPosition: bottomPosition)
    }
}

extension MasterContainerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let bottomContainer else { return false }

        let location = gestureRecognizer.location(in: bottomContainer)

        if gestureRecognizer is UITapGestureRecognizer {
            return location.y <= Self.bottomContainerTappableHeight
        }

        if gestureRecognizer is UIPanGestureRecognizer {
            return location.y <= Self.bottomContainerDraggableHeight
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

extension MasterContainerViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        updateBottomPosition()
    }
}
