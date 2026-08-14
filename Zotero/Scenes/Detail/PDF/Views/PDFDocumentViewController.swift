//
//  PDFDocumentViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import Combine

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RealmSwift
import RxSwift

protocol PDFDocumentDelegate: AnyObject {
    func annotationTool(
        didChangeStateFrom oldState: PSPDFKit.Annotation.Tool?,
        to newState: PSPDFKit.Annotation.Tool?,
        variantFrom oldVariant: PSPDFKit.Annotation.Variant?,
        to newVariant: PSPDFKit.Annotation.Variant?
    )
    func didChange(undoState undoEnabled: Bool, redoState redoEnabled: Bool)
    func interfaceVisibilityDidChange(to isHidden: Bool)
    func toggleToolOptions()
    func pageIndexChanged(event: PDFViewController.PageIndexChangeEvent)
    func backActionExecuted()
    func forwardActionExecuted()
    func backForwardListDidUpdate(hasBackActions: Bool, hasForwardActions: Bool)
    func didSelectText(_ text: String)
}

final class PDFDocumentViewController: UIViewController {
    private(set) weak var pdfController: PDFViewController?
    private weak var unlockController: UnlockPDFViewController?

    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag
    private let initialUIHidden: Bool

    private static var toolHistory: [PSPDFKit.Annotation.Tool?] = []
    /// How long a pencil location is considered recent enough to place the color wheel at.
    private static let pencilLocationLifetime: CFTimeInterval = 5
    /// Above this altitude the pencil is held close to upright, where its azimuth is mostly noise and says nothing useful about where the hand is.
    private static let maximumUsableAzimuthAltitude: CGFloat = 1.3
    /// How long a pencil button may be held before the wheel gives up on hearing that it was released and closes itself.
    private static let colorWheelHoldTimeout: TimeInterval = 4
    /// Size of the markup tool previews at 100% zoom, roughly a line of text at a typical body size.
    private static let markupPreviewLength: CGFloat = 26
    private static let highlightPreviewThickness: CGFloat = 11
    private static let underlinePreviewThickness: CGFloat = 3

    private var selectionView: SelectionView?
    // Used to decide whether text annotation should start editing on tap
    private var selectedAnnotationWasSelectedBefore: Bool
    private var searchResults: [SearchResult] = []
    private var pageIndexCancellable: AnyCancellable?
    // Holds the zoom scale captured right before a corner-tap (fast scroll) page navigation, so it can be re-applied
    // to the page that becomes visible after the scroll. `nil` means there's no pending zoom to restore.
    private var pendingCornerTapZoomScale: CGFloat?
    private weak var colorWheelView: PDFColorWheelView?
    /// Gestures belonging to PSPDFKit which this controller has added itself to as a second target. Weak, since they belong to page views which come and go.
    private let observedPageGestures: NSHashTable<UIGestureRecognizer> = .weakObjects()
    private weak var toolPreviewView: PencilToolPreviewView?
    private var lastPencilHover: (point: CGPoint, handBearing: CGFloat?, timestamp: CFTimeInterval)?
    private var isPencilHovering: Bool
    private var colorWheelHoldTimeoutWorkItem: DispatchWorkItem?
    /// Text is being edited somewhere, which for this controller means a free text annotation or the search field. Tracked from the keyboard rather than looked up on
    /// every hover, which arrives far too often to go walking the view hierarchy for a first responder.
    private var isEditingText: Bool
    private var keyboardCancellables: [AnyCancellable] = []
    var currentPage: UInt {
        return pdfController?.pageIndex ?? 0
    }

    weak var parentDelegate: (PDFReaderContainerDelegate & PDFDocumentDelegate)?
    weak var coordinatorDelegate: PdfReaderCoordinatorDelegate?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>, compactSize: Bool, initialUIHidden: Bool) {
        self.viewModel = viewModel
        self.initialUIHidden = initialUIHidden
        selectedAnnotationWasSelectedBefore = false
        isPencilHovering = false
        isEditingText = false
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGray6
        if viewModel.state.document.isLocked {
            setupLockedView()
        } else {
            setupPdfController()
        }
        setupObserving()

        func setupLockedView() {
            let unlockController = UnlockPDFViewController(viewModel: viewModel)
            unlockController.view.translatesAutoresizingMaskIntoConstraints = false

            unlockController.willMove(toParent: self)
            addChild(unlockController)
            view.addSubview(unlockController.view)
            unlockController.didMove(toParent: self)

            NSLayoutConstraint.activate([
                unlockController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                unlockController.view.topAnchor.constraint(equalTo: view.topAnchor),
                unlockController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                unlockController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            ])

            self.unlockController = unlockController
        }

        func setupObserving() {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] state in
                    self?.update(state: state)
                })
                .disposed(by: disposeBag)
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        setupTextEditingObservingIfNeeded()
        setInterface(hidden: initialUIHidden)
        updateInterface(to: viewModel.state.settings.appearanceMode, userInterfaceStyle: traitCollection.userInterfaceStyle)
        if let (page, _) = viewModel.state.focusDocumentLocation, let annotation = viewModel.state.selectedAnnotation {
            select(annotation: annotation, pageIndex: PageIndex(page), document: viewModel.state.document)
        }
    }

    deinit {
        disableAnnotationTools()
        pdfController?.annotationStateManager.remove(self)
        DDLogInfo("PDFDocumentViewController deinitialized")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dismissColorWheel(animated: false)
        pencilDidStopHovering()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        dismissColorWheel(animated: false)

        guard viewIfLoaded != nil else { return }

        coordinator.animate { [weak self] _ in
            // Update highlight/underline selection if needed.
            guard let self, let annotation = viewModel.state.selectedAnnotation, let pdfController else { return }
            updateSelectionOnVisiblePages(of: pdfController, annotation: annotation)
        }
    }

    func didBecomeActive() {
        // Update pencil settings if neeeded.
        guard let pdfController, pdfController.annotationStateManager.state == .ink else { return }
        pdfController.annotationStateManager.stylusMode = UIPencilInteraction.prefersPencilOnlyDrawing ? .stylus : .fromStylusManager
    }

    // MARK: - Actions

    func performBackAction() {
        pdfController?.backForwardList.requestBack(animated: false)
    }

    func performForwardAction() {
        pdfController?.backForwardList.requestForward(animated: false)
    }

    func focus(page: UInt) {
        scrollIfNeeded(to: page, animated: true)
    }

    func highlightSearchResults(_ results: [SearchResult]) {
        searchResults = results
        guard let searchHighlightViewManager = pdfController?.searchHighlightViewManager else { return }
        searchHighlightViewManager.clearHighlightedSearchResults(animated: true)
        searchHighlightViewManager.addHighlight(results, animated: true)
    }

    func highlightSelectedSearchResult(_ result: SearchResult) {
        let searchHighlightViewManager = pdfController?.searchHighlightViewManager
        scrollIfNeeded(to: result.pageIndex, animated: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                searchHighlightViewManager?.animateSearchHighlight(result)
            }
        }
    }

    func disableAnnotationTools() {
        guard let tool = pdfController?.annotationStateManager.state else { return }
        toggle(annotationTool: tool, color: nil, tappedWithStylus: false)
    }

    func toggle(annotationTool: PSPDFKit.Annotation.Tool, color: UIColor?, tappedWithStylus: Bool, resetPencilManager: Bool = true) {
        guard let stateManager = pdfController?.annotationStateManager else { return }

        stateManager.stylusMode = .fromStylusManager

        let toolToAdd = stateManager.state == annotationTool ? nil : annotationTool
        if Self.toolHistory.last != toolToAdd {
            Self.toolHistory.append(toolToAdd)
            if Self.toolHistory.count > 2 {
                Self.toolHistory.remove(at: 0)
            }
        }
        if stateManager.state == annotationTool {
            stateManager.setState(nil, variant: nil)
            if resetPencilManager {
                PSPDFKit.SDK.shared.applePencilManager.detected = false
                PSPDFKit.SDK.shared.applePencilManager.enabled = false
            }
            return
        } else if tappedWithStylus {
            PSPDFKit.SDK.shared.applePencilManager.detected = true
            PSPDFKit.SDK.shared.applePencilManager.enabled = true
        }

        stateManager.setState(annotationTool, variant: nil)

        if let color {
            let type: AnnotationType?
            switch annotationTool {
            case .highlight:
                type = .highlight

            case .underline:
                type = .underline

            default:
                type = nil
            }
            let appearance = viewModel.handler.appearance
            let (_color, _, blendMode) = AnnotationColorGenerator.color(from: color, type: type, appearance: appearance)
            stateManager.drawColor = _color
            stateManager.blendMode = blendMode ?? .normal
        }

        switch annotationTool {
        case .ink:
            stateManager.lineWidth = viewModel.state.activeLineWidth
            if UIPencilInteraction.prefersPencilOnlyDrawing {
                stateManager.stylusMode = .stylus
            }

        case .eraser:
            stateManager.lineWidth = viewModel.state.activeEraserSize

        case .freeText:
            stateManager.fontSize = viewModel.state.activeFontSize

        default:
            break
        }
    }

    // MARK: - Color wheel

    /// Whether the wheel is actually on screen, rather than merely still referenced. A wheel which has been taken out of the view hierarchy shouldn't go on suppressing
    /// the tool preview just because it hasn't been released yet.
    private var isColorWheelVisible: Bool {
        return view.subviews.contains(where: { $0 is PDFColorWheelView })
    }

    /// Takes any wheel out of the view hierarchy, including one which outlived the reference to it. Nothing else can tell that a wheel is up, so one left behind here
    /// goes on covering the document and suppressing the tool preview with no way to reach it.
    private func removeColorWheelsFromViewHierarchy() {
        for subview in view.subviews where subview is PDFColorWheelView {
            subview.removeFromSuperview()
        }
    }

    /// Shows a radial color picker around the pencil, or dismisses one which is already visible.
    private func toggleColorWheel() {
        guard colorWheelView == nil else {
            dismissColorWheel(animated: true)
            return
        }
        showColorWheel()
    }

    /// Called when the pencil button starts being held down. Shows the wheel if needed and starts tracking the pencil, or closes a wheel which is already up, so that
    /// a second press still dismisses it.
    private func beginColorWheelHold(at location: CGPoint) {
        guard colorWheelView == nil else {
            dismissColorWheel(animated: true)
            return
        }
        showColorWheel(at: location)
        colorWheelView?.beginFollowingPen()

        // The squeeze doesn't always report that it ended, and a wheel left over from a hold nobody saw the end of sits there suppressing the tool preview until
        // something is tapped. So the hold ends by itself if the release is never heard.
        colorWheelHoldTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.endColorWheelHold()
        }
        colorWheelHoldTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.colorWheelHoldTimeout, execute: workItem)
    }

    /// Called when the pencil button is released. Picks the color the pencil points at, and closes the wheel either way. Leaving it up to be tapped instead reads as
    /// the wheel being stuck: it stays there until something is tapped, and everything it suppresses while it's up stays suppressed with it. A double tap still opens
    /// a wheel which waits to be tapped, so that way of picking a color isn't lost.
    private func endColorWheelHold() {
        colorWheelHoldTimeoutWorkItem?.cancel()
        colorWheelHoldTimeoutWorkItem = nil

        guard let wheel = colorWheelView else { return }

        if let hexColor = wheel.highlightedHexColor {
            apply(hexColor: hexColor)
        }
        dismissColorWheel(animated: true)
    }

    private func showColorWheel() {
        showColorWheel(at: pencilAnchorLocation())
    }

    private func showColorWheel(at location: CGPoint) {
        guard let tool = pdfController?.annotationStateManager.state else { return }

        guard let hexColors = tool.toolbarTool?.annotationType?.colors, !hexColors.isEmpty else {
            // Eraser has no colors, so keep showing the tool options popover, which is where its size slider lives.
            parentDelegate?.toggleToolOptions()
            return
        }

        let wheel = PDFColorWheelView(
            hexColors: hexColors,
            selectedHexColor: viewModel.state.toolColors[tool]?.hexString,
            anchor: location,
            handBearing: pencilHandBearing(),
            colorPicked: { [weak self] hexColor in
                guard let self else { return }
                apply(hexColor: hexColor)
                dismissColorWheel(animated: true)
            },
            dismissRequested: { [weak self] in
                self?.dismissColorWheel(animated: true)
            }
        )
        wheel.overrideUserInterfaceStyle = viewModel.state.settings.appearanceMode.userInterfaceStyle
        // The wheel takes over the pencil, so the tool preview would only be a leftover dot underneath it.
        hideToolPreview()
        wheel.show(in: view)
        // The wheel covers the page views, so PSPDFKit's gestures stop hearing about the pencil while it's up and it needs to follow the pencil itself. Nothing else
        // watches this view, so there's nothing here to compete with.
        let hoverRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(pencilHoverChanged(_:)))
        wheel.addGestureRecognizer(hoverRecognizer)
        colorWheelView = wheel
    }

    /// Applies a color picked in the wheel to the active tool. Same action the tool options popover uses, so defaults, draw color and toolbar all follow.
    private func apply(hexColor: String) {
        guard let tool = pdfController?.annotationStateManager.state else { return }
        viewModel.process(action: .setToolOptions(color: hexColor, size: nil, tool: tool))
    }

    private func dismissColorWheel(animated: Bool) {
        guard let wheel = colorWheelView else { return }
        // Cleared synchronously, so that a wheel triggered again during the dismissal animation is created immediately.
        colorWheelView = nil
        wheel.isUserInteractionEnabled = false
        wheel.hide(animated: animated, completion: { [weak self] in
            self?.removeColorWheelsFromViewHierarchy()
        })
        // The wheel was the only reason the preview was suppressed, so it comes straight back rather than waiting for the pencil to move again.
        refreshToolPreview()
    }

    /// Most recent pencil location, falling back to the center of the document when it's not known or too old to be useful.
    private func pencilAnchorLocation() -> CGPoint {
        guard let location = recentPencilHover()?.point, view.bounds.contains(location) else {
            return CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
        return location
    }

    /// Direction of the pencil's barrel, and so roughly of the hand holding it, which is only known while the pencil hovers. `nil` when there's no usable recent hover,
    /// in which case the wheel picks its own orientation.
    private func pencilHandBearing() -> CGFloat? {
        return recentPencilHover()?.handBearing
    }

    /// Uses the azimuth unit vector rather than the azimuth angle, because the vector is already in the view's coordinate space and so carries no sign ambiguity.
    /// Points along the barrel, away from the tip and toward the hand.
    private func handBearing(from recognizer: UIHoverGestureRecognizer) -> CGFloat? {
        guard recognizer.altitudeAngle <= Self.maximumUsableAzimuthAltitude else { return nil }
        let azimuth = recognizer.azimuthUnitVector(in: view)
        return atan2(azimuth.dy, azimuth.dx)
    }

    private func recentPencilHover() -> (point: CGPoint, handBearing: CGFloat?, timestamp: CFTimeInterval)? {
        guard let hover = lastPencilHover, isPencilHovering || (CACurrentMediaTime() - hover.timestamp) <= Self.pencilLocationLifetime else { return nil }
        return hover
    }

    // MARK: - Tool preview

    /// Shows what the active tool will draw, under the hovering pencil. Shown whenever a tool which draws something is active, except while the color wheel is up,
    /// where it would only sit underneath the wheel saying nothing.
    private func updateToolPreview(at location: CGPoint) {
        guard !isColorWheelVisible, !isEditingText, let tool = pdfController?.annotationStateManager.state, let preview = toolPreview(for: tool, at: location) else {
            hideToolPreview()
            return
        }

        let previewView = toolPreviewView ?? makeToolPreviewView()
        previewView.update(center: preview.center, shape: preview.shape, color: preview.color)
        previewView.isHidden = false
        // The color wheel and PSPDFKit both add views over the document, so the preview claims the top again whenever it's shown.
        view.bringSubviewToFront(previewView)
    }

    private func toolPreview(for tool: PSPDFKit.Annotation.Tool, at location: CGPoint) -> (shape: PencilToolPreviewView.Shape, color: UIColor?, center: CGPoint)? {
        let scale = pageScale(at: location)

        switch tool {
        case .ink:
            return (.nib(diameter: viewModel.state.activeLineWidth * scale), viewModel.state.toolColors[tool], location)

        case .eraser:
            return (.nib(diameter: viewModel.state.activeEraserSize * scale), nil, location)

        case .highlight, .underline:
            let color = viewModel.state.toolColors[tool]

            // Over a word, the preview takes that word's own shape, so it shows what would actually be marked rather than an approximation of it.
            if let word = wordFrame(at: location) {
                let size = tool == .highlight ? word.size : CGSize(width: word.width, height: Self.underlinePreviewThickness * scale)
                let center = tool == .highlight ? CGPoint(x: word.midX, y: word.midY) : CGPoint(x: word.midX, y: word.maxY)
                return (.band(size: size), color, center)
            }

            // Away from text there's nothing to take the shape of, so the markup tools fall back to something the size of a line of text. The highlighter stands
            // upright, where it reads as a chisel tip waiting for a line rather than as a mark already made, and the underline stays flat, which is what it leaves.
            let size = tool == .highlight
                ? CGSize(width: Self.highlightPreviewThickness * scale, height: Self.markupPreviewLength * scale)
                : CGSize(width: Self.markupPreviewLength * scale, height: Self.underlinePreviewThickness * scale)
            return (.band(size: size), color, location)

        default:
            return nil
        }
    }

    /// Frame of the word under given point, in this view's coordinates, or `nil` when the pencil isn't over text.
    private func wordFrame(at location: CGPoint) -> CGRect? {
        guard let pageView = pageView(at: location), let textParser = viewModel.state.document.textParserForPage(at: pageView.pageIndex) else { return nil }

        let pointOnPage = pageView.convert(view.convert(location, to: pageView), to: pageView.pdfCoordinateSpace)

        guard let word = textParser.words.first(where: { $0.frame.contains(pointOnPage) }) else { return nil }

        return view.convert(pageView.convert(word.frame, from: pageView.pdfCoordinateSpace), from: pageView)
    }

    private func pageView(at location: CGPoint) -> PDFPageView? {
        guard let pdfController else { return nil }
        return pdfController.visiblePageViews.first(where: { $0.convert($0.bounds, to: view).contains(location) }) ?? pdfController.visiblePageViews.first
    }

    /// Tool sizes are in PDF points, so they have to be scaled to match what's actually drawn on screen. `scaleForPageView` is what PSPDFKit itself uses to turn a line
    /// width into one, and it covers both how the page is fitted and how far it's zoomed in - the zoom alone would leave everything far too small.
    private func pageScale(at location: CGPoint) -> CGFloat {
        return pageView(at: location)?.scaleForPageView ?? 1
    }

    private func makeToolPreviewView() -> PencilToolPreviewView {
        let previewView = PencilToolPreviewView(frame: CGRect())
        view.addSubview(previewView)
        toolPreviewView = previewView
        return previewView
    }

    /// Re-evaluates the preview without waiting for the pencil to move. Picking a tool, a color or a size while the pencil already hovers produces no new hover event,
    /// so the preview would otherwise only catch up once the pencil was moved.
    private func refreshToolPreview() {
        guard isPencilHovering, let location = lastPencilHover?.point else {
            hideToolPreview()
            return
        }
        updateToolPreview(at: location)
    }

    private func hideToolPreview() {
        toolPreviewView?.isHidden = true
    }

    @objc private func pencilHoverChanged(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            pencilDidHover(at: recognizer.location(in: view), handBearing: handBearing(from: recognizer))

        case .ended, .cancelled, .failed:
            pencilDidStopHovering()

        case .possible:
            break

        @unknown default:
            break
        }
    }

    /// Listens in on the gestures PSPDFKit already runs on each page view, rather than adding more beside them and losing to them. Its hover gesture reports hovers over
    /// a page reliably - that's what it's there for - so being told about the same ones is worth far more than winning a fight over them.
    private func prepareHoverHandling(for pageView: PDFPageView) {
        observePageGestures(in: pageView)
        // Again once the page view has finished being put together, since PSPDFKit doesn't necessarily have its own gestures in place by the time a page is announced.
        DispatchQueue.main.async { [weak self, weak pageView] in
            guard let self, let pageView else { return }
            observePageGestures(in: pageView)
        }
    }

    /// Adds this controller as a second target of a page view's gestures, leaving whatever they already do completely alone. Hover gestures report where the pencil is,
    /// and the rest report that something has started happening on the page, which is the moment the preview stops describing anything. Page views are recycled, so a
    /// gesture which is already being listened to is left as it is.
    private func observePageGestures(in view: UIView) {
        for recognizer in view.gestureRecognizers ?? [] {
            guard !observedPageGestures.contains(recognizer) else { continue }
            observedPageGestures.add(recognizer)

            if recognizer is UIHoverGestureRecognizer {
                recognizer.isEnabled = true
                recognizer.addTarget(self, action: #selector(pencilHoverChanged(_:)))
            } else {
                recognizer.addTarget(self, action: #selector(pageGestureChanged(_:)))
            }
        }

        for subview in view.subviews {
            observePageGestures(in: subview)
        }
    }

    /// Something has started on the page - a stroke, a text selection drag, a tap. Whatever the preview was describing is now happening, so it goes away.
    @objc private func pageGestureChanged(_ recognizer: UIGestureRecognizer) {
        guard recognizer.state == .began else { return }
        pencilDidStopHovering()
    }

    /// The pencil is above the screen at given location. The single way that becomes true, so that nothing which depends on it can disagree about it.
    private func pencilDidHover(at location: CGPoint, handBearing: CGFloat?) {
        isPencilHovering = true
        lastPencilHover = (location, handBearing, CACurrentMediaTime())
        // Hover updates are more frequent than squeeze updates, so they're what actually drives the wheel while the pencil button is held down.
        colorWheelView?.setPenLocation(location, handBearing: handBearing)
        updateToolPreview(at: location)
    }

    /// The pencil is no longer above the screen, whether it was lifted away or put down on it. The single way that becomes true, so that nothing which depends on it
    /// can disagree about it.
    ///
    /// There was a timeout here as well, on the grounds that a hover might end without saying so, taken from a gap in hover updates. A pencil held still reports
    /// nothing at all, so all it really did was take the preview away while the pencil was sitting right there.
    private func pencilDidStopHovering() {
        guard isPencilHovering else { return }
        // The last known location is kept, it's still the best guess for where the pencil is if the color wheel is asked for right after.
        isPencilHovering = false
        hideToolPreview()
    }

    private func update(state: PDFReaderState) {
        if let pdfController {
            update(state: state, pdfController: pdfController)
        } else if let unlockController {
            update(state: state, unlockController: unlockController)
        }
    }

    private func update(state: PDFReaderState, unlockController: UnlockPDFViewController) {
        guard state.unlockSuccessful == true else { return }
        // Remove unlock controller
        unlockController.willMove(toParent: nil)
        unlockController.view.removeFromSuperview()
        unlockController.removeFromParent()
        unlockController.didMove(toParent: nil)
        // Setup PDF controller to show unlocked PDF
        setupPdfController()
    }

    private func update(state: PDFReaderState, pdfController: PDFViewController) {
        if state.changes.contains(.appearance) {
            updateInterface(to: state.settings.appearanceMode, userInterfaceStyle: state.interfaceStyle)
        }

        if state.changes.contains(.settings) {
            if pdfController.configuration.scrollDirection != state.settings.direction ||
                pdfController.configuration.pageTransition != state.settings.transition ||
                pdfController.configuration.pageMode != state.settings.pageMode ||
                pdfController.configuration.spreadFitting != state.settings.pageFitting ||
                pdfController.configuration.isFirstPageAlwaysSingle != state.settings.isFirstPageAlwaysSingle {
                pdfController.updateConfiguration { configuration in
                    configuration.scrollDirection = state.settings.direction
                    configuration.pageTransition = state.settings.transition
                    configuration.pageMode = state.settings.pageMode
                    configuration.spreadFitting = state.settings.pageFitting
                    configuration.isFirstPageAlwaysSingle = state.settings.isFirstPageAlwaysSingle
                }
            }
        }

        if state.changes.contains(.selection) {
            if let annotation = state.selectedAnnotation {
                if let location = state.focusDocumentLocation {
                    // If annotation was selected, focus if needed
                    focus(annotation: annotation, at: location, document: state.document)
                } else if annotation.type != .ink || pdfController.annotationStateManager.state != .ink {
                    // Update selection if needed.
                    // Never select ink annotation if inking is active in case the user needs to continue typing.
                    select(annotation: annotation, pageIndex: pdfController.pageIndex, document: state.document)
                }
            } else {
                // Otherwise remove selection if needed
                deselectAnnotation(pdfController: pdfController)
            }

            showPopupAnnotationIfNeeded(state: state)
        }

        if state.changes.contains(.visiblePageFromThumbnailList) {
            let currentPageIndex = pdfController.pageIndex
            pdfController.setPageIndex(PageIndex(state.visiblePage), animated: false)
            pdfController.backForwardList.register(PSPDFKit.GoToAction(pageIndex: currentPageIndex))
        }

        if let tool = state.changedColorForTool, let color = state.toolColors[tool] {
            set(color: color, for: tool, in: pdfController.annotationStateManager, state: state)
            refreshToolPreview()
        }

        if state.changes.contains(.activeLineWidth) {
            pdfController.annotationStateManager.lineWidth = state.activeLineWidth
            refreshToolPreview()
        }

        if state.changes.contains(.activeEraserSize) {
            pdfController.annotationStateManager.lineWidth = state.activeEraserSize
            refreshToolPreview()
        }

        if state.changes.contains(.activeFontSize) {
            pdfController.annotationStateManager.fontSize = state.activeFontSize
        }

        if let notification = state.pdfNotification {
            updatePDF(notification: notification, state: state, pdfController: pdfController)
        }

        if state.changes.contains(.initialDataLoaded) {
            pdfController.setPageIndex(PageIndex(state.visiblePage), animated: false)
            if let annotation = state.selectedAnnotation {
                select(annotation: annotation, pageIndex: pdfController.pageIndex, document: state.document)
            }
            if let previewRects = state.previewRects {
                DispatchQueue.main.async {
                    self.show(previewRects: previewRects, pageIndex: pdfController.pageIndex, document: state.document)
                }
            }
        }

        func deselectAnnotation(pdfController: PDFViewController) {
            updateSelectionOnVisiblePages(of: pdfController, annotation: nil)
            // We don't know the deselection page, as pdfController.pageIndex may be the one of last annotation addition.
            // To overcome this we discard selection in all visible page views.
            pdfController.visiblePageViews.forEach({ $0.discardSelection(animated: false) })
        }

        func updatePDF(notification: Notification, state: PDFReaderState, pdfController: PDFViewController) {
            switch notification.name {
            case .PSPDFAnnotationChanged:
                guard let changes = notification.userInfo?[PSPDFAnnotationChangedNotificationKeyPathKey] as? [String] else { return }
                // Changing annotation color changes the `lastUsed` color in `annotationStateManager` (#487), so we have to re-set it.
                if changes.contains("color"), let annotation = notification.object as? PSPDFKit.Annotation, let tool = annotation.tool, let color = state.toolColors[tool] {
                    set(color: color, for: tool, in: pdfController.annotationStateManager, state: state)
                }

            case .PSPDFAnnotationsAdded:
                guard let annotations = notification.object as? [PSPDFKit.Annotation] else { return }
                // If Image annotation is active after adding the annotation, deactivate it
                if annotations.first is PSPDFKit.SquareAnnotation && pdfController.annotationStateManager.state == .square, let color = state.toolColors[.square] {
                    // Don't reset apple pencil detection here, this is automatic action, not performed by user.
                    toggle(annotationTool: .square, color: color, tappedWithStylus: false, resetPencilManager: false)
                }

            default:
                break
            }
        }

        func set(color: UIColor, for tool: PSPDFKit.Annotation.Tool, in stateManager: AnnotationStateManager, state: PDFReaderState) {
            let type: AnnotationType?
            switch tool {
            case .highlight:
                type = .highlight

            case .underline:
                type = .underline

            default:
                type = nil
            }
            let appearance = Appearance.from(appearanceMode: state.settings.appearanceMode, interfaceStyle: state.interfaceStyle)
            let toolColor = AnnotationColorGenerator.color(from: color, type: type, appearance: appearance).color
            stateManager.setLastUsedColor(toolColor, annotationString: tool)
            if stateManager.state == tool {
                stateManager.drawColor = toolColor
            }
        }
    }

    private func updateInterface(to appearanceMode: ReaderSettingsState.Appearance, userInterfaceStyle: UIUserInterfaceStyle) {
        switch appearanceMode {
        case .automatic:
            pdfController?.appearanceModeManager.appearanceMode = userInterfaceStyle == .dark ? .night : []
            pdfController?.overrideUserInterfaceStyle = userInterfaceStyle
            unlockController?.overrideUserInterfaceStyle = userInterfaceStyle

        case .light:
            pdfController?.appearanceModeManager.appearanceMode = []
            pdfController?.overrideUserInterfaceStyle = .light
            unlockController?.overrideUserInterfaceStyle = .light

        case .sepia:
            pdfController?.appearanceModeManager.appearanceMode = .sepia
            pdfController?.overrideUserInterfaceStyle = .light
            unlockController?.overrideUserInterfaceStyle = .light

        case .dark:
            pdfController?.appearanceModeManager.appearanceMode = .night
            pdfController?.overrideUserInterfaceStyle = .dark
            unlockController?.overrideUserInterfaceStyle = .dark
        }
    }

    private func showPopupAnnotationIfNeeded(state: PDFReaderState) {
        guard !(parentDelegate?.isSidebarVisible ?? false),
              let annotation = state.selectedAnnotation,
              annotation.type != .freeText,
              let pageView = pdfController?.pageViewForPage(at: UInt(annotation.page)) else { return }

        let key = annotation.readerKey
        var frame = view.convert(annotation.boundingBox(boundingBoxConverter: viewModel.state.document), from: pageView.pdfCoordinateSpace)
        frame.origin.y += parentDelegate?.documentTopOffset ?? 0
        let observable = coordinatorDelegate?.showAnnotationPopover(
            state: state,
            sourceRect: frame,
            popoverDelegate: self,
            userInterfaceStyle: viewModel.state.settings.appearanceMode.userInterfaceStyle
        )

        guard let observable else { return }
        observable.subscribe(onNext: { [weak viewModel] state in
            guard let viewModel else { return }
            // These are `AnnotationPopoverViewController` properties updated individually
            if state.changes.contains(.color) {
                viewModel.process(action: .setColor(key: key.key, color: state.color))
            }
            if state.changes.contains(.comment) {
                viewModel.process(action: .setComment(key: key.key, comment: state.comment))
            }
            if state.changes.contains(.deletion) {
                viewModel.process(action: .removeAnnotation(key))
            }
            if state.changes.contains(.lineWidth) {
                viewModel.process(action: .setLineWidth(key: key.key, width: state.lineWidth))
            }
            if state.changes.contains(.tags) {
                viewModel.process(action: .setTags(key: key.key, tags: state.tags))
            }
            // These are `AnnotationEditViewController` properties updated all at once with Save button
            if state.changes.contains(.pageLabel) || state.changes.contains(.highlight) || state.changes.contains(.type) {
                var fontSize: CGFloat = 0
                if state.type == .freeText, let annotation = viewModel.state.annotation(for: key) {
                    // We should never actually get here, because Annotation Popup is not shown for Free Text Annotations. But in case we do get here, let's fetch current font size and pass it along.
                    fontSize = annotation.fontSize ?? 0
                }
                viewModel.process(action: .updateAnnotationProperties(
                    key: key.key,
                    type: state.type,
                    color: state.color,
                    lineWidth: state.lineWidth,
                    fontSize: fontSize,
                    pageLabel: state.pageLabel,
                    updateSubsequentLabels: state.updateSubsequentLabels,
                    highlightText: state.highlightText,
                    higlightFont: state.highlightFont
                ))
            }
        })
        .disposed(by: disposeBag)
    }

    private func updatePencilSettingsIfNeeded() {
        guard self.pdfController?.annotationStateManager.state == .ink else { return }
        self.pdfController?.annotationStateManager.stylusMode = UIPencilInteraction.prefersPencilOnlyDrawing ? .stylus : .fromStylusManager
    }

    /// Scrolls to given page if needed.
    /// - parameter pageIndex: Page index to which the `pdfController` is supposed to scroll.
    /// - parameter animated: `true` if scrolling is animated, `false` otherwise.
    /// - parameter completion: Optioal completion block called after scroll. Block is also called when scroll was not needed.
    private func scrollIfNeeded(to pageIndex: PageIndex, animated: Bool, completion: (() -> Void)? = nil) {
        guard let pdfController, pdfController.pageIndex != pageIndex else {
            completion?()
            return
        }
        let currentPageIndex = pdfController.pageIndex

        if !animated {
            pdfController.setPageIndex(pageIndex, animated: false)
            pdfController.backForwardList.register(PSPDFKit.GoToAction(pageIndex: currentPageIndex))
            completion?()
            return
        }

        UIView.animate(withDuration: 0.25, animations: {
            pdfController.setPageIndex(pageIndex, animated: false)
        }, completion: { finished in
            pdfController.backForwardList.register(PSPDFKit.GoToAction(pageIndex: currentPageIndex))
            guard finished else { return }
            completion?()
        })
    }

    func setInterface(hidden: Bool) {
        pdfController?.userInterfaceView.alpha = hidden ? 0 : 1
        if hidden {
            dismissColorWheel(animated: false)
            pencilDidStopHovering()
        }
    }

    // MARK: - Selection

    /// Shows temporary preview highlight in given rects. Used by note editor to highlight original position of annotation. The annotation may already be deleted, so we're highlighting the original location.
    /// - parameter previewRects: Rects to select.
    /// - parameter pageIndex: Page index of page where (selection should happen.
    /// - parameter document: Active `Document` instance.
    private func show(previewRects: [CGRect], pageIndex: PageIndex, document: PSPDFKit.Document) {
        guard !previewRects.isEmpty, let pageView = pdfController?.pageViewForPage(at: pageIndex) else { return }

        let convertedRects = previewRects.map({ pageView.convert($0, from: pageView.pdfCoordinateSpace) })
        let view = AnnotationPreviewView(frames: convertedRects)
        view.alpha = 0
        pageView.contentView.addSubview(view)

        UIView.animate(
            withDuration: 0.2,
            delay: 0.5,
            options: .curveEaseIn,
            animations: {
                view.alpha = 1
            },
            completion: { _ in
                hidePreview()
            }
        )

        func hidePreview() {
            UIView.animate(
                withDuration: 0.2,
                delay: 0.2,
                options: .curveEaseOut,
                animations: {
                    view.alpha = 0
                },
                completion: { _ in
                    view.removeFromSuperview()
                }
            )
        }
    }

    /// Selects given annotation in document.
    /// - parameter annotation: Annotation to select.
    /// - parameter pageIndex: Page index of page where selection should happen.
    /// - parameter document: Active `Document` instance.
    private func select(annotation: PDFAnnotation, pageIndex: PageIndex, document: PSPDFKit.Document) {
        guard let pdfController,
              let pageView = updateSelectionOnVisiblePages(of: pdfController, annotation: annotation) ?? pdfController.pageViewForPage(at: pageIndex),
              let pdfAnnotation = document.annotation(at: pageView.pageIndex, with: annotation.key)
        else { return }
        pageView.selectedAnnotations = [pdfAnnotation]
    }

    /// Focuses given annotation and selects it if it's not selected yet.
    private func focus(annotation: PDFAnnotation, at location: AnnotationDocumentLocation, document: PSPDFKit.Document) {
        let pageIndex = PageIndex(location.page)
        scrollIfNeeded(to: pageIndex, animated: true) {
            self.select(annotation: annotation, pageIndex: pageIndex, document: document)
        }
    }

    /// Updates `SelectionView` for visible `PDFPageView`s of `PDFViewController` based on selected annotation.
    /// - parameter pdfController: `PDFViewController` instance for given PDF view controller.
    /// - parameter selectedAnnotation: `PDFAnnotation` Selected annotation or `nil` if there is no selection.
    /// - returns: Returns the affected`PDFPageView` if a `SelectionView` was added, otherwise `nil`
    @discardableResult
    private func updateSelectionOnVisiblePages(of pdfController: PDFViewController, annotation: PDFAnnotation?) -> PDFPageView? {
        // Delete existing custom highlight/underline selection view
        if selectionView != nil {
            selectionView?.removeFromSuperview()
            selectionView = nil
        }

        guard let selection = annotation, let pageView = pdfController.visiblePageViews.first(where: { $0.pageIndex == PageIndex(selection.page) }) else { return nil }
        if selection.type == .highlight || selection.type == .underline {
            // Add custom highlight/underline selection view if needed
            let frame = pageView.convert(selection.boundingBox(boundingBoxConverter: viewModel.state.document), from: pageView.pdfCoordinateSpace)
            let selectionView = SelectionView(frame: frame)
            pageView.annotationContainerView.addSubview(selectionView)
            self.selectionView = selectionView
        }
        return pageView
    }

    // MARK: - Setups

    /// Text editing is watched from the keyboard rather than by looking up a first responder, which hover arrives far too often to be doing.
    private func setupTextEditingObservingIfNeeded() {
        guard keyboardCancellables.isEmpty else { return }

        keyboardCancellables = [
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.isEditingText = true
                    self?.hideToolPreview()
                },
            NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.isEditingText = false
                    self?.refreshToolPreview()
                }
        ]
    }

    private func setupPdfController() {
        let pdfController = createPdfController(with: viewModel.state.document, settings: viewModel.state.settings)
        pdfController.view.translatesAutoresizingMaskIntoConstraints = false

        pdfController.willMove(toParent: self)
        addChild(pdfController)
        view.addSubview(pdfController.view)
        pdfController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            pdfController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ])
        if #available(iOS 26.0.0, *) {
            NSLayoutConstraint.activate([
                pdfController.view.topAnchor.constraint(equalTo: view.topAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                pdfController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
            ])
        }

        self.pdfController = pdfController

        func createPdfController(with document: PSPDFKit.Document, settings: PDFSettings) -> PDFViewController {
            let pdfConfiguration = PDFConfiguration { builder in
                builder.scrollDirection = settings.direction
                builder.pageTransition = settings.transition
                builder.pageMode = settings.pageMode
                builder.spreadFitting = settings.pageFitting
                builder.isFirstPageAlwaysSingle = settings.isFirstPageAlwaysSingle
                builder.documentLabelEnabled = .NO
                builder.allowedAppearanceModes = [.night]
                builder.isCreateAnnotationMenuEnabled = viewModel.state.library.metadataEditable
                builder.createAnnotationMenuGroups = createAnnotationCreationMenuGroups()
                builder.isTextSelectionEnabled = true
                builder.isImageSelectionEnabled = true
                builder.showBackActionButton = false
                builder.showForwardActionButton = false
                builder.contentMenuConfiguration = ContentMenuConfiguration {
                    $0.annotationToolChoices = { _, _, _, _ in
                        return [.highlight, .underline]
                    }
                }
                builder.scrubberBarType = .horizontal
                // builder.thumbnailBarMode = .scrubberBar
                builder.markupAnnotationMergeBehavior = .never
                builder.freeTextAccessoryViewEnabled = false
                builder.overrideClass(PSPDFKit.HighlightAnnotation.self, with: HighlightAnnotation.self)
                builder.overrideClass(PSPDFKit.NoteAnnotation.self, with: NoteAnnotation.self)
                builder.overrideClass(PSPDFKit.SquareAnnotation.self, with: SquareAnnotation.self)
                builder.overrideClass(PSPDFKit.UnderlineAnnotation.self, with: UnderlineAnnotation.self)
                builder.overrideClass(PSPDFKit.AnnotationManager.self, with: AnnotationManager.self)
                builder.overrideClass(PSPDFKitUI.FreeTextAnnotationView.self, with: FreeTextAnnotationView.self)
                builder.propertiesForAnnotations = [.freeText: []]
                builder.editableAnnotationTypes = AnnotationsConfig.editableAnnotationTypes
            }

            let controller = PDFViewController(document: document, configuration: pdfConfiguration)
            controller.view.backgroundColor = .systemGray6
            controller.delegate = self
            controller.backForwardList.delegate = self
            controller.formSubmissionDelegate = nil
            controller.annotationStateManager.add(self)
            controller.annotationStateManager.pencilInteraction.delegate = self
            controller.annotationStateManager.pencilInteraction.isEnabled = true
            pageIndexCancellable = controller.pageIndexPublisher.sink { [weak self, weak viewModel] event in
                self?.parentDelegate?.pageIndexChanged(event: event)
                viewModel?.process(action: .setVisiblePage(page: Int(event.pageIndex), userActionFromDocument: event.reason == .userInterface, fromThumbnailList: false))
            }
            setup(scrubberBar: controller.userInterfaceView.scrubberBar)
            setup(interactions: controller.interactions)
            controller.shouldResetAppearanceModeWhenViewDisappears = false
            controller.documentViewController?.delegate = self

            return controller

            func createAnnotationCreationMenuGroups() -> [AnnotationToolConfiguration.ToolGroup] {
                return [AnnotationToolConfiguration.ToolGroup(items: [
                    AnnotationToolConfiguration.ToolItem(type: .note),
                    AnnotationToolConfiguration.ToolItem(type: .square)
                ])]
            }

            func setup(scrubberBar: ScrubberBar) {
                let appearance = UIToolbarAppearance()
                appearance.backgroundColor = Asset.Colors.pdfScrubberBarBackground.color

                scrubberBar.standardAppearance = appearance
                scrubberBar.compactAppearance = appearance
                scrubberBar.delegate = self
            }

            func setup(interactions: DocumentViewInteractions) {
                // Preserve zoom when tapping the edges of the document to scroll between pages.
                // PSPDFKit's default fast scroll navigates via `scrollToNextSpread`, which resets zoom on the new
                // spread. Capture the current zoom scale here so we can re-apply it once the new page becomes visible
                // (see `pdfViewController(_:willBeginDisplaying:forPageAt:)`). Normal scrolling is unaffected since
                // this only fires for edge-tap navigation.
                interactions.fastScroll.addActivationCallback { [weak self] _, _, _ in
                    guard let self, let zoomScale = self.pdfController?.visiblePageViews.first?.zoomView?.zoomScale, zoomScale > 1 else { return }
                    self.pendingCornerTapZoomScale = zoomScale
                }

                // Only supported annotations can be selected
                interactions.selectAnnotation.addActivationCondition { context, _, _ -> Bool in
                    return AnnotationsConfig.supported.contains(context.annotation.type)
                }

                interactions.selectAnnotation.addActivationCallback { [weak self] context, _, _ in
                    let key = context.annotation.key ?? context.annotation.uuid
                    let type: PDFReaderAnnotationKey.Kind
                    switch context.annotation.source {
                    case .database:
                        type = .database

                    case .document:
                        type = .document

                    case nil:
                        type = context.annotation.isZoteroAnnotation ? .database : .document
                    }
                    self?.viewModel.process(action: .selectAnnotationFromDocument(PDFReaderAnnotationKey(key: key, type: type)))
                }

                interactions.toggleUserInterface.addActivationCallback { [weak self] _, _, _ in
                    guard let self, let interfaceView = self.pdfController?.userInterfaceView else { return }
                    parentDelegate?.interfaceVisibilityDidChange(to: interfaceView.alpha != 0)
                }

                interactions.deselectAnnotation.addActivationCondition { [weak viewModel] _, _, _ -> Bool in
                    // `interactions.deselectAnnotation.addActivationCallback` is not always called when highglight annotation tool is enabled.
                    viewModel?.process(action: .deselectSelectedAnnotationFromDocument)
                    return true
                }

                // Only Zotero-synced annotations can be edited
                interactions.editAnnotation.addActivationCondition { context, _, _ -> Bool in
                    return context.annotation.key != nil && context.annotation.isEditable
                }
            }
        }
    }
}

extension PDFDocumentViewController: PDFViewControllerDelegate {
    func pdfViewController(_ pdfController: PDFViewController, willBeginDisplaying pageView: PDFPageView, forPageAt pageIndex: Int) {
        prepareHoverHandling(for: pageView)

        if !searchResults.isEmpty {
            pdfController.searchHighlightViewManager.addHighlight(searchResults, animated: false)
        }
        // Re-apply zoom captured from the previous page when the user navigated via a corner tap.
        // We schedule the scale change asynchronously so PSPDFKit finishes its own zoom/layout pass first.
        if let zoomScale = pendingCornerTapZoomScale {
            pendingCornerTapZoomScale = nil
            DispatchQueue.main.async { [weak pageView] in
                pageView?.zoomView?.setZoomScale(zoomScale, animated: false)
            }
        }
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldShow controller: UIViewController, options: [String: Any]? = nil, animated: Bool) -> Bool {
        return false
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldSave document: PSPDFKit.Document, withOptions options: AutoreleasingUnsafeMutablePointer<NSDictionary>) -> Bool {
        return false
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldSelect annotations: [PSPDFKit.Annotation], on pageView: PDFPageView) -> [PSPDFKit.Annotation] {
        guard let annotation = annotations.first, annotation.type == .freeText else { return annotations }
        selectedAnnotationWasSelectedBefore = pageView.selectedAnnotations.contains(annotation)
        return annotations
    }

    func pdfViewController(
        _ sender: PDFViewController,
        menuForAnnotations annotations: [PSPDFKit.Annotation],
        onPageView pageView: PDFPageView,
        appearance: EditMenuAppearance,
        suggestedMenu: UIMenu
    ) -> UIMenu {
        guard let annotation = annotations.first,
              annotation.type == .freeText,
              let annotationView = pageView.visibleAnnotationViews.first(where: { $0.annotation == annotation }) as? FreeTextAnnotationView
        else { return UIMenu(children: []) }

        annotationView.delegate = self
        annotationView.annotationKey = annotation.key.flatMap({ .init(key: $0, type: .database) })

        if annotation.key != nil && selectedAnnotationWasSelectedBefore {
            // Focus only if Zotero annotation is selected, if annotation popup is dismissed and this annotation has been already selected
            _ = annotationView.beginEditing()
        }

        selectedAnnotationWasSelectedBefore = false

        return UIMenu(children: [])
    }

    func pdfViewController(_ sender: PDFViewController, menuForCreatingAnnotationAt point: CGPoint, onPageView pageView: PDFPageView, appearance: EditMenuAppearance, suggestedMenu: UIMenu) -> UIMenu {
        let origin = pageView.convert(point, to: pageView.pdfCoordinateSpace)
        let children: [UIMenuElement] = [
            UIAction(title: L10n.Pdf.AnnotationToolbar.note, handler: { [weak viewModel] _ in
                viewModel?.process(action: .createNote(pageIndex: pageView.pageIndex, origin: origin))
            }),
            UIAction(title: L10n.Pdf.AnnotationToolbar.image, handler: { [weak viewModel] _ in
                viewModel?.process(action: .createImage(pageIndex: pageView.pageIndex, origin: origin))
            })
        ]
        return UIMenu(children: children)
    }

    func pdfViewController(_ sender: PDFViewController, menuForText glyphs: GlyphSequence, onPageView pageView: PDFPageView, appearance: EditMenuAppearance, suggestedMenu: UIMenu) -> UIMenu {
        return filterActions(
            forMenu: suggestedMenu,
            predicate: { menuId, action -> UIMenuElement? in
                switch menuId {
                case .standardEdit:
                    switch action.identifier {
                    case .PSPDFKit.copy:
                        return action.replacing(title: L10n.copy, handler: { _ in
                            UIPasteboard.general.string = TextConverter.convertTextForCopying(from: glyphs.text)
                        })

                    default:
                        return action
                    }

                case .share:
                    guard action.identifier == .PSPDFKit.share else { return nil }
                    return action.replacing(handler: { [weak self] _ in
                        guard let self else { return }
                        coordinatorDelegate?.share(
                            text: glyphs.text,
                            rect: pageView.convert(glyphs.boundingBox, from: pageView.pdfCoordinateSpace),
                            view: pageView,
                            userInterfaceStyle: viewModel.state.settings.appearanceMode.userInterfaceStyle
                        )
                    })

                case .pspdfkitActions:
                    switch action.identifier {
                    case .PSPDFKit.searchDocument:
                        return action.replacing(handler: { [weak self] _ in
                            self?.parentDelegate?.showSearch(text: glyphs.text)
                        })

                    default:
                        return action
                    }

                case .PSPDFKit.annotate:
                    switch action.identifier {
                    case .pspdfkitAnnotationToolHighlight:
                        return action.replacing(title: L10n.Pdf.highlight, handler: createHighlightActionHandler(for: pageView, in: viewModel))

                    case .pspdfkitAnnotationToolUnderline:
                        return action.replacing(title: L10n.Pdf.underline, handler: createUnderlineActionHandler(for: pageView, in: viewModel))

                    default:
                        return action
                    }

                default:
                    return action
                }
            },
            populatingEmptyMenu: { menu -> [UIAction]? in
                switch menu.identifier {
                case .PSPDFKit.annotate:
                    return [
                        UIAction(title: L10n.Pdf.highlight, identifier: .pspdfkitAnnotationToolHighlight, handler: createHighlightActionHandler(for: pageView, in: viewModel)),
                        UIAction(title: L10n.Pdf.underline, identifier: .pspdfkitAnnotationToolUnderline, handler: createUnderlineActionHandler(for: pageView, in: viewModel))
                    ]

                default:
                    return nil
                }
            }
        )

        func filterActions(forMenu menu: UIMenu, predicate: (UIMenu.Identifier, UIAction) -> UIMenuElement?, populatingEmptyMenu: (UIMenu) -> [UIAction]?) -> UIMenu {
            return menu.replacingChildren(menu.children.compactMap { element -> UIMenuElement? in
                if let action = element as? UIAction {
                    if let element = predicate(menu.identifier, action) {
                        return element
                    } else {
                        return nil
                    }
                } else if let menu = element as? UIMenu {
                    if menu.children.isEmpty {
                        return populatingEmptyMenu(menu).flatMap({ menu.replacingChildren($0) }) ?? menu
                    } else {
                        // Filter children of submenus recursively.
                        return filterActions(forMenu: menu, predicate: predicate, populatingEmptyMenu: populatingEmptyMenu)
                    }
                } else {
                    return element
                }
            })
        }

        func createHighlightActionHandler(for pageView: PDFPageView, in viewModel: ViewModel<PDFReaderActionHandler>) -> UIActionHandler {
            let rects = pageView.selectionView.selectionRects.map({ pageView.convert($0.cgRectValue, to: pageView.pdfCoordinateSpace) })
            return { [weak viewModel] _ in
                guard let viewModel else { return }
                viewModel.process(action: .createHighlight(pageIndex: pageView.pageIndex, rects: rects))
                pageView.selectionView.selectedGlyphs = nil
            }
        }

        func createUnderlineActionHandler(for pageView: PDFPageView, in viewModel: ViewModel<PDFReaderActionHandler>) -> UIActionHandler {
            let rects = pageView.selectionView.selectionRects.map({ pageView.convert($0.cgRectValue, to: pageView.pdfCoordinateSpace) })
            return { [weak viewModel] _ in
                guard let viewModel else { return }
                viewModel.process(action: .createUnderline(pageIndex: pageView.pageIndex, rects: rects))
                pageView.selectionView.selectedGlyphs = nil
            }
        }
    }

    func pdfViewController(_ pdfController: PDFViewController, didSelectText text: String, with glyphs: [Glyph], at rect: CGRect, on pageView: PDFPageView) {
        parentDelegate?.didSelectText(text)
    }

    func pdfViewController(_ pdfController: PDFViewController, didFinishRenderTaskFor pageView: PDFPageView, error: (any Error)?) {
        if let error {
            DDLogError("PDFDocumentViewController: PDFViewController didFinishRenderTaskFor \(pageView) with error - \(error)")
        }
    }
}

extension PDFDocumentViewController: BackForwardActionListDelegate {
    func backForwardList(_ list: PSPDFKit.BackForwardActionList, requestedBackActionExecution actions: [Action], animated: Bool) {
        pdfController?.backForwardList(list, requestedBackActionExecution: actions, animated: animated)
        parentDelegate?.backActionExecuted()
    }

    func backForwardList(_ list: PSPDFKit.BackForwardActionList, requestedForwardActionExecution actions: [Action], animated: Bool) {
        pdfController?.backForwardList(list, requestedForwardActionExecution: actions, animated: animated)
        parentDelegate?.forwardActionExecuted()
    }

    func backForwardListDidUpdate(_ list: PSPDFKit.BackForwardActionList) {
        pdfController?.backForwardListDidUpdate(list)
        parentDelegate?.backForwardListDidUpdate(hasBackActions: list.backAction != nil, hasForwardActions: list.forwardAction != nil)
    }
}

extension PDFDocumentViewController: AnnotationStateManagerDelegate {
    func annotationStateManager(
        _ manager: AnnotationStateManager,
        didChangeState oldState: PSPDFKit.Annotation.Tool?,
        to newState: PSPDFKit.Annotation.Tool?,
        variant oldVariant: PSPDFKit.Annotation.Variant?,
        to newVariant: PSPDFKit.Annotation.Variant?
    ) {
        dismissColorWheel(animated: true)
        // Picking a tool is the moment the preview becomes meaningful, and there's usually no pencil movement right after it to bring the preview in by itself.
        refreshToolPreview()
        parentDelegate?.annotationTool(didChangeStateFrom: oldState, to: newState, variantFrom: oldVariant, to: newVariant)
    }

    func annotationStateManager(_ manager: AnnotationStateManager, didChangeUndoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        parentDelegate?.didChange(undoState: undoEnabled, redoState: redoEnabled)
    }
}

extension PDFDocumentViewController: UIPencilInteractionDelegate {
    private func process(action: UIPencilPreferredAction) {
        guard parentDelegate?.isToolbarVisible == true else { return }
        switch action {
        case .switchEraser:
            if let tool = pdfController?.annotationStateManager.state {
                if tool != .eraser {
                    toggle(annotationTool: .eraser, color: nil, tappedWithStylus: true)
                } else {
                    let previous = (PDFDocumentViewController.toolHistory.last(where: { $0 != .eraser }) ?? nil) ?? .ink
                    let color = viewModel.state.toolColors[previous]
                    toggle(annotationTool: previous, color: color, tappedWithStylus: true)
                }
            }

        case .switchPrevious:
            let previous: Annotation.Tool
            if let tool = pdfController?.annotationStateManager.state {
                // Find the most recent different tool – if it's the "nil tool", default to `tool` to unset current tool
                previous = (PDFDocumentViewController.toolHistory.last(where: { $0 != tool }) ?? nil) ?? tool
            } else {
                // Since we can't switch from nil to nil, find the most recent non-nil tool, default to .ink
                previous = (PDFDocumentViewController.toolHistory.last(where: { $0 != nil }) ?? nil) ?? .ink
            }
            let color = viewModel.state.toolColors[previous]
            toggle(annotationTool: previous, color: color, tappedWithStylus: true)

        case .showColorPalette, .showInkAttributes, .showContextualPalette:
            toggleColorWheel()

        case .runSystemShortcut, .ignore:
            break

        @unknown default:
            break
        }
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        process(action: UIPencilInteraction.preferredTapAction)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        let action = UIPencilInteraction.preferredSqueezeAction

        guard isColorPaletteAction(action) else {
            // Other actions stay discrete, they're performed once the squeeze ends.
            if squeeze.phase == .ended {
                process(action: action)
            }
            return
        }

        guard parentDelegate?.isToolbarVisible == true else { return }

        // A squeeze which requests colors is treated as a hold - the wheel is shown for as long as the button is held down, follows the pencil around and picks the
        // color the pencil points at when the button is released.
        switch squeeze.phase {
        case .began:
            beginColorWheelHold(at: pencilAnchorLocation())

        case .changed:
            colorWheelView?.setPenLocation(pencilAnchorLocation(), handBearing: pencilHandBearing())

        case .ended:
            endColorWheelHold()

        case .cancelled:
            dismissColorWheel(animated: true)

        @unknown default:
            break
        }
    }

    private func isColorPaletteAction(_ action: UIPencilPreferredAction) -> Bool {
        switch action {
        case .showColorPalette, .showInkAttributes, .showContextualPalette:
            return true

        default:
            return false
        }
    }
}

extension PDFDocumentViewController: UIPopoverPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let presentedNavigationController = presentationController.presentedViewController as? NavigationViewController,
              (presentedNavigationController.children.first as? AnnotationPopoverViewController) != nil,
              let type = viewModel.state.selectedAnnotation?.type,
              type == .highlight || type == .underline
        else { return }
        viewModel.process(action: .deselectSelectedAnnotationFromDocument)
    }
}

extension PDFDocumentViewController: FreeTextInputDelegate {
    func showColorPicker(sender: UIView, key: PDFReaderAnnotationKey, updated: @escaping (String) -> Void) {
        let color = viewModel.state.annotation(for: key)?.color
        coordinatorDelegate?.showToolSettings(
            tool: .freeText,
            colorHex: color,
            sizeValue: nil,
            sourceItem: sender,
            userInterfaceStyle: self.overrideUserInterfaceStyle,
            valueChanged: { [weak viewModel] newColor, _ in
                guard let newColor else { return }
                viewModel?.process(action: .setColor(key: key.key, color: newColor))
                updated(newColor)
            }
        )
    }
    
    func showFontSizePicker(sender: UIView, key: PDFReaderAnnotationKey, updated: @escaping (CGFloat) -> Void) {
        coordinatorDelegate?.showFontSizePicker(sender: sender, picked: { [weak viewModel] size in
            viewModel?.process(action: .setFontSize(key: key.key, size: size))
            updated(size)
        })
    }

    func showTagPicker(sender: UIView, key: PDFReaderAnnotationKey, updated: @escaping ([Tag]) -> Void) {
        let tags = Set((getTags(for: key) ?? []).compactMap({ $0.name }))
        coordinatorDelegate?.showTagPicker(libraryId: viewModel.state.library.identifier, selected: tags, userInterfaceStyle: viewModel.state.interfaceStyle, picked: { [weak viewModel] tags in
            viewModel?.process(action: .setTags(key: key.key, tags: tags))
            updated(tags)
        })
    }

    func deleteAnnotation(sender: UIView, key: PDFReaderAnnotationKey) {
        coordinatorDelegate?.showDeleteAlertForAnnotation(sender: sender, delete: { [weak viewModel] in
            viewModel?.process(action: .removeAnnotation(key))
        })
    }

    func change(fontSize: CGFloat, for key: PDFReaderAnnotationKey) {
        viewModel.process(action: .setFontSize(key: key.key, size: fontSize))
    }
    
    func getFontSize(for key: PDFReaderAnnotationKey) -> CGFloat? {
        return viewModel.state.annotation(for: key)?.fontSize
    }

    func getColor(for key: PDFReaderAnnotationKey) -> UIColor? {
        return (viewModel.state.annotation(for: key)?.color).flatMap({ UIColor(hex: $0) })
    }

    func getTags(for key: PDFReaderAnnotationKey) -> [Tag]? {
        return viewModel.state.annotation(for: key)?.tags
    }
}

class SelectionView: UIView {
    private static let inset: CGFloat = 4.5 // 2.5 for border, 2 for padding

    override init(frame: CGRect) {
        super.init(frame: frame.insetBy(dx: -Self.inset, dy: -Self.inset))
        commonSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        backgroundColor = .clear
        autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin, .flexibleBottomMargin, .flexibleRightMargin, .flexibleWidth, .flexibleHeight]
        layer.borderColor = Asset.Colors.annotationHighlightSelection.color.cgColor
        layer.borderWidth = 2.5
        layer.cornerRadius = 2.5
        layer.masksToBounds = true
    }
}

final class AnnotationPreviewView: SelectionView {
    init(frames: [CGRect]) {
        super.init(frame: AnnotationBoundingBoxCalculator.boundingBox(from: frames))
        for rect in frames {
            addRow(rect: CGRect(origin: CGPoint(x: (rect.origin.x - frame.origin.x), y: (rect.origin.y - frame.origin.y)), size: rect.size))
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func addRow(rect: CGRect) {
        let view = UIView()
        view.backgroundColor = Asset.Colors.annotationHighlightSelection.color.withAlphaComponent(0.25)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.frame = rect
        addSubview(view)
    }
}

extension UIMenu.Identifier {
    fileprivate static let pspdfkitActions = UIMenu.Identifier(rawValue: "com.pspdfkit.menu.actions")
}

extension UIAction {
    fileprivate func replacing(title: String? = nil, handler: @escaping UIActionHandler) -> UIAction {
        UIAction(
            title: title ?? self.title,
            subtitle: subtitle,
            image: title != nil ? nil : image,
            identifier: identifier,
            discoverabilityTitle: discoverabilityTitle,
            attributes: attributes,
            state: state,
            handler: handler
        )
    }
}

extension UIAction.Identifier {
    fileprivate static let pspdfkitAnnotationToolHighlight = UIAction.Identifier(rawValue: "com.pspdfkit.action.annotation-tool-Highlight")
    fileprivate static let pspdfkitAnnotationToolUnderline = UIAction.Identifier(rawValue: "com.pspdfkit.action.annotation-tool-Underline")
}

extension PDFDocumentViewController: PDFDocumentViewControllerDelegate {
    func documentViewController(_ documentViewController: PSPDFKitUI.PDFDocumentViewController, configureScrollView scrollView: UIScrollView) {
        scrollView.delegate = self
    }
}

extension PDFDocumentViewController: UIScrollViewDelegate {
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        return false
    }
}

extension PDFDocumentViewController: PSPDFKitUI.ScrubberBarDelegate {
    func scrubberBar(_ scrubberBar: ScrubberBar, didSelectPageAt pageIndex: PageIndex) {
        guard let pdfController, pdfController.pageIndex != pageIndex else { return }
        let currentPageIndex = pdfController.pageIndex
        pdfController.userInterfaceView.scrubberBar(scrubberBar, didSelectPageAt: pageIndex)
        pdfController.backForwardList.register(PSPDFKit.GoToAction(pageIndex: currentPageIndex))
    }
}

extension PDFDocumentViewController: ParentWithSidebarDocumentController {}

/// Preview of what the active tool will draw, shown under the Apple Pencil while it hovers, the way PencilKit previews a brush. Sized in screen points, so it reflects
/// the current zoom as well as the tool's own size.
final class PencilToolPreviewView: UIView {
    /// What the tool leaves behind: a round nib for tools which draw a stroke, a flat one for the markup tools, which lay a band over a line of text.
    enum Shape {
        case nib(diameter: CGFloat)
        case band(size: CGSize)
    }

    private static let outlineWidth: CGFloat = 1.5
    /// A thin tool would otherwise preview as a dot too small to notice.
    private static let minimumNibSize: CGFloat = 10
    /// Bands take their size from the text they sit on, so they're only stopped from collapsing entirely rather than being held to a size of their own.
    private static let minimumBandSize: CGFloat = 2
    /// Drawn beneath the outline and a little wider, so that the outline reads against both the page and whatever is on it. A highlighter's own color over white paper
    /// is nearly invisible on its own, which is the whole reason this is here.
    private let contrastLayer: CAShapeLayer
    private let shapeLayer: CAShapeLayer

    override init(frame: CGRect) {
        contrastLayer = CAShapeLayer()
        shapeLayer = CAShapeLayer()
        super.init(frame: frame)
        isUserInteractionEnabled = false
        contrastLayer.fillColor = UIColor.clear.cgColor
        contrastLayer.lineWidth = Self.outlineWidth + 1.5
        shapeLayer.lineWidth = Self.outlineWidth
        layer.addSublayer(contrastLayer)
        layer.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - parameter shape: What the tool draws, already scaled to screen points.
    /// - parameter color: Color the tool draws in, or `nil` for tools which only take away, like the eraser.
    func update(center: CGPoint, shape: Shape, color: UIColor?) {
        let size: CGSize
        let cornerRadius: CGFloat

        switch shape {
        case .nib(let diameter):
            let side = max(Self.minimumNibSize, diameter)
            size = CGSize(width: side, height: side)
            cornerRadius = side / 2

        case .band(let bandSize):
            size = CGSize(width: max(Self.minimumBandSize, bandSize.width), height: max(Self.minimumBandSize, bandSize.height))
            cornerRadius = min(min(size.width, size.height) / 2, 2)
        }

        // Room for both outlines, the outer one being the wider of the two.
        let inset = Self.outlineWidth + 1.5
        bounds = CGRect(x: 0, y: 0, width: size.width + inset, height: size.height + inset)
        self.center = center

        let rect = CGRect(x: inset / 2, y: inset / 2, width: size.width, height: size.height)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath

        contrastLayer.frame = layer.bounds
        contrastLayer.path = path
        shapeLayer.frame = layer.bounds
        shapeLayer.path = path
        // Filled for tools which add something, hollow for the eraser. The outline is the tool's own color over a wider one in the opposite color, so that it reads on
        // white paper, on a dark page, and over a mark of its own color, which a single outline in the tool's color does not.
        shapeLayer.fillColor = color?.withAlphaComponent(0.4).cgColor ?? UIColor.clear.cgColor
        shapeLayer.strokeColor = (color ?? UIColor.label).resolvedColor(with: traitCollection).cgColor
        contrastLayer.strokeColor = UIColor.systemBackground.resolvedColor(with: traitCollection).withAlphaComponent(0.85).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowPath = path
    }
}
