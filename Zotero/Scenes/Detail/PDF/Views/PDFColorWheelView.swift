//
//  PDFColorWheelView.swift
//  Zotero
//
//  Created by Ivy Pierlot on 14.08.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

/// Radial color picker shown around the Apple Pencil location when a pencil button action requests a color palette.
/// The view acts as its own backdrop - it's added over the whole document view, swallows touches so that no ink lands on the page while it's visible,
/// and dismisses when a touch lands outside of a color swatch.
final class PDFColorWheelView: UIView {
    /// Tappable size of a single swatch.
    private static let swatchDiameter: CGFloat = 44
    /// Size of the drawn circle inside of a swatch, matching `AnnotationToolOptionsViewController`.
    private static let circleDiameter: CGFloat = 32
    /// Minimum gap between hit areas of neighboring swatches.
    private static let swatchSpacing: CGFloat = 10
    private static let minimumRadius: CGFloat = 78
    /// Padding between swatches and the edge of the platter.
    private static let platterPadding: CGFloat = 14
    /// Padding between the platter and the edge of the container.
    private static let edgePadding: CGFloat = 12
    private static let hubDiameter: CGFloat = 14
    private static let showDuration: TimeInterval = 0.3
    private static let fadeDuration: TimeInterval = 0.15
    /// Fraction of the wheel radius around the center in which the pencil doesn't select anything yet, so that a hold without any movement picks nothing.
    private static let deadZoneFraction: CGFloat = 0.4
    private static let highlightScale: CGFloat = 1.28
    private static let highlightDuration: TimeInterval = 0.12
    private static let followDuration: TimeInterval = 0.18
    /// How much of a full circle the swatches are spread over. Deliberately not a full circle, so that the hand holding the pencil never covers a swatch.
    private static let arcSweep: CGFloat = (200 * .pi) / 180
    /// Bearing used when the pencil isn't hovering and its direction is unknown. Points straight up, away from where a hand usually is.
    private static let defaultArcBearing: CGFloat = -.pi / 2
    /// The arc is only re-aimed once the pencil turns by more than this, otherwise it would swim around while the pencil is just resting.
    private static let arcReorientationThreshold: CGFloat = (25 * .pi) / 180
    private static let arcReorientationDuration: TimeInterval = 0.2
    /// Bearings tried, in order and in both directions, when the arc doesn't fit on screen at its natural bearing.
    private static let arcFitRotations: [CGFloat] = [0, .pi / 6, .pi / 3, .pi / 2, (2 * .pi) / 3, (5 * .pi) / 6, .pi]

    private let hexColors: [String]
    private let selectedHexColor: String?
    /// Pencil location in container coordinates. The wheel is centered here unless it needs to be moved to stay on screen.
    private var anchor: CGPoint
    private let colorPicked: (String) -> Void
    private let dismissRequested: () -> Void
    private let disposeBag: DisposeBag

    private let platterLayer: CAShapeLayer
    private let hubView: UIView
    private let connectorLayer: CAShapeLayer
    private var swatchViews: [ColorPickerCircleView]
    /// Center of the arc the swatches sit on, which is clamped to stay inside the container and so may differ from `anchor`.
    private var wheelCenter: CGPoint
    /// Direction the arc would face given where the pencil points, which is opposite of the hand holding it.
    private var preferredArcBearing: CGFloat
    /// Direction the arc actually ended up facing, which differs from the preferred one when it had to be turned to fit on screen.
    private var arcBearing: CGFloat
    /// Laid out positions of swatches. Kept separately, because they're animated and so must not be overwritten by a layout pass mid-animation.
    private var swatchCenters: [CGPoint]
    private var isAnimatingIn: Bool
    /// Set while the arc is turning to a new bearing, which is the only time the platter's path is allowed to animate rather than snap.
    private var isReorienting: Bool
    /// Set while the pencil button is held down, during which the wheel tracks the pencil and the pencil picks a color by pointing at it.
    private var isFollowingPen: Bool
    private var highlightedIndex: Int?
    private let selectionFeedback: UISelectionFeedbackGenerator

    // MARK: - Lifecycle

    init(
        hexColors: [String],
        selectedHexColor: String?,
        anchor: CGPoint,
        handBearing: CGFloat?,
        colorPicked: @escaping (String) -> Void,
        dismissRequested: @escaping () -> Void
    ) {
        self.hexColors = hexColors
        self.selectedHexColor = selectedHexColor
        self.anchor = anchor
        self.colorPicked = colorPicked
        self.dismissRequested = dismissRequested
        disposeBag = DisposeBag()
        platterLayer = CAShapeLayer()
        hubView = UIView()
        connectorLayer = CAShapeLayer()
        swatchViews = []
        wheelCenter = anchor
        preferredArcBearing = handBearing.map(Self.bearing(awayFrom:)) ?? Self.defaultArcBearing
        arcBearing = preferredArcBearing
        swatchCenters = []
        isAnimatingIn = false
        isReorienting = false
        isFollowingPen = false
        selectionFeedback = UISelectionFeedbackGenerator()

        super.init(frame: CGRect())

        setupViews()

        func setupViews() {
            backgroundColor = .clear

            connectorLayer.lineWidth = 1.5
            connectorLayer.lineCap = .round
            connectorLayer.fillColor = UIColor.clear.cgColor
            connectorLayer.isHidden = true
            layer.addSublayer(connectorLayer)

            let platterColor = Asset.Colors.annotationPopoverBackground.color
            platterLayer.fillColor = platterColor.cgColor
            platterLayer.shadowColor = UIColor.black.cgColor
            platterLayer.shadowOpacity = 0.18
            platterLayer.shadowRadius = 12
            platterLayer.shadowOffset = CGSize(width: 0, height: 4)
            layer.addSublayer(platterLayer)

            for hexColor in hexColors {
                let isSelected = hexColor == selectedHexColor
                let circleView = ColorPickerCircleView(hexColor: hexColor)
                circleView.backgroundColor = platterColor
                circleView.circleSize = CGSize(width: Self.circleDiameter, height: Self.circleDiameter)
                circleView.contentInsets = UIEdgeInsets(
                    top: (Self.swatchDiameter - Self.circleDiameter) / 2,
                    left: (Self.swatchDiameter - Self.circleDiameter) / 2,
                    bottom: (Self.swatchDiameter - Self.circleDiameter) / 2,
                    right: (Self.swatchDiameter - Self.circleDiameter) / 2
                )
                circleView.selectionLineWidth = 2.5
                circleView.selectionInset = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
                circleView.isSelected = isSelected
                circleView.isAccessibilityElement = true
                circleView.accessibilityTraits = .button
                circleView.accessibilityLabel = accessibilityName(for: hexColor, isSelected: isSelected)
                circleView.tap
                    .observe(on: MainScheduler.instance)
                    .subscribe(onNext: { [weak self] hexColor in
                        self?.colorPicked(hexColor)
                    })
                    .disposed(by: disposeBag)
                addSubview(circleView)
                swatchViews.append(circleView)
            }

            hubView.isUserInteractionEnabled = false
            hubView.backgroundColor = selectedHexColor.map({ UIColor(hex: $0) }) ?? platterColor
            hubView.layer.borderWidth = 2
            hubView.layer.cornerRadius = Self.hubDiameter / 2
            hubView.layer.shadowColor = UIColor.black.cgColor
            hubView.layer.shadowOpacity = 0.2
            hubView.layer.shadowRadius = 2
            hubView.layer.shadowOffset = CGSize(width: 0, height: 1)
            addSubview(hubView)

            isAccessibilityElement = false
            accessibilityViewIsModal = true
            accessibilityLabel = L10n.Accessibility.Pdf.colorWheel
            accessibilityElements = swatchViews
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    /// Adds the wheel over given container view and animates it in.
    func show(in containerView: UIView) {
        frame = containerView.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(self)
        setNeedsLayout()
        layoutIfNeeded()
        animateIn()
    }

    func hide(animated: Bool, completion: (() -> Void)?) {
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        // Nothing may be picked from here on, whether or not the animation below ever runs its course.
        isUserInteractionEnabled = false

        guard animated else {
            removeFromSuperview()
            completion?()
            return
        }

        // The animation's completion is what normally takes the wheel out of the hierarchy, but a wheel which stays there keeps suppressing everything it suppresses
        // while it's up, so it comes out on a timer as well rather than relying on the animation being seen through.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration + 0.1) { [weak self] in
            self?.removeFromSuperview()
        }

        UIView.animate(
            withDuration: Self.fadeDuration,
            animations: { [weak self] in
                guard let self else { return }
                backgroundColor = .clear
                let transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
                platterLayer.opacity = 0
                hubView.alpha = 0
                connectorLayer.opacity = 0
                for swatchView in swatchViews {
                    swatchView.transform = transform
                    swatchView.alpha = 0
                }
            },
            completion: { [weak self] _ in
                self?.removeFromSuperview()
                completion?()
            }
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // Touches which land on a swatch are delivered to the swatch itself, so anything received here is a tap outside of the wheel.
        dismissRequested()
    }

    // MARK: - Pencil hold

    /// Starts tracking the pencil, which happens while its button is held down. The wheel follows the pencil around and the swatch the pencil points at is highlighted,
    /// so that releasing the button picks it.
    func beginFollowingPen() {
        isFollowingPen = true
        selectionFeedback.prepare()
    }

    /// Stops tracking the pencil and leaves the wheel where it is, so that a color can still be picked by tapping it.
    func endFollowingPen() {
        isFollowingPen = false
        setHighlightedIndex(nil)
    }

    /// Color the pencil is currently pointing at, if any.
    var highlightedHexColor: String? {
        return highlightedIndex.map({ hexColors[$0] })
    }

    /// Pencil location and hand direction in container coordinates, updated while its button is held down.
    func setPenLocation(_ point: CGPoint, handBearing: CGFloat?) {
        guard isFollowingPen else { return }

        if let handBearing {
            reorient(to: Self.bearing(awayFrom: handBearing))
        }

        let offset = CGPoint(x: point.x - wheelCenter.x, y: point.y - wheelCenter.y)
        let distance = hypot(offset.x, offset.y)
        let radius = wheelRadius()

        guard distance <= radius + (Self.swatchDiameter / 2) + Self.platterPadding else {
            // The pencil left the arc entirely, so bring it along instead of leaving it behind.
            move(to: point)
            return
        }

        guard distance > radius * Self.deadZoneFraction else {
            // Right around the center nothing is picked yet, so that holding the button without moving doesn't change the color.
            setHighlightedIndex(nil)
            return
        }

        setHighlightedIndex(indexOfSwatch(inDirectionOf: offset))
    }

    /// Shortest turn from one bearing to another, in `(-pi, pi]`. Bearings accumulate as the pencil turns, so every comparison between them has to go through this.
    private static func signedDelta(from bearing: CGFloat, to other: CGFloat) -> CGFloat {
        let difference = other - bearing
        return atan2(sin(difference), cos(difference))
    }

    /// Index of the swatch the pencil points at, or `nil` when it points outside of the arc - back toward the hand, where releasing shouldn't pick anything.
    private func indexOfSwatch(inDirectionOf offset: CGPoint) -> Int? {
        let delta = Self.signedDelta(from: arcBearing, to: atan2(offset.y, offset.x))
        let half = Self.arcSweep / 2

        guard hexColors.count > 1 else { return abs(delta) <= half ? 0 : nil }
        // Each end swatch also captures half a step past the end of the arc, so overshooting it doesn't drop the selection.
        guard abs(delta) <= half + (arcStep / 2) else { return nil }

        let steps = ((delta + half) / arcStep).rounded()
        return Int(min(max(steps, 0), CGFloat(hexColors.count - 1)))
    }

    /// Turns the arc to face away from the hand. Only acts on real turns of the pencil, otherwise the arc would swim around while the pencil merely rests.
    private func reorient(to bearing: CGFloat) {
        let difference = Self.signedDelta(from: preferredArcBearing, to: bearing)

        // Turning the arc while the pencil is already aiming at a swatch would pull that swatch out from under it, so it only settles while nothing is picked.
        guard abs(difference) > Self.arcReorientationThreshold, !isAnimatingIn, highlightedIndex == nil else { return }

        preferredArcBearing += difference
        isReorienting = true
        setNeedsLayout()
        UIView.animate(
            withDuration: Self.arcReorientationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut],
            animations: { [weak self] in
                self?.layoutIfNeeded()
            },
            completion: { [weak self] _ in
                self?.isReorienting = false
            }
        )
    }

    private func move(to point: CGPoint) {
        // Swatches are on their way out from the center while animating in, so moving the wheel now would strand them at their old positions.
        guard !isAnimatingIn else { return }
        anchor = point
        setHighlightedIndex(nil)
        setNeedsLayout()
        UIView.animate(withDuration: Self.followDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) { [weak self] in
            self?.layoutIfNeeded()
        }
    }

    private func setHighlightedIndex(_ index: Int?) {
        guard highlightedIndex != index else { return }
        highlightedIndex = index

        if index != nil {
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()
        }

        UIView.animate(withDuration: Self.highlightDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) { [weak self] in
            self?.applyHighlight()
        }
    }

    private func applyHighlight() {
        for (index, swatchView) in swatchViews.enumerated() {
            let isHighlighted = index == highlightedIndex
            swatchView.transform = isHighlighted ? CGAffineTransform(scaleX: Self.highlightScale, y: Self.highlightScale) : .identity
            swatchView.isSelected = isHighlighted || swatchView.hexColor == selectedHexColor
        }
        hubView.backgroundColor = (highlightedHexColor ?? selectedHexColor).map({ UIColor(hex: $0) }) ?? Asset.Colors.annotationPopoverBackground.color
    }

    override func accessibilityPerformEscape() -> Bool {
        dismissRequested()
        return true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateDynamicColors()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDynamicColors()

        let radius = wheelRadius()
        let outerRadius = radius + (Self.swatchDiameter / 2) + Self.platterPadding
        let placement = placement(radius: radius, outerRadius: outerRadius)
        wheelCenter = placement.center
        arcBearing = placement.bearing

        let swatchSize = CGSize(width: Self.swatchDiameter, height: Self.swatchDiameter)
        swatchCenters = swatchViews.indices.map({ swatchCenter(at: $0, radius: radius, bearing: arcBearing) })
        for (index, swatchView) in swatchViews.enumerated() {
            swatchView.bounds = CGRect(origin: CGPoint(), size: swatchSize)
            // While animating in, swatches travel from the center of the arc to their final positions, so their centers must not be overwritten here.
            if !isAnimatingIn {
                swatchView.center = swatchCenters[index]
            }
        }

        updatePlatter(radius: radius, outerRadius: outerRadius)

        hubView.bounds = CGRect(x: 0, y: 0, width: Self.hubDiameter, height: Self.hubDiameter)
        hubView.center = anchor

        updateConnector(outerRadius: outerRadius)
    }

    /// Builds the platter as a band which follows the arc, rather than the full disc a ring would need.
    private func updatePlatter(radius: CGFloat, outerRadius: CGFloat) {
        let innerRadius = max(0, radius - (Self.swatchDiameter / 2) - Self.platterPadding)
        let start = arcBearing - (Self.arcSweep / 2)
        let end = arcBearing + (Self.arcSweep / 2)

        let path = UIBezierPath()
        path.addArc(withCenter: wheelCenter, radius: outerRadius, startAngle: start, endAngle: end, clockwise: true)
        path.addArc(withCenter: wheelCenter, radius: innerRadius, startAngle: end, endAngle: start, clockwise: false)
        path.close()

        // Every layout pass would otherwise kick off an implicit quarter second animation of the path, so it's only animated when the arc is deliberately turning.
        CATransaction.begin()
        CATransaction.setDisableActions(!isReorienting)
        platterLayer.path = path.cgPath
        platterLayer.shadowPath = path.cgPath
        CATransaction.commit()
    }

    /// `CALayer` colors don't follow trait changes on their own, so they're resolved against the current traits whenever those may have changed.
    private func updateDynamicColors() {
        let platterColor = Asset.Colors.annotationPopoverBackground.color.resolvedColor(with: traitCollection)
        connectorLayer.strokeColor = UIColor.label.resolvedColor(with: traitCollection).withAlphaComponent(0.25).cgColor
        platterLayer.fillColor = platterColor.cgColor
        hubView.layer.borderColor = platterColor.cgColor
    }

    /// Angle between neighboring swatches along the arc.
    private var arcStep: CGFloat {
        guard hexColors.count > 1 else { return Self.arcSweep }
        return Self.arcSweep / CGFloat(hexColors.count - 1)
    }

    /// Radius the swatches sit at. Derived from the chord between neighbors, so that they can never overlap however tight the arc is.
    private func wheelRadius() -> CGFloat {
        guard hexColors.count > 1 else { return Self.minimumRadius }
        let minimumSpacedRadius = (Self.swatchDiameter + Self.swatchSpacing) / (2 * sin(arcStep / 2))
        return max(Self.minimumRadius, minimumSpacedRadius)
    }

    /// Position of a swatch along the arc, spread evenly from one end to the other. Kept identical in RTL, color order isn't a reading order.
    private func swatchCenter(at index: Int, radius: CGFloat, bearing: CGFloat) -> CGPoint {
        let angle = angleOfSwatch(at: index, bearing: bearing)
        return CGPoint(x: wheelCenter.x + (radius * cos(angle)), y: wheelCenter.y + (radius * sin(angle)))
    }

    private func angleOfSwatch(at index: Int, bearing: CGFloat) -> CGFloat {
        guard hexColors.count > 1 else { return bearing }
        return bearing - (Self.arcSweep / 2) + (arcStep * CGFloat(index))
    }

    /// Direction the arc should face given where the hand is, which is simply the opposite one.
    private static func bearing(awayFrom handBearing: CGFloat) -> CGFloat {
        return handBearing + .pi
    }

    /// Picks where the arc sits and which way it faces. The arc is anchored on the pencil, so when it doesn't fit on screen it's rotated around the pencil before
    /// resorting to moving it away, which keeps it attached to the pen for as long as possible.
    private func placement(radius: CGFloat, outerRadius: CGFloat) -> (center: CGPoint, bearing: CGFloat) {
        let limit = bounds.inset(by: safeAreaInsets).insetBy(dx: Self.edgePadding, dy: Self.edgePadding)

        guard limit.width > 0, limit.height > 0 else { return (CGPoint(x: bounds.midX, y: bounds.midY), preferredArcBearing) }

        for rotation in Self.arcFitRotations {
            for bearing in (rotation == 0 ? [preferredArcBearing] : [preferredArcBearing + rotation, preferredArcBearing - rotation]) {
                if limit.contains(arcBounds(center: anchor, radius: radius, bearing: bearing)) {
                    return (anchor, bearing)
                }
            }
        }

        // Nothing fits around the pencil, so fall back to keeping the arc on screen and drawing a connector back to the pencil.
        let translated = limit.insetBy(dx: outerRadius, dy: outerRadius)
        guard translated.width > 0, translated.height > 0 else { return (CGPoint(x: bounds.midX, y: bounds.midY), preferredArcBearing) }
        let x = min(max(anchor.x, translated.minX), translated.maxX)
        let y = min(max(anchor.y, translated.minY), translated.maxY)
        return (CGPoint(x: x, y: y), preferredArcBearing)
    }

    /// Bounding box of the platter at a given bearing, which is what has to fit on screen. Taken from the swatch positions grown by half the band's thickness - the arc
    /// bulges only a couple of points further than that between neighbors, so it doesn't need to be solved exactly.
    private func arcBounds(center: CGPoint, radius: CGFloat, bearing: CGFloat) -> CGRect {
        let reach = (Self.swatchDiameter / 2) + Self.platterPadding
        var rect: CGRect?
        for index in hexColors.indices {
            let angle = angleOfSwatch(at: index, bearing: bearing)
            let point = CGPoint(x: center.x + (radius * cos(angle)), y: center.y + (radius * sin(angle)))
            let swatchRect = CGRect(x: point.x, y: point.y, width: 0, height: 0).insetBy(dx: -reach, dy: -reach)
            rect = rect.map({ $0.union(swatchRect) }) ?? swatchRect
        }
        return rect ?? CGRect(origin: center, size: CGSize())
    }

    /// Draws a line between the pencil location and the arc when the arc had to be moved far enough that the connection isn't obvious.
    private func updateConnector(outerRadius: CGFloat) {
        let offset = CGPoint(x: wheelCenter.x - anchor.x, y: wheelCenter.y - anchor.y)
        let distance = hypot(offset.x, offset.y)

        guard distance > outerRadius else {
            connectorLayer.isHidden = true
            return
        }

        let edge = CGPoint(x: wheelCenter.x - ((offset.x / distance) * outerRadius), y: wheelCenter.y - ((offset.y / distance) * outerRadius))
        let path = UIBezierPath()
        path.move(to: anchor)
        path.addLine(to: edge)
        connectorLayer.path = path.cgPath
        connectorLayer.isHidden = false
    }

    // MARK: - Animations

    private func animateIn() {
        let dimmedBackground = UIColor.black.withAlphaComponent(0.12)

        isAnimatingIn = true
        // The platter is a path rather than a view, so it fades in while the swatches carry the motion.
        platterLayer.opacity = 0
        hubView.alpha = 0
        connectorLayer.opacity = 0
        for swatchView in swatchViews {
            // Hit testing uses model frames, so a very early tap would otherwise hit a swatch which is still visually in the center.
            swatchView.isUserInteractionEnabled = false
            // Fan out from the pencil itself rather than the center of the arc, which differ when the arc had to be moved to stay on screen.
            swatchView.center = anchor
            swatchView.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
            swatchView.alpha = 0
        }

        guard !UIAccessibility.isReduceMotionEnabled else {
            UIView.animate(
                withDuration: Self.fadeDuration,
                animations: { [weak self] in
                    guard let self else { return }
                    backgroundColor = dimmedBackground
                    resetToFinalState()
                },
                completion: { [weak self] _ in
                    self?.finishAnimatingIn()
                }
            )
            return
        }

        UIView.animate(withDuration: Self.fadeDuration) { [weak self] in
            self?.backgroundColor = dimmedBackground
        }

        UIView.animate(withDuration: Self.showDuration, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.5) { [weak self] in
            self?.hubView.alpha = 1
        }

        platterLayer.opacity = 1
        connectorLayer.opacity = 1

        for (index, swatchView) in swatchViews.enumerated() {
            let center = swatchCenters[index]
            let isLast = index == swatchViews.count - 1
            UIView.animate(
                withDuration: Self.showDuration,
                delay: 0.04 + (Double(index) * 0.018),
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0.5,
                animations: {
                    swatchView.center = center
                    swatchView.transform = .identity
                    swatchView.alpha = 1
                },
                completion: { [weak self] _ in
                    guard isLast else { return }
                    self?.finishAnimatingIn()
                }
            )
        }
    }

    private func resetToFinalState() {
        platterLayer.opacity = 1
        hubView.alpha = 1
        connectorLayer.opacity = 1
        for (index, swatchView) in swatchViews.enumerated() {
            swatchView.center = swatchCenters[index]
            swatchView.transform = .identity
            swatchView.alpha = 1
        }
    }

    private func finishAnimatingIn() {
        isAnimatingIn = false
        for swatchView in swatchViews {
            swatchView.isUserInteractionEnabled = true
        }
        // The entrance animation resets transforms, so a swatch highlighted by the pencil while it was still running has to be reapplied.
        applyHighlight()
        // The wheel may have already been dismissed while animating in, in which case focus shouldn't be moved to it.
        guard superview != nil else { return }
        UIAccessibility.post(notification: .screenChanged, argument: swatchViews.first)
    }

    private func accessibilityName(for hexColor: String, isSelected: Bool) -> String {
        let colorName = AnnotationsConfig.colorNames[hexColor] ?? L10n.unknown
        return !isSelected ? colorName : L10n.Accessibility.Pdf.selected + ": " + colorName
    }
}
