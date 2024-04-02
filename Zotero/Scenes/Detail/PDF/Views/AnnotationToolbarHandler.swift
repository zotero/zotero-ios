//
//  AnnotationToolbarHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 06.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol AnnotationToolbarHandlerDelegate: AnyObject {
    var toolbarState: AnnotationToolbarHandler.State { get set }
    var statusBarVisible: Bool { get set }
    var statusBarHeight: CGFloat { get }
    var isNavigationBarHidden: Bool { get }
    var navigationBarHeight: CGFloat { get }
    var isSidebarHidden: Bool { get }
    var isCompactWidth: Bool { get }
    var containerView: UIView { get }
    var documentView: UIView { get }
    var toolbarLeadingAnchor: NSLayoutXAxisAnchor { get }
    var toolbarLeadingSafeAreaAnchor: NSLayoutXAxisAnchor { get }

    func layoutIfNeeded()
    func setNeedsLayout()
    func hideSidebarIfNeeded(forPosition position: AnnotationToolbarHandler.State.Position, isToolbarSmallerThanMinWidth: Bool, animated: Bool)
    func setNavigationBar(hidden: Bool, animated: Bool)
    func setNavigationBar(alpha: CGFloat)
    func setDocumentInterface(hidden: Bool)
    func topDidChange(forToolbarState state: AnnotationToolbarHandler.State)
    func updateStatusBar()
}

final class AnnotationToolbarHandler: NSObject {
    struct State: Codable {
        enum Position: Int, Codable {
            case leading = 0
            case trailing = 1
            case top = 2
            case pinned = 3
        }

        let position: Position
        let visible: Bool
    }

    private unowned let controller: AnnotationToolbarViewController
    private unowned let delegate: AnnotationToolbarHandlerDelegate
    static let toolbarCompactInset: CGFloat = 12
    static let toolbarFullInset: CGFloat = 20
    static let minToolbarWidth: CGFloat = 300
    static let annotationToolbarDragHandleHeight: CGFloat = 50
    private let previewBackgroundColor: UIColor
    private let previewDashColor: UIColor
    private let previewSelectedBackgroundColor: UIColor
    private let previewSelectedDashColor: UIColor
    private let disposeBag: DisposeBag

    private var toolbarInitialFrame: CGRect?
    private weak var toolbarTop: NSLayoutConstraint!
    private var toolbarLeading: NSLayoutConstraint!
    private var toolbarLeadingSafeArea: NSLayoutConstraint!
    private var toolbarTrailing: NSLayoutConstraint!
    private var toolbarTrailingSafeArea: NSLayoutConstraint!
    weak var dragHandleLongPressRecognizer: UILongPressGestureRecognizer!
    private weak var toolbarPreviewsOverlay: UIView!
    private weak var toolbarLeadingPreview: DashedView!
    private weak var inbetweenTopDashedView: DashedView!
    private weak var toolbarLeadingPreviewHeight: NSLayoutConstraint!
    private weak var toolbarTrailingPreview: DashedView!
    private weak var toolbarTrailingPreviewHeight: NSLayoutConstraint!
    private weak var toolbarTopPreview: DashedView!
    private weak var toolbarPinnedPreview: DashedView!
    private weak var toolbarPinnedPreviewHeight: NSLayoutConstraint!

    var stateDidChange: ((State) -> Void)?
    var didHide: (() -> Void)?

    init(controller: AnnotationToolbarViewController, delegate: AnnotationToolbarHandlerDelegate) {
        self.controller = controller
        self.delegate = delegate
        previewDashColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
        previewBackgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.15)
        previewSelectedDashColor = Asset.Colors.zoteroBlueWithDarkMode.color
        previewSelectedBackgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
        disposeBag = DisposeBag()

        super.init()

        setupController()
        createViewsWithConstraints()
        createGestureRecognizers()

        func setupController() {
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            controller.view.setContentHuggingPriority(.required, for: .horizontal)
            controller.view.setContentHuggingPriority(.required, for: .vertical)
        }

        func createViewsWithConstraints() {
            let previewsOverlay = UIView()
            previewsOverlay.translatesAutoresizingMaskIntoConstraints = false
            previewsOverlay.backgroundColor = .clear
            previewsOverlay.isHidden = true

            let topPreview = DashedView(type: .partialStraight(sides: [.left, .right, .bottom]))
            setup(toolbarPositionView: topPreview)
            let inbetweenTopDash = DashedView(type: .partialStraight(sides: .bottom))
            setup(toolbarPositionView: inbetweenTopDash)
            let pinnedPreview = DashedView(type: .partialStraight(sides: [.left, .right, .top]))
            setup(toolbarPositionView: pinnedPreview)
            let leadingPreview = DashedView(type: .rounded(cornerRadius: 8))
            leadingPreview.translatesAutoresizingMaskIntoConstraints = false
            setup(toolbarPositionView: leadingPreview)
            let trailingPreview = DashedView(type: .rounded(cornerRadius: 8))
            trailingPreview.translatesAutoresizingMaskIntoConstraints = false
            setup(toolbarPositionView: trailingPreview)

            let topPreviewContainer = UIStackView(arrangedSubviews: [pinnedPreview, inbetweenTopDash, topPreview])
            topPreviewContainer.translatesAutoresizingMaskIntoConstraints = false
            topPreviewContainer.axis = .vertical

            delegate.documentView.insertSubview(previewsOverlay, belowSubview: controller.view)
            previewsOverlay.addSubview(topPreviewContainer)
            previewsOverlay.addSubview(leadingPreview)
            previewsOverlay.addSubview(trailingPreview)

            toolbarLeading = controller.view.leadingAnchor.constraint(equalTo: delegate.toolbarLeadingAnchor, constant: Self.toolbarFullInset)
            toolbarLeading.priority = .init(999)
            toolbarLeadingSafeArea = controller.view.leadingAnchor.constraint(equalTo: delegate.toolbarLeadingSafeAreaAnchor)
            toolbarTrailing = delegate.containerView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: Self.toolbarFullInset)
            toolbarTrailingSafeArea = delegate.containerView.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: Self.toolbarFullInset)
            let toolbarTop = controller.view.topAnchor.constraint(equalTo: delegate.containerView.topAnchor, constant: Self.toolbarCompactInset)
            let leadingPreviewHeight = leadingPreview.heightAnchor.constraint(equalToConstant: 50)
            let trailingPreviewHeight = trailingPreview.heightAnchor.constraint(equalToConstant: 50)
            let pinnedPreviewHeight = pinnedPreview.heightAnchor.constraint(equalToConstant: controller.size)

            NSLayoutConstraint.activate([
                toolbarTop,
                toolbarLeadingSafeArea,
                previewsOverlay.topAnchor.constraint(equalTo: delegate.containerView.topAnchor),
                previewsOverlay.bottomAnchor.constraint(equalTo: delegate.containerView.safeAreaLayoutGuide.bottomAnchor),
                previewsOverlay.leadingAnchor.constraint(equalTo: delegate.documentView.leadingAnchor),
                previewsOverlay.trailingAnchor.constraint(equalTo: delegate.containerView.trailingAnchor),
                topPreviewContainer.topAnchor.constraint(equalTo: previewsOverlay.topAnchor),
                topPreviewContainer.leadingAnchor.constraint(equalTo: previewsOverlay.leadingAnchor),
                previewsOverlay.trailingAnchor.constraint(equalTo: topPreviewContainer.trailingAnchor),
                pinnedPreviewHeight,
                topPreview.heightAnchor.constraint(equalToConstant: controller.size),
                leadingPreview.leadingAnchor.constraint(equalTo: previewsOverlay.safeAreaLayoutGuide.leadingAnchor, constant: Self.toolbarFullInset),
                leadingPreview.topAnchor.constraint(equalTo: topPreviewContainer.bottomAnchor, constant: Self.toolbarCompactInset),
                leadingPreviewHeight,
                leadingPreview.widthAnchor.constraint(equalToConstant: controller.size),
                previewsOverlay.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: trailingPreview.trailingAnchor, constant: Self.toolbarFullInset),
                trailingPreview.topAnchor.constraint(equalTo: topPreviewContainer.bottomAnchor, constant: Self.toolbarCompactInset),
                trailingPreviewHeight,
                trailingPreview.widthAnchor.constraint(equalToConstant: controller.size),
                inbetweenTopDash.heightAnchor.constraint(equalToConstant: 2 / UIScreen.main.scale)
            ])

            self.toolbarTop = toolbarTop
            toolbarPreviewsOverlay = previewsOverlay
            toolbarTopPreview = topPreview
            toolbarPinnedPreview = pinnedPreview
            toolbarLeadingPreview = leadingPreview
            toolbarLeadingPreviewHeight = leadingPreviewHeight
            toolbarTrailingPreview = trailingPreview
            toolbarTrailingPreviewHeight = trailingPreviewHeight
            toolbarPinnedPreviewHeight = pinnedPreviewHeight
            inbetweenTopDashedView = inbetweenTopDash

            func setup(toolbarPositionView view: DashedView) {
                view.backgroundColor = previewBackgroundColor
                view.dashColor = previewDashColor
                view.layer.masksToBounds = true
            }
        }

        func createGestureRecognizers() {
            let panRecognizer = UIPanGestureRecognizer()
            panRecognizer.delegate = self
            panRecognizer.rx.event
                .subscribe(onNext: { [weak self] recognizer in
                    self?.toolbarDidPan(recognizer: recognizer)
                })
                .disposed(by: disposeBag)
            controller.view.addGestureRecognizer(panRecognizer)

            let longPressRecognizer = UILongPressGestureRecognizer()
            longPressRecognizer.delegate = self
            longPressRecognizer.rx.event
                .subscribe(onNext: { [weak self] recognizer in
                    self?.didTapToolbar(recognizer: recognizer)
                })
                .disposed(by: disposeBag)
            dragHandleLongPressRecognizer = longPressRecognizer
            controller.view.addGestureRecognizer(longPressRecognizer)
        }
    }

    // MARK: - Layout

    func performInitialLayout() {
        var rotation: AnnotationToolbarViewController.Rotation
        switch delegate.toolbarState.position {
        case .leading, .trailing:
            rotation = .vertical

        case .top, .pinned:
            rotation = .horizontal
        }
        controller.set(rotation: rotation, isCompactSize: isCompactSize(for: rotation))
        delegate.layoutIfNeeded()
    }
    
    func viewIsAppearing(editingEnabled: Bool) {
        setConstraints(for: delegate.toolbarState.position, statusBarVisible: delegate.statusBarVisible)
        delegate.topDidChange(forToolbarState: delegate.toolbarState)
        setAnnotationToolbarHandleMinimumLongPressDuration(forPosition: delegate.toolbarState.position)
        if delegate.toolbarState.visible && editingEnabled {
            showAnnotationToolbar(state: delegate.toolbarState, statusBarVisible: delegate.statusBarVisible, animated: false)
        } else {
            hideAnnotationToolbar(newState: delegate.toolbarState, statusBarVisible: delegate.statusBarVisible, animated: false)
        }
    }

    func viewWillTransitionToNewSize() {
        controller.prepareForSizeChange()
        controller.updateAdditionalButtons()
        setConstraints(for: delegate.toolbarState.position, statusBarVisible: delegate.statusBarVisible)
        delegate.topDidChange(forToolbarState: delegate.toolbarState)
        delegate.layoutIfNeeded()
        controller.sizeDidChange()
    }

    func interfaceVisibilityDidChange() {
        delegate.topDidChange(forToolbarState: delegate.toolbarState)
        setConstraints(for: delegate.toolbarState.position, statusBarVisible: delegate.statusBarVisible)
    }

    private func isCompactSize(for rotation: AnnotationToolbarViewController.Rotation) -> Bool {
        switch rotation {
        case .horizontal:
            return delegate.isCompactWidth

        case .vertical:
            return delegate.containerView.frame.height <= 400
        }
    }

    func topOffsets(statusBarVisible: Bool) -> (statusBarHeight: CGFloat, navigationBarHeight: CGFloat, total: CGFloat) {
        let statusBarOffset = statusBarVisible || UIDevice.current.userInterfaceIdiom != .pad ? delegate.statusBarHeight : 0
        let navigationBarOffset = statusBarVisible ? delegate.navigationBarHeight : 0
        return (statusBarOffset, navigationBarOffset, statusBarOffset + navigationBarOffset)
    }

    // MARK: - Actions

    func enableLeadingSafeConstraint() {
        toolbarLeading.isActive = false
        toolbarLeadingSafeArea.isActive = true
    }

    func disableLeadingSafeConstraint() {
        toolbarLeadingSafeArea.isActive = false
        toolbarLeading.isActive = true
    }

    func set(hidden: Bool, animated: Bool) {
        delegate.toolbarState = State(position: delegate.toolbarState.position, visible: !hidden)

        if hidden {
            hideAnnotationToolbar(newState: delegate.toolbarState, statusBarVisible: delegate.statusBarVisible, animated: animated)
        } else {
            showAnnotationToolbar(state: delegate.toolbarState, statusBarVisible: delegate.statusBarVisible, animated: animated)
        }
    }

    private func showAnnotationToolbar(state: State, statusBarVisible: Bool, animated: Bool) {
        controller.prepareForSizeChange()
        setConstraints(for: state.position, statusBarVisible: statusBarVisible)
        controller.view.isHidden = false
        delegate.layoutIfNeeded()
        controller.sizeDidChange()
        delegate.layoutIfNeeded()
        delegate.topDidChange(forToolbarState: state)

        delegate.hideSidebarIfNeeded(forPosition: state.position, isToolbarSmallerThanMinWidth: controller.view.frame.width < Self.minToolbarWidth, animated: animated)

        let navigationBarHidden = !statusBarVisible || state.position == .pinned

        if !animated {
            controller.view.alpha = 1
            delegate.setNavigationBar(hidden: navigationBarHidden, animated: false)
            delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
            delegate.layoutIfNeeded()
            return
        }

        if !navigationBarHidden, delegate.isNavigationBarHidden {
            delegate.setNavigationBar(hidden: false, animated: false)
            delegate.setNavigationBar(alpha: 0)
        }

        UIView.animate(withDuration: 0.2, animations: { [weak self] in
            guard let self else { return }
            controller.view.alpha = 1
            delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
            delegate.layoutIfNeeded()
        }, completion: { [weak self] finished in
            guard let self, finished, navigationBarHidden else { return }
            delegate.setNavigationBar(hidden: true, animated: false)
        })
    }

    private func hideAnnotationToolbar(newState: State, statusBarVisible: Bool, animated: Bool) {
        delegate.topDidChange(forToolbarState: newState)

        if !animated {
            delegate.layoutIfNeeded()
            controller.view.alpha = 0
            controller.view.isHidden = true
            delegate.setNavigationBar(alpha: statusBarVisible ? 1 : 0)
            delegate.setNavigationBar(hidden: !statusBarVisible, animated: false)
            return
        }

        if statusBarVisible && delegate.isNavigationBarHidden {
            delegate.setNavigationBar(hidden: false, animated: false)
            delegate.setNavigationBar(alpha: 0)
        }

        UIView.animate(withDuration: 0.2, animations: { [weak self] in
            guard let self else { return }
            delegate.layoutIfNeeded()
            controller.view.alpha = 0
            delegate.setNavigationBar(alpha: statusBarVisible ? 1 : 0)
        }, completion: { [weak self] finished in
            guard let self, finished else { return }
            controller.view.isHidden = true
            didHide?()
            if !statusBarVisible {
                delegate.setNavigationBar(hidden: true, animated: false)
            }
        })
    }

    private func setConstraints(for position: State.Position, statusBarVisible: Bool) {
        let rotation: AnnotationToolbarViewController.Rotation
        switch position {
        case .top, .pinned:
            rotation = .horizontal

        case .leading, .trailing:
            rotation = .vertical
        }
        let isCompact = isCompactSize(for: rotation)
        switch position {
        case .leading:
            setupLeadingConstraints(isCompact: isCompact, statusBarVisible: statusBarVisible)

        case .trailing:
            setupTrailingConstraints(isCompact: isCompact, statusBarVisible: statusBarVisible)

        case .top:
            setupTopConstraints(isCompact: isCompact, isPinned: false, statusBarVisible: statusBarVisible)

        case .pinned:
            setupTopConstraints(isCompact: isCompact, isPinned: true, statusBarVisible: statusBarVisible)
        }

        func setupLeadingConstraints(isCompact: Bool, statusBarVisible: Bool) {
            let inset = isCompact ? Self.toolbarCompactInset : Self.toolbarFullInset
            toolbarTrailing.isActive = false
            toolbarTrailingSafeArea.isActive = false
            if !delegate.isSidebarHidden {
                toolbarLeadingSafeArea.isActive = false
                toolbarLeading.isActive = true
                toolbarLeading.constant = inset
            } else {
                toolbarLeading.isActive = false
                toolbarLeadingSafeArea.isActive = true
                toolbarLeadingSafeArea.constant = inset
            }
            toolbarTop.constant = inset + topOffsets(statusBarVisible: statusBarVisible).total
            controller.set(rotation: .vertical, isCompactSize: isCompact)
        }

        func setupTrailingConstraints(isCompact: Bool, statusBarVisible: Bool) {
            let inset = isCompact ? Self.toolbarCompactInset : Self.toolbarFullInset
            toolbarLeading.isActive = false
            toolbarLeadingSafeArea.isActive = false
            toolbarTrailing.isActive = false
            toolbarTrailingSafeArea.isActive = true
            toolbarTrailingSafeArea.constant = inset
            toolbarTop.constant = inset + topOffsets(statusBarVisible: statusBarVisible).total
            controller.set(rotation: .vertical, isCompactSize: isCompact)
        }

        func setupTopConstraints(isCompact: Bool, isPinned: Bool, statusBarVisible: Bool) {
            toolbarLeadingSafeArea.isActive = false
            toolbarTrailingSafeArea.isActive = false
            toolbarTrailing.isActive = true
            toolbarTrailing.constant = 0
            toolbarLeading.isActive = true
            toolbarLeading.constant = 0
            let topOffsets = topOffsets(statusBarVisible: statusBarVisible)
            toolbarTop.constant = isPinned ? topOffsets.statusBarHeight : topOffsets.total
            controller.set(rotation: .horizontal, isCompactSize: isCompact)
        }
    }

    // MARK: - Gesture recognizers

    private func isSwipe(fromVelocity velocity: CGPoint) -> Bool {
        return velocity.y <= -1500 || abs(velocity.x) >= 1500
    }

    private func didTapToolbar(recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            setHighlightSelected(at: delegate.toolbarState.position)
            showPreviews()

        case .ended, .failed:
            hidePreviewsIfNeeded()

        default:
            break
        }

        func hidePreviewsIfNeeded() {
            guard toolbarPreviewsOverlay.alpha == 1 else { return }

            UIView.animate(withDuration: 0.2, animations: { [weak self] in
                guard let self else { return }
                delegate.setNavigationBar(alpha: 1)
                toolbarPreviewsOverlay.alpha = 0
            }, completion: { [weak self] finished in
                guard let self, finished else { return }
                toolbarPreviewsOverlay.isHidden = true
            })
        }
    }

    private func toolbarDidPan(recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            toolbarInitialFrame = controller.view.frame

        case .changed:
            guard let originalFrame = toolbarInitialFrame else { return }
            let translation = recognizer.translation(in: controller.view)
            let location = recognizer.location(in: delegate.containerView)
            let position = position(
                fromTouch: location,
                frame: controller.view.frame,
                containerFrame: delegate.documentView.frame,
                velocity: CGPoint(),
                statusBarVisible: delegate.statusBarVisible
            )

            controller.view.frame = originalFrame.offsetBy(dx: translation.x, dy: translation.y)

            showPreviewsOnDragIfNeeded(translation: translation, velocity: recognizer.velocity(in: delegate.containerView), currentPosition: delegate.toolbarState.position)

            if !toolbarPreviewsOverlay.isHidden {
                setHighlightSelected(at: position)
            }

        case .ended, .failed:
            let velocity = recognizer.velocity(in: delegate.containerView)
            let location = recognizer.location(in: delegate.containerView)
            let position = position(
                fromTouch: location,
                frame: controller.view.frame,
                containerFrame: delegate.documentView.frame,
                velocity: velocity,
                statusBarVisible: delegate.statusBarVisible
            )
            let newState = State(position: position, visible: true)

            if position == .top && delegate.toolbarState.position == .pinned {
                delegate.statusBarVisible = true
            }
            set(toolbarPosition: position, oldPosition: delegate.toolbarState.position, velocity: velocity, statusBarVisible: delegate.statusBarVisible)
            setAnnotationToolbarHandleMinimumLongPressDuration(forPosition: position)
            delegate.toolbarState = newState
            toolbarInitialFrame = nil

        default:
            break
        }

        /// Return new position for given touch point and velocity of toolbar. The user can pan up/left/right to move the toolbar. If velocity > 1500, it's considered a swipe and the toolbar is moved
        /// in swipe direction. Otherwise the toolbar is pinned to closest point from touch.
        func position(fromTouch point: CGPoint, frame: CGRect, containerFrame: CGRect, velocity: CGPoint, statusBarVisible: Bool) -> State.Position {
            if isSwipe(fromVelocity: velocity) {
                // Move in direction of swipe
                if abs(velocity.y) > abs(velocity.x) && containerFrame.size.width >= Self.minToolbarWidth {
                    return .top
                }
                return velocity.x < 0 ? .leading : .trailing
            }

            let topViewBottomRightPoint = toolbarTopPreview.convert(CGPoint(x: toolbarTopPreview.bounds.maxX, y: toolbarTopPreview.bounds.maxY), to: delegate.containerView)

            if point.y < topViewBottomRightPoint.y {
                let pinnedViewBottomRightPoint = toolbarPinnedPreview.convert(CGPoint(x: toolbarPinnedPreview.frame.maxX, y: toolbarPinnedPreview.frame.maxY), to: delegate.containerView)
                return point.y < pinnedViewBottomRightPoint.y ? .pinned : .top
            }

            let xPos = point.x - containerFrame.minX

            if point.y < (topViewBottomRightPoint.y + 150) {
                if xPos > 150 && xPos < (containerFrame.size.width - 150) {
                    return .top
                }
                return xPos <= 150 ? .leading : .trailing
            }

            return xPos > containerFrame.size.width / 2 ? .trailing : .leading
        }

        func showPreviewsOnDragIfNeeded(translation: CGPoint, velocity: CGPoint, currentPosition: State.Position) {
            guard toolbarPreviewsOverlay.isHidden else { return }

            let distance = sqrt((translation.x * translation.x) + (translation.y * translation.y))
            let distanceThreshold: CGFloat = (currentPosition == .pinned || currentPosition == .top) ? 0 : 70

            guard distance > distanceThreshold && !isSwipe(fromVelocity: velocity) else { return }

            showPreviews()
        }

        func set(toolbarPosition newPosition: State.Position, oldPosition: State.Position, velocity velocityPoint: CGPoint, statusBarVisible: Bool) {
            let navigationBarHidden = newPosition == .pinned || !statusBarVisible

            switch (newPosition, oldPosition) {
            case (.leading, .leading), (.trailing, .trailing), (.top, .top), (.pinned, .pinned):
                // Position didn't change, move to initial frame
                let frame = toolbarInitialFrame ?? CGRect()
                let velocity = velocity(from: velocityPoint, newPosition: newPosition)

                if !navigationBarHidden && delegate.isNavigationBarHidden {
                    delegate.setNavigationBar(hidden: false, animated: false)
                    delegate.setNavigationBar(alpha: 0)
                }

                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [.curveEaseOut], animations: { [weak self] in
                    guard let self else { return }
                    toolbarPreviewsOverlay.alpha = 0
                    controller.view.frame = frame
                    delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
                    delegate.setDocumentInterface(hidden: !statusBarVisible)
                }, completion: { [weak self] finished in
                    guard let self, finished else { return }
                    toolbarPreviewsOverlay.isHidden = true
                    if navigationBarHidden {
                        delegate.setNavigationBar(hidden: true, animated: false)
                    }
                })

            case (.leading, .trailing), (.trailing, .leading), (.top, .pinned), (.pinned, .top):
                // Move from side to side or vertically
                let velocity = velocity(from: velocityPoint, newPosition: newPosition)
                setConstraints(for: newPosition, statusBarVisible: statusBarVisible)
                delegate.topDidChange(forToolbarState: State(position: newPosition, visible: true))
                delegate.setNeedsLayout()

                delegate.hideSidebarIfNeeded(forPosition: newPosition, isToolbarSmallerThanMinWidth: controller.view.frame.width < Self.minToolbarWidth, animated: true)

                if !navigationBarHidden && delegate.isNavigationBarHidden {
                    delegate.setNavigationBar(hidden: false, animated: false)
                    delegate.setNavigationBar(alpha: 0)
                }

                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: { [weak self] in
                    guard let self else { return }
                    delegate.layoutIfNeeded()
                    toolbarPreviewsOverlay.alpha = 0
                    delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
                    delegate.setDocumentInterface(hidden: !statusBarVisible)
                    delegate.updateStatusBar()
                }, completion: { [weak self] finished in
                    guard let self, finished else { return }
                    toolbarPreviewsOverlay.isHidden = true
                    if navigationBarHidden {
                        delegate.setNavigationBar(hidden: true, animated: false)
                    }
                })

            case (.top, .leading), (.top, .trailing), (.leading, .top), (.leading, .pinned), (.trailing, .top), (.trailing, .pinned), (.pinned, .leading), (.pinned, .trailing):
                let velocity = velocity(from: velocityPoint, newPosition: newPosition)
                UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: { [weak self] in
                    guard let self else { return }
                    let newFrame = controller.view.frame.offsetBy(dx: velocityPoint.x / 10, dy: velocityPoint.y / 10)
                    controller.view.frame = newFrame
                    controller.view.alpha = 0
                }, completion: { [weak self] finished in
                    guard let self, finished else { return }

                    if !navigationBarHidden && delegate.isNavigationBarHidden {
                        delegate.setNavigationBar(hidden: false, animated: false)
                        delegate.setNavigationBar(alpha: 0)
                    }

                    controller.prepareForSizeChange()
                    setConstraints(for: newPosition, statusBarVisible: statusBarVisible)
                    delegate.layoutIfNeeded()
                    controller.sizeDidChange()
                    delegate.layoutIfNeeded()
                    delegate.topDidChange(forToolbarState: State(position: newPosition, visible: true))

                    delegate.hideSidebarIfNeeded(forPosition: newPosition, isToolbarSmallerThanMinWidth: controller.view.frame.width < Self.minToolbarWidth, animated: true)

                    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: { [weak self] in
                        guard let self else { return }
                        controller.view.alpha = 1
                        delegate.layoutIfNeeded()
                        toolbarPreviewsOverlay.alpha = 0
                        delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
                        delegate.setDocumentInterface(hidden: !statusBarVisible)
                        delegate.updateStatusBar()
                    }, completion: { [weak self] finished in
                        guard let self, finished else { return }
                        toolbarPreviewsOverlay.isHidden = true
                        if navigationBarHidden {
                            delegate.setNavigationBar(hidden: true, animated: false)
                        }
                    })
                })
            }

            func velocity(from panVelocity: CGPoint, newPosition: State.Position) -> CGFloat {
                let currentPosition: CGFloat
                let endPosition: CGFloat
                let velocity: CGFloat

                switch newPosition {
                case .top:
                    velocity = panVelocity.y
                    currentPosition = controller.view.frame.minY
                    endPosition = delegate.containerView.safeAreaInsets.top

                case .leading:
                    velocity = panVelocity.x
                    currentPosition = controller.view.frame.minX
                    endPosition = 0

                case .trailing:
                    velocity = panVelocity.x
                    currentPosition = controller.view.frame.maxX
                    endPosition = delegate.containerView.frame.width

                case .pinned:
                    velocity = panVelocity.y
                    currentPosition = controller.view.frame.minY
                    endPosition = delegate.containerView.safeAreaInsets.top
                }

                return abs(velocity / (endPosition - currentPosition))
            }
        }
    }

    private func setAnnotationToolbarHandleMinimumLongPressDuration(forPosition position: State.Position) {
        switch position {
        case .leading, .trailing:
            dragHandleLongPressRecognizer.minimumPressDuration = 0.3

        case .top, .pinned:
            dragHandleLongPressRecognizer.minimumPressDuration = 0
        }
    }

    // MARK: - Previews

    private func showPreviews() {
        updatePositionOverlayViews(
            currentHeight: controller.view.frame.height,
            containerSize: delegate.documentView.frame.size,
            position: delegate.toolbarState.position,
            statusBarVisible: delegate.statusBarVisible
        )
        toolbarPreviewsOverlay.alpha = 0
        toolbarPreviewsOverlay.isHidden = false

        UIView.animate(withDuration: 0.2, animations: { [weak self] in
            guard let self else { return }
            toolbarPreviewsOverlay.alpha = 1
            delegate.setNavigationBar(alpha: 0)
        })

        func updatePositionOverlayViews(currentHeight: CGFloat, containerSize: CGSize, position: State.Position, statusBarVisible: Bool) {
            let topToolbarsAvailable = containerSize.width >= Self.minToolbarWidth
            let verticalHeight: CGFloat
            switch position {
            case .leading, .trailing:
                // Position the preview so that the bottom of preview matches actual bottom of toolbar, add offset for dashed border
                let offset = controller.size + (statusBarVisible ? 0 : controller.size)
                verticalHeight = currentHeight - offset + (DashedView.dashWidth * 2) + 1

            case .top, .pinned:
                verticalHeight = min(containerSize.height - currentHeight - (position == .pinned ? delegate.navigationBarHeight : 0), AnnotationToolbarViewController.estimatedVerticalHeight)
            }

            toolbarPinnedPreview.isHidden = !topToolbarsAvailable || (position == .top && !statusBarVisible)
            inbetweenTopDashedView.isHidden = toolbarPinnedPreview.isHidden
            if !toolbarPinnedPreview.isHidden {
                // Change height based on current position so that preview is shown around currently visible toolbar
                let baseHeight = position == .pinned ? controller.size : delegate.navigationBarHeight
                toolbarPinnedPreviewHeight.constant = baseHeight + topOffsets(statusBarVisible: statusBarVisible).statusBarHeight - (position == .top ? 1 : 0)
            }
            toolbarTopPreview.isHidden = !topToolbarsAvailable
            toolbarLeadingPreviewHeight.constant = verticalHeight
            toolbarTrailingPreviewHeight.constant = verticalHeight
            toolbarPreviewsOverlay.layoutIfNeeded()
        }
    }

    private func setHighlightSelected(at position: State.Position) {
        switch position {
        case .top:
            toolbarLeadingPreview.backgroundColor = previewBackgroundColor
            toolbarLeadingPreview.dashColor = previewDashColor
            toolbarTrailingPreview.backgroundColor = previewBackgroundColor
            toolbarTrailingPreview.dashColor = previewDashColor
            toolbarTopPreview.backgroundColor = previewSelectedBackgroundColor
            toolbarTopPreview.dashColor = previewSelectedDashColor
            toolbarPinnedPreview.backgroundColor = previewBackgroundColor
            toolbarPinnedPreview.dashColor = previewDashColor

        case .leading:
            toolbarLeadingPreview.backgroundColor = previewSelectedBackgroundColor
            toolbarLeadingPreview.dashColor = previewSelectedDashColor
            toolbarTrailingPreview.backgroundColor = previewBackgroundColor
            toolbarTrailingPreview.dashColor = previewDashColor
            toolbarTopPreview.backgroundColor = previewBackgroundColor
            toolbarTopPreview.dashColor = previewDashColor
            toolbarPinnedPreview.backgroundColor = previewBackgroundColor
            toolbarPinnedPreview.dashColor = previewDashColor

        case .trailing:
            toolbarLeadingPreview.backgroundColor = previewBackgroundColor
            toolbarLeadingPreview.dashColor = previewDashColor
            toolbarTrailingPreview.backgroundColor = previewSelectedBackgroundColor
            toolbarTrailingPreview.dashColor = previewSelectedDashColor
            toolbarTopPreview.backgroundColor = previewBackgroundColor
            toolbarTopPreview.dashColor = previewDashColor
            toolbarPinnedPreview.backgroundColor = previewBackgroundColor
            toolbarPinnedPreview.dashColor = previewDashColor

        case .pinned:
            toolbarLeadingPreview.backgroundColor = previewBackgroundColor
            toolbarLeadingPreview.dashColor = previewDashColor
            toolbarTrailingPreview.backgroundColor = previewBackgroundColor
            toolbarTrailingPreview.dashColor = previewDashColor
            toolbarTopPreview.backgroundColor = previewBackgroundColor
            toolbarTopPreview.dashColor = previewDashColor
            toolbarPinnedPreview.backgroundColor = previewSelectedBackgroundColor
            toolbarPinnedPreview.dashColor = previewSelectedDashColor
        }
    }
}

extension AnnotationToolbarHandler: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let longPressRecognizer = gestureRecognizer as? UILongPressGestureRecognizer else { return true }

        let location = longPressRecognizer.location(in: controller.view)
        let currentLocation: CGFloat
        let border: CGFloat

        switch delegate.toolbarState.position {
        case .pinned, .top:
            currentLocation = location.x
            border = controller.view.frame.width - Self.annotationToolbarDragHandleHeight

        case .leading, .trailing:
            currentLocation = location.y
            border = controller.view.frame.height - Self.annotationToolbarDragHandleHeight
        }
        return currentLocation >= border
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
