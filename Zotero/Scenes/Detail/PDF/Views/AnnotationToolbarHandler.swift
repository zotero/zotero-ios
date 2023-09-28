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
    var statusBarHeight: CGFloat { get set }
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
    static let toolbarFullInsetInset: CGFloat = 20
    static let minToolbarWidth: CGFloat = 300
    private static let annotationToolbarDragHandleHeight: CGFloat = 50
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

    init(controller _controller: AnnotationToolbarViewController, delegate _delegate: AnnotationToolbarHandlerDelegate) {
        controller = _controller
        delegate = _delegate
        previewDashColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
        previewBackgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.15)
        previewSelectedDashColor = Asset.Colors.zoteroBlueWithDarkMode.color
        previewSelectedBackgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
        disposeBag = DisposeBag()

        super.init()

        setupController()
        createViewsWithConstraints()
        createGestureRecognizers()

        func createGestureRecognizers() {
            let panRecognizer = UIPanGestureRecognizer()
            panRecognizer.delegate = self
            panRecognizer.rx.event
                .subscribe(with: self, onNext: { `self`, recognizer in
                    self.toolbarDidPan(recognizer: recognizer)
                })
                .disposed(by: disposeBag)
            controller.view.addGestureRecognizer(panRecognizer)

            let longPressRecognizer = UILongPressGestureRecognizer()
            longPressRecognizer.delegate = self
            longPressRecognizer.rx.event
                .subscribe(with: self, onNext: { `self`, recognizer in
                    self.didTapToolbar(recognizer: recognizer)
                })
                .disposed(by: disposeBag)
            dragHandleLongPressRecognizer = longPressRecognizer
            controller.view.addGestureRecognizer(longPressRecognizer)
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

            toolbarLeading = controller.view.leadingAnchor.constraint(equalTo: delegate.toolbarLeadingAnchor, constant: Self.toolbarFullInsetInset)
            toolbarLeading.priority = .init(999)
            toolbarLeadingSafeArea = controller.view.leadingAnchor.constraint(equalTo: delegate.toolbarLeadingSafeAreaAnchor)
            toolbarTrailing = delegate.containerView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: Self.toolbarFullInsetInset)
            toolbarTrailingSafeArea = delegate.containerView.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: Self.toolbarFullInsetInset)
            let _toolbarTop = controller.view.topAnchor.constraint(equalTo: delegate.containerView.topAnchor, constant: Self.toolbarCompactInset)
            let leadingPreviewHeight = leadingPreview.heightAnchor.constraint(equalToConstant: 50)
            let trailingPreviewHeight = trailingPreview.heightAnchor.constraint(equalToConstant: 50)
            let pinnedPreviewHeight = pinnedPreview.heightAnchor.constraint(equalToConstant: controller.size)

            NSLayoutConstraint.activate([
                _toolbarTop,
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
                leadingPreview.leadingAnchor.constraint(equalTo: previewsOverlay.safeAreaLayoutGuide.leadingAnchor, constant: Self.toolbarFullInsetInset),
                leadingPreview.topAnchor.constraint(equalTo: topPreviewContainer.bottomAnchor, constant: Self.toolbarCompactInset),
                leadingPreviewHeight,
                leadingPreview.widthAnchor.constraint(equalToConstant: controller.size),
                previewsOverlay.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: trailingPreview.trailingAnchor, constant: Self.toolbarFullInsetInset),
                trailingPreview.topAnchor.constraint(equalTo: topPreviewContainer.bottomAnchor, constant: Self.toolbarCompactInset),
                trailingPreviewHeight,
                trailingPreview.widthAnchor.constraint(equalToConstant: controller.size),
                inbetweenTopDash.heightAnchor.constraint(equalToConstant: 2 / UIScreen.main.scale)
            ])

            toolbarTop = _toolbarTop
            toolbarPreviewsOverlay = previewsOverlay
            toolbarTopPreview = topPreview
            toolbarPinnedPreview = pinnedPreview
            toolbarLeadingPreview = leadingPreview
            toolbarLeadingPreviewHeight = leadingPreviewHeight
            toolbarTrailingPreview = trailingPreview
            toolbarTrailingPreviewHeight = trailingPreviewHeight
            toolbarPinnedPreviewHeight = pinnedPreviewHeight
            inbetweenTopDashedView = inbetweenTopDash
        }

        func setupController() {
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            controller.view.setContentHuggingPriority(.required, for: .horizontal)
            controller.view.setContentHuggingPriority(.required, for: .vertical)
        }

        func setup(toolbarPositionView view: DashedView) {
            view.backgroundColor = previewBackgroundColor
            view.dashColor = previewDashColor
            view.layer.masksToBounds = true
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
    
    func viewIsAppearing(documentIsLocked: Bool) {
        self.setConstraints(for: self.delegate.toolbarState.position, statusBarVisible: self.delegate.statusBarVisible)
        self.delegate.topDidChange(forToolbarState: self.delegate.toolbarState)
        self.setAnnotationToolbarHandleMinimumLongPressDuration(forPosition: self.delegate.toolbarState.position)
        if self.delegate.toolbarState.visible && !documentIsLocked {
            self.showAnnotationToolbar(state: self.delegate.toolbarState, statusBarVisible: self.delegate.statusBarVisible, animated: false)
        } else {
            self.hideAnnotationToolbar(newState: self.delegate.toolbarState, statusBarVisible: self.delegate.statusBarVisible, animated: false)
        }
    }

    func viewWillTransitionToNewSize() {
        self.controller.prepareForSizeChange()
        self.controller.updateAdditionalButtons()
        self.setConstraints(for: self.delegate.toolbarState.position, statusBarVisible: self.delegate.statusBarVisible)
        self.delegate.topDidChange(forToolbarState: self.delegate.toolbarState)
        self.delegate.layoutIfNeeded()
        self.controller.sizeDidChange()
    }

    func interfaceVisibilityDidChange() {
        self.delegate.topDidChange(forToolbarState: self.delegate.toolbarState)
        self.setConstraints(for: self.delegate.toolbarState.position, statusBarVisible: self.delegate.statusBarVisible)
    }

    private func isCompactSize(for rotation: AnnotationToolbarViewController.Rotation) -> Bool {
        switch rotation {
        case .horizontal:
            return self.delegate.isCompactWidth

        case .vertical:
            return self.delegate.containerView.frame.height <= 400
        }
    }

    func topOffsets(statusBarVisible: Bool) -> (statusBarHeight: CGFloat, navigationBarHeight: CGFloat, total: CGFloat) {
        let statusBarOffset = statusBarVisible || UIDevice.current.userInterfaceIdiom != .pad ? self.delegate.statusBarHeight : 0
        let navigationBarOffset = statusBarVisible ? self.delegate.navigationBarHeight : 0
        return (statusBarOffset, navigationBarOffset, statusBarOffset + navigationBarOffset)
    }

    // MARK: - Actions

    func enableLeadingSafeConstraint() {
        self.toolbarLeading.isActive = false
        self.toolbarLeadingSafeArea.isActive = true
    }

    func disableLeadingSafeConstraint() {
        self.toolbarLeadingSafeArea.isActive = false
        self.toolbarLeading.isActive = true
    }

    func set(hidden: Bool, animated: Bool) {
        self.delegate.toolbarState = State(position: self.delegate.toolbarState.position, visible: !hidden)

        if hidden {
            self.hideAnnotationToolbar(newState: self.delegate.toolbarState, statusBarVisible: self.delegate.statusBarVisible, animated: animated)
        } else {
            self.showAnnotationToolbar(state: self.delegate.toolbarState, statusBarVisible: self.delegate.statusBarVisible, animated: animated)
        }
    }

    private func showAnnotationToolbar(state: State, statusBarVisible: Bool, animated: Bool) {
        self.controller.prepareForSizeChange()
        self.setConstraints(for: state.position, statusBarVisible: statusBarVisible)
        self.controller.view.isHidden = false
        self.delegate.layoutIfNeeded()
        self.controller.sizeDidChange()
        self.delegate.layoutIfNeeded()
        self.delegate.topDidChange(forToolbarState: state)

        self.delegate.hideSidebarIfNeeded(forPosition: state.position, isToolbarSmallerThanMinWidth: self.controller.view.frame.width < Self.minToolbarWidth, animated: animated)

        let navigationBarHidden = !statusBarVisible || state.position == .pinned

        if !animated {
            self.controller.view.alpha = 1
            self.delegate.setNavigationBar(hidden: navigationBarHidden, animated: false)
            self.delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
            self.delegate.layoutIfNeeded()
            return
        }

        if !navigationBarHidden && self.delegate.isNavigationBarHidden {
            self.delegate.setNavigationBar(hidden: false, animated: false)
            self.delegate.setNavigationBar(alpha: 0)
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.controller.view.alpha = 1
            self.delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
            self.delegate.layoutIfNeeded()
        }, completion: { finished in
            guard finished && navigationBarHidden else { return }
            self.delegate.setNavigationBar(hidden: true, animated: false)
        })
    }

    private func hideAnnotationToolbar(newState: State, statusBarVisible: Bool, animated: Bool) {
        self.delegate.topDidChange(forToolbarState: newState)

        if !animated {
            self.delegate.layoutIfNeeded()
            self.controller.view.alpha = 0
            self.controller.view.isHidden = true
            self.delegate.setNavigationBar(alpha: statusBarVisible ? 1 : 0)
            self.delegate.setNavigationBar(hidden: !statusBarVisible, animated: false)
            return
        }

        if statusBarVisible && self.delegate.isNavigationBarHidden {
            self.delegate.setNavigationBar(hidden: false, animated: false)
            self.delegate.setNavigationBar(alpha: 0)
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.delegate.layoutIfNeeded()
            self.controller.view.alpha = 0
            self.delegate.setNavigationBar(alpha: statusBarVisible ? 1 : 0)
        }, completion: { finished in
            guard finished else { return }
            self.controller.view.isHidden = true
            self.didHide?()
            if !statusBarVisible {
                self.delegate.setNavigationBar(hidden: true, animated: false)
            }
        })
    }

    private func setConstraints(for position: State.Position, statusBarVisible: Bool) {
        let rotation: AnnotationToolbarViewController.Rotation = (position == .top || position == .pinned) ? .horizontal : .vertical
        if self.isCompactSize(for: rotation) {
            self.setCompactConstraints(for: position, statusBarVisible: statusBarVisible)
        } else {
            self.setFullConstraints(for: position, statusBarVisible: statusBarVisible)
        }
    }

    private func setFullConstraints(for position: State.Position, statusBarVisible: Bool) {
        switch position {
        case .leading:
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = false
            if !self.delegate.isSidebarHidden {
                self.toolbarLeadingSafeArea.isActive = false
                self.toolbarLeading.isActive = true
                self.toolbarLeading.constant = Self.toolbarFullInsetInset
            } else {
                self.toolbarLeading.isActive = false
                self.toolbarLeadingSafeArea.isActive = true
                self.toolbarLeadingSafeArea.constant = Self.toolbarFullInsetInset
            }
            self.toolbarTop.constant = Self.toolbarFullInsetInset + self.topOffsets(statusBarVisible: statusBarVisible).total
            self.controller.set(rotation: .vertical, isCompactSize: false)

        case .trailing:
            self.toolbarLeading.isActive = false
            self.toolbarLeadingSafeArea.isActive = false
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = true
            self.toolbarTrailingSafeArea.constant = Self.toolbarFullInsetInset
            self.toolbarTop.constant = Self.toolbarFullInsetInset + self.topOffsets(statusBarVisible: statusBarVisible).total
            self.controller.set(rotation: .vertical, isCompactSize: false)

        case .top:
            self.setupTopConstraints(isCompact: false, isPinned: false, statusBarVisible: statusBarVisible)

        case .pinned:
            self.setupTopConstraints(isCompact: false, isPinned: true, statusBarVisible: statusBarVisible)
        }
    }

    private func setCompactConstraints(for position: State.Position, statusBarVisible: Bool) {
        switch position {
        case .leading:
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = false
            if !self.delegate.isSidebarHidden {
                self.toolbarLeadingSafeArea.isActive = false
                self.toolbarLeading.isActive = true
                self.toolbarLeading.constant = Self.toolbarCompactInset
            } else {
                self.toolbarLeading.isActive = false
                self.toolbarLeadingSafeArea.isActive = true
                self.toolbarLeadingSafeArea.constant = Self.toolbarCompactInset
            }
            self.toolbarTop.constant = Self.toolbarCompactInset + self.topOffsets(statusBarVisible: statusBarVisible).total
            self.controller.set(rotation: .vertical, isCompactSize: true)

        case .trailing:
            self.toolbarLeading.isActive = false
            self.toolbarLeadingSafeArea.isActive = false
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = true
            self.toolbarTrailingSafeArea.constant = Self.toolbarCompactInset
            self.toolbarTop.constant = Self.toolbarCompactInset + self.topOffsets(statusBarVisible: statusBarVisible).total
            self.controller.set(rotation: .vertical, isCompactSize: true)

        case .top:
            self.setupTopConstraints(isCompact: true, isPinned: false, statusBarVisible: statusBarVisible)

        case .pinned:
            self.setupTopConstraints(isCompact: true, isPinned: true, statusBarVisible: statusBarVisible)
        }
    }

    private func setupTopConstraints(isCompact: Bool, isPinned: Bool, statusBarVisible: Bool) {
        self.toolbarLeadingSafeArea.isActive = false
        self.toolbarTrailingSafeArea.isActive = false
        self.toolbarTrailing.isActive = true
        self.toolbarTrailing.constant = 0
        self.toolbarLeading.isActive = true
        self.toolbarLeading.constant = 0
        self.toolbarTop.constant = isPinned ? self.topOffsets(statusBarVisible: statusBarVisible).statusBarHeight : self.topOffsets(statusBarVisible: statusBarVisible).total
        self.controller.set(rotation: .horizontal, isCompactSize: isCompact)
    }

    // MARK: - Gesture recognizers

    private func isSwipe(fromVelocity velocity: CGPoint) -> Bool {
        return velocity.y <= -1500 || abs(velocity.x) >= 1500
    }

    /// Return new position for given touch point and velocity of toolbar. The user can pan up/left/right to move the toolbar. If velocity > 1500, it's considered a swipe and the toolbar is moved
    /// in swipe direction. Otherwise the toolbar is pinned to closest point from touch.
    private func position(fromTouch point: CGPoint, frame: CGRect, containerFrame: CGRect, velocity: CGPoint, statusBarVisible: Bool) -> State.Position {
        if self.isSwipe(fromVelocity: velocity) {
            // Move in direction of swipe
            if abs(velocity.y) > abs(velocity.x) && containerFrame.size.width >= Self.minToolbarWidth {
                return .top
            }
            return velocity.x < 0 ? .leading : .trailing
        }

        let topViewBottomRightPoint = self.toolbarTopPreview.convert(CGPoint(x: self.toolbarTopPreview.bounds.maxX, y: self.toolbarTopPreview.bounds.maxY), to: self.delegate.containerView)

        if point.y < topViewBottomRightPoint.y {
            let pinnedViewBottomRightPoint = self.toolbarPinnedPreview.convert(CGPoint(x: self.toolbarPinnedPreview.frame.maxX, y: self.toolbarPinnedPreview.frame.maxY), to: self.delegate.containerView)
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

    private func velocity(from panVelocity: CGPoint, newPosition: State.Position) -> CGFloat {
        let currentPosition: CGFloat
        let endPosition: CGFloat
        let velocity: CGFloat

        switch newPosition {
        case .top:
            velocity = panVelocity.y
            currentPosition = self.controller.view.frame.minY
            endPosition = self.delegate.containerView.safeAreaInsets.top

        case .leading:
            velocity = panVelocity.x
            currentPosition = self.controller.view.frame.minX
            endPosition = 0

        case .trailing:
            velocity = panVelocity.x
            currentPosition = self.controller.view.frame.maxX
            endPosition = self.delegate.containerView.frame.width

        case .pinned:
            velocity = panVelocity.y
            currentPosition = self.controller.view.frame.minY
            endPosition = self.delegate.containerView.safeAreaInsets.top
        }

        return abs(velocity / (endPosition - currentPosition))
    }

    func didTapToolbar(recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.setHighlightSelected(at: self.delegate.toolbarState.position)
            self.showPreviews()

        case .ended, .failed:
            self.hidePreviewsIfNeeded()

        default: break
        }
    }

    func toolbarDidPan(recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.toolbarInitialFrame = self.controller.view.frame

        case .changed:
            guard let originalFrame = self.toolbarInitialFrame else { return }
            let translation = recognizer.translation(in: self.controller.view)
            let location = recognizer.location(in: self.delegate.containerView)
            let position = self.position(
                fromTouch: location,
                frame: self.controller.view.frame,
                containerFrame: self.delegate.documentView.frame,
                velocity: CGPoint(),
                statusBarVisible: self.delegate.statusBarVisible
            )

            self.controller.view.frame = originalFrame.offsetBy(dx: translation.x, dy: translation.y)

            self.showPreviewsOnDragIfNeeded(translation: translation, velocity: recognizer.velocity(in: self.delegate.containerView), currentPosition: self.delegate.toolbarState.position)

            if !self.toolbarPreviewsOverlay.isHidden {
                self.setHighlightSelected(at: position)
            }

        case .ended, .failed:
            let velocity = recognizer.velocity(in: self.delegate.containerView)
            let location = recognizer.location(in: self.delegate.containerView)
            let position = self.position(
                fromTouch: location,
                frame: self.controller.view.frame,
                containerFrame: self.delegate.documentView.frame,
                velocity: velocity,
                statusBarVisible: self.delegate.statusBarVisible
            )
            let newState = State(position: position, visible: true)

            if position == .top && self.delegate.toolbarState.position == .pinned {
                self.delegate.statusBarVisible = true
            }
            self.set(toolbarPosition: position, oldPosition: self.delegate.toolbarState.position, velocity: velocity, statusBarVisible: self.delegate.statusBarVisible)
            self.setAnnotationToolbarHandleMinimumLongPressDuration(forPosition: position)
            self.delegate.toolbarState = newState
            self.toolbarInitialFrame = nil

        default: break
        }
    }

    private func setAnnotationToolbarHandleMinimumLongPressDuration(forPosition position: State.Position) {
        switch position {
        case .leading, .trailing:
            self.dragHandleLongPressRecognizer.minimumPressDuration = 0.3

        case .top, .pinned:
            self.dragHandleLongPressRecognizer.minimumPressDuration = 0
        }
    }

    // MARK: - Previews

    private func showPreviewsOnDragIfNeeded(translation: CGPoint, velocity: CGPoint, currentPosition: State.Position) {
        guard self.toolbarPreviewsOverlay.isHidden else { return }

        let distance = sqrt((translation.x * translation.x) + (translation.y * translation.y))
        let distanceThreshold: CGFloat = (currentPosition == .pinned || currentPosition == .top) ? 0 : 70

        guard distance > distanceThreshold && !self.isSwipe(fromVelocity: velocity) else { return }

        self.showPreviews()
    }

    private func showPreviews() {
        self.updatePositionOverlayViews(
            currentHeight: self.controller.view.frame.height,
            containerSize: self.delegate.documentView.frame.size,
            position: self.delegate.toolbarState.position,
            statusBarVisible: self.delegate.statusBarVisible
        )
        self.toolbarPreviewsOverlay.alpha = 0
        self.toolbarPreviewsOverlay.isHidden = false

        UIView.animate(withDuration: 0.2, animations: {
            self.toolbarPreviewsOverlay.alpha = 1
            self.delegate.setNavigationBar(alpha: 0)
        })
    }

    private func hidePreviewsIfNeeded() {
        guard self.toolbarPreviewsOverlay.alpha == 1 else { return }

        UIView.animate(withDuration: 0.2, animations: {
            self.delegate.setNavigationBar(alpha: 1)
            self.toolbarPreviewsOverlay.alpha = 0
        }, completion: { finished in
            guard finished else { return }
            self.toolbarPreviewsOverlay.isHidden = true
        })
    }

    private func updatePositionOverlayViews(currentHeight: CGFloat, containerSize: CGSize, position: State.Position, statusBarVisible: Bool) {
        let topToolbarsAvailable = containerSize.width >= Self.minToolbarWidth
        let verticalHeight: CGFloat
        switch position {
        case .leading, .trailing:
            // Position the preview so that the bottom of preview matches actual bottom of toolbar, add offset for dashed border
            let offset = self.controller.size + (statusBarVisible ? 0 : self.controller.size)
            verticalHeight = currentHeight - offset + (DashedView.dashWidth * 2) + 1

        case .top, .pinned:
            verticalHeight = min(containerSize.height - currentHeight - (position == .pinned ? self.delegate.navigationBarHeight : 0), AnnotationToolbarViewController.estimatedVerticalHeight)
        }

        self.toolbarPinnedPreview.isHidden = !topToolbarsAvailable || (position == .top && !statusBarVisible)
        self.inbetweenTopDashedView.isHidden = self.toolbarPinnedPreview.isHidden
        if !self.toolbarPinnedPreview.isHidden {
            // Change height based on current position so that preview is shown around currently visible toolbar
            let baseHeight = position == .pinned ? self.controller.size : self.delegate.navigationBarHeight
            self.toolbarPinnedPreviewHeight.constant = baseHeight + self.topOffsets(statusBarVisible: statusBarVisible).statusBarHeight - (position == .top ? 1 : 0)
        }
        self.toolbarTopPreview.isHidden = !topToolbarsAvailable
        self.toolbarLeadingPreviewHeight.constant = verticalHeight
        self.toolbarTrailingPreviewHeight.constant = verticalHeight
        self.toolbarPreviewsOverlay.layoutIfNeeded()
    }

    private func set(toolbarPosition newPosition: State.Position, oldPosition: State.Position, velocity velocityPoint: CGPoint, statusBarVisible: Bool) {
        let navigationBarHidden = newPosition == .pinned || !statusBarVisible

        switch (newPosition, oldPosition) {
        case (.leading, .leading), (.trailing, .trailing), (.top, .top), (.pinned, .pinned):
            // Position didn't change, move to initial frame
            let frame = self.toolbarInitialFrame ?? CGRect()
            let velocity = self.velocity(from: velocityPoint, newPosition: newPosition)

            if !navigationBarHidden && self.delegate.isNavigationBarHidden {
                self.delegate.setNavigationBar(hidden: false, animated: false)
                self.delegate.setNavigationBar(alpha: 0)
            }

            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [.curveEaseOut], animations: {
                self.toolbarPreviewsOverlay.alpha = 0
                self.controller.view.frame = frame
                self.delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
                self.delegate.setDocumentInterface(hidden: !statusBarVisible)
            }, completion: { finished in
                guard finished else { return }

                self.toolbarPreviewsOverlay.isHidden = true

                if navigationBarHidden {
                    self.delegate.setNavigationBar(hidden: true, animated: false)
                }
            })

        case (.leading, .trailing), (.trailing, .leading), (.top, .pinned), (.pinned, .top):
            // Move from side to side or vertically
            let velocity = self.velocity(from: velocityPoint, newPosition: newPosition)
            self.setConstraints(for: newPosition, statusBarVisible: statusBarVisible)
            self.delegate.topDidChange(forToolbarState: State(position: newPosition, visible: true))
            self.delegate.setNeedsLayout()

            self.delegate.hideSidebarIfNeeded(forPosition: newPosition, isToolbarSmallerThanMinWidth: self.controller.view.frame.width < Self.minToolbarWidth, animated: true)

            if !navigationBarHidden && self.delegate.isNavigationBarHidden {
                self.delegate.setNavigationBar(hidden: false, animated: false)
                self.delegate.setNavigationBar(alpha: 0)
            }

            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: {
                self.delegate.layoutIfNeeded()
                self.toolbarPreviewsOverlay.alpha = 0
                self.delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
                self.delegate.setDocumentInterface(hidden: !statusBarVisible)
                self.delegate.updateStatusBar()
            }, completion: { finished in
                guard finished else { return }

                self.toolbarPreviewsOverlay.isHidden = true

                if navigationBarHidden {
                    self.delegate.setNavigationBar(hidden: true, animated: false)
                }
            })

        case (.top, .leading), (.top, .trailing), (.leading, .top), (.leading, .pinned), (.trailing, .top), (.trailing, .pinned), (.pinned, .leading), (.pinned, .trailing):
            let velocity = self.velocity(from: velocityPoint, newPosition: newPosition)
            UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: {
                let newFrame = self.controller.view.frame.offsetBy(dx: velocityPoint.x / 10, dy: velocityPoint.y / 10)
                self.controller.view.frame = newFrame
                self.controller.view.alpha = 0
            }, completion: { finished in
                guard finished else { return }

                if !navigationBarHidden && self.delegate.isNavigationBarHidden {
                    self.delegate.setNavigationBar(hidden: false, animated: false)
                    self.delegate.setNavigationBar(alpha: 0)
                }

                self.controller.prepareForSizeChange()
                self.setConstraints(for: newPosition, statusBarVisible: statusBarVisible)
                self.delegate.layoutIfNeeded()
                self.controller.sizeDidChange()
                self.delegate.layoutIfNeeded()
                self.delegate.topDidChange(forToolbarState: State(position: newPosition, visible: true))

                self.delegate.hideSidebarIfNeeded(forPosition: newPosition, isToolbarSmallerThanMinWidth: self.controller.view.frame.width < Self.minToolbarWidth, animated: true)

                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: {
                    self.controller.view.alpha = 1
                    self.delegate.layoutIfNeeded()
                    self.toolbarPreviewsOverlay.alpha = 0
                    self.delegate.setNavigationBar(alpha: navigationBarHidden ? 0 : 1)
                    self.delegate.setDocumentInterface(hidden: !statusBarVisible)
                    self.delegate.updateStatusBar()
                }, completion: { finished in
                    guard finished else { return }

                    self.toolbarPreviewsOverlay.isHidden = true

                    if navigationBarHidden {
                        self.delegate.setNavigationBar(hidden: true, animated: false)
                    }
                })
            })
        }
    }

    private func setHighlightSelected(at position: State.Position) {
        switch position {
        case .top:
            self.toolbarLeadingPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarLeadingPreview.dashColor = self.previewDashColor
            self.toolbarTrailingPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarTrailingPreview.dashColor = self.previewDashColor
            self.toolbarTopPreview.backgroundColor = self.previewSelectedBackgroundColor
            self.toolbarTopPreview.dashColor = self.previewSelectedDashColor
            self.toolbarPinnedPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarPinnedPreview.dashColor = self.previewDashColor

        case .leading:
            self.toolbarLeadingPreview.backgroundColor = self.previewSelectedBackgroundColor
            self.toolbarLeadingPreview.dashColor = self.previewSelectedDashColor
            self.toolbarTrailingPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarTrailingPreview.dashColor = self.previewDashColor
            self.toolbarTopPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarTopPreview.dashColor = self.previewDashColor
            self.toolbarPinnedPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarPinnedPreview.dashColor = self.previewDashColor

        case .trailing:
            self.toolbarLeadingPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarLeadingPreview.dashColor = self.previewDashColor
            self.toolbarTrailingPreview.backgroundColor = self.previewSelectedBackgroundColor
            self.toolbarTrailingPreview.dashColor = self.previewSelectedDashColor
            self.toolbarTopPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarTopPreview.dashColor = self.previewDashColor
            self.toolbarPinnedPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarPinnedPreview.dashColor = self.previewDashColor

        case .pinned:
            self.toolbarLeadingPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarLeadingPreview.dashColor = self.previewDashColor
            self.toolbarTrailingPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarTrailingPreview.dashColor = self.previewDashColor
            self.toolbarTopPreview.backgroundColor = self.previewBackgroundColor
            self.toolbarTopPreview.dashColor = self.previewDashColor
            self.toolbarPinnedPreview.backgroundColor = self.previewSelectedBackgroundColor
            self.toolbarPinnedPreview.dashColor = self.previewSelectedDashColor
        }
    }
}

extension AnnotationToolbarHandler: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let longPressRecognizer = gestureRecognizer as? UILongPressGestureRecognizer else { return true }

        let location = longPressRecognizer.location(in: self.controller.view)
        let currentLocation: CGFloat
        let border: CGFloat

        switch self.delegate.toolbarState.position {
        case .pinned, .top:
            currentLocation = location.x
            border = self.controller.view.frame.width - Self.annotationToolbarDragHandleHeight

        case .leading, .trailing:
            currentLocation = location.y
            border = self.controller.view.frame.height - Self.annotationToolbarDragHandleHeight
        }
        return currentLocation >= border
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
