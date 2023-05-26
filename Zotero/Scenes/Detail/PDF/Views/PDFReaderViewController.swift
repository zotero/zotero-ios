//
//  PDFReaderViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 31.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RxSwift

protocol PDFReaderContainerDelegate: AnyObject {
    var isSidebarVisible: Bool { get }
    var isSidebarTransitioning: Bool { get }
    var isCurrentlyVisible: Bool { get }

    func showSearch(pdfController: PDFViewController, text: String?)
}

class PDFReaderViewController: UIViewController {
    private enum NavigationBarButton: Int {
        case redo = 1
        case undo = 2
        case share = 3
    }

    private struct ToolbarState: Codable {
        enum Position: Int, Codable {
            case leading = 0
            case trailing = 1
            case top = 2
            case pinned = 3
        }

        let position: Position
        let visible: Bool
    }

    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag
    private static let toolbarCompactInset: CGFloat = 12
    private static let toolbarFullInsetInset: CGFloat = 20
    private static let minToolbarWidth: CGFloat = 300
    private static let sidebarButtonTag = 7
    private let statusBarHeight: CGFloat

    private weak var sidebarController: PDFSidebarViewController!
    private weak var sidebarControllerLeft: NSLayoutConstraint!
    private weak var documentController: PDFDocumentViewController!
    private weak var documentControllerLeft: NSLayoutConstraint!
    private weak var annotationToolbarController: AnnotationToolbarViewController!
    private var documentTop: NSLayoutConstraint!
    private weak var toolbarTop: NSLayoutConstraint!
    private var toolbarLeading: NSLayoutConstraint!
    private var toolbarLeadingSafeArea: NSLayoutConstraint!
    private var toolbarTrailing: NSLayoutConstraint!
    private weak var toolbarPreviewsOverlay: UIView!
    private weak var toolbarLeadingPreview: DashedView!
    private weak var toolbarLeadingPreviewTop: NSLayoutConstraint!
    private weak var toolbarLeadingPreviewHeight: NSLayoutConstraint!
    private weak var toolbarTrailingPreview: DashedView!
    private weak var toolbarTrailingPreviewTop: NSLayoutConstraint!
    private weak var toolbarTrailingPreviewHeight: NSLayoutConstraint!
    private weak var toolbarTopPreview: DashedView!
    private weak var toolbarPinnedPreview: DashedView!
    private weak var toolbarPinnedPreviewHeight: NSLayoutConstraint!
    private(set) var isSidebarTransitioning: Bool
    private(set) var isCompactWidth: Bool
    @CodableUserDefault(key: "PDFReaderToolbarState", defaultValue: ToolbarState(position: .leading, visible: true), encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    private var toolbarState: ToolbarState
    private var toolbarInitialFrame: CGRect?
    @UserDefault(key: "PDFReaderStatusBarVisible", defaultValue: true)
    private var statusBarVisible: Bool {
        didSet {
            (self.navigationController as? NavigationViewController)?.statusBarVisible = self.statusBarVisible
        }
    }
    private var didAppear: Bool
    private(set) var isCurrentlyVisible: Bool
    private var previousTraitCollection: UITraitCollection?
    var isSidebarVisible: Bool { return self.sidebarControllerLeft?.constant == 0 }
    var key: String { return self.viewModel.state.key }
    private var navigationBarHeight: CGFloat {
        return self.navigationController?.navigationBar.frame.height ?? 0.0
    }

    weak var coordinatorDelegate: (PdfReaderCoordinatorDelegate & PdfAnnotationsCoordinatorDelegate)?

    private lazy var shareButton: UIBarButtonItem = {
        let share = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)
        share.isEnabled = !self.viewModel.state.document.isLocked
        share.accessibilityLabel = L10n.Accessibility.Pdf.export
        share.title = L10n.Accessibility.Pdf.export
        share.tag = NavigationBarButton.share.rawValue
        share.rx.tap
             .subscribe(onNext: { [weak self, weak share] _ in
                 guard let `self` = self, let share = share else { return }
                 self.coordinatorDelegate?.showPdfExportSettings(sender: share, userInterfaceStyle: self.viewModel.state.interfaceStyle) { [weak self] settings in
                     self?.viewModel.process(action: .export(settings))
                 }
             })
             .disposed(by: self.disposeBag)
        return share
    }()
    private lazy var settingsButton: UIBarButtonItem = {
        let settings = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: nil, action: nil)
        settings.isEnabled = !self.viewModel.state.document.isLocked
        settings.accessibilityLabel = L10n.Accessibility.Pdf.settings
        settings.title = L10n.Accessibility.Pdf.settings
        settings.rx.tap
                .subscribe(onNext: { [weak self] _ in
                    self?.showSettings(sender: settings)
                })
                .disposed(by: self.disposeBag)
        return settings
    }()
    private lazy var searchButton: UIBarButtonItem = {
        let search = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: nil, action: nil)
        search.isEnabled = !self.viewModel.state.document.isLocked
        search.accessibilityLabel = L10n.Accessibility.Pdf.searchPdf
        search.title = L10n.Accessibility.Pdf.searchPdf
        search.rx.tap
              .subscribe(onNext: { [weak self] _ in
                  guard let `self` = self, let controller = self.documentController.pdfController else { return }
                  self.showSearch(pdfController: controller, text: nil)
              })
              .disposed(by: self.disposeBag)
        return search
    }()
    private var undoBarButton: UIBarButtonItem?
    private var redoBarButton: UIBarButtonItem?
    private lazy var toolbarButton: UIBarButtonItem = {
        let checkbox = CheckboxButton(type: .custom)
        checkbox.setImage(UIImage(systemName: "pencil.and.outline", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        checkbox.adjustsImageWhenHighlighted = false
        checkbox.scalesLargeContentImage = true
        checkbox.layer.cornerRadius = 4
        checkbox.layer.masksToBounds = true
        checkbox.deselectedTintColor = self.viewModel.state.document.isLocked ? .gray : Asset.Colors.zoteroBlueWithDarkMode.color
        checkbox.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        checkbox.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        checkbox.selectedTintColor = .white
        checkbox.isSelected = !self.viewModel.state.document.isLocked && self.toolbarState.visible
        checkbox.rx.controlEvent(.touchUpInside)
                .subscribe(onNext: { [weak self, weak checkbox] _ in
                    guard let `self` = self, let checkbox = checkbox else { return }
                    checkbox.isSelected = !checkbox.isSelected

                    self.toolbarState = ToolbarState(position: self.toolbarState.position, visible: checkbox.isSelected)

                    if checkbox.isSelected {
                        self.showAnnotationToolbar(state: self.toolbarState, statusBarVisible: self.statusBarVisible, animated: true)
                    } else {
                        self.hideAnnotationToolbar(fromPosition: self.toolbarState.position, statusBarVisible: self.statusBarVisible, animated: true)
                    }
                })
                .disposed(by: self.disposeBag)
        let barButton = UIBarButtonItem(customView: checkbox)
        barButton.isEnabled = !self.viewModel.state.document.isLocked
        barButton.accessibilityLabel = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.title = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.largeContentSizeImage = UIImage(systemName: "pencil.and.outline", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        return barButton
    }()

    init(viewModel: ViewModel<PDFReaderActionHandler>, compactSize: Bool) {
        self.viewModel = viewModel
        self.isSidebarTransitioning = false
        self.isCompactWidth = compactSize
        self.isCurrentlyVisible = false
        self.disposeBag = DisposeBag()
        self.didAppear = false
        self.statusBarHeight = UIApplication.shared.windows.first(where: \.isKeyWindow)?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0.0
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.set(userActivity: .pdfActivity(for: self.viewModel.state.key, libraryId: self.viewModel.state.library.identifier))

        self.view.backgroundColor = .systemGray6
        self.setupViews()
        self.setupNavigationBar()
        self.setupGestureRecognizer()
        self.setupObserving()

        self.updateInterface(to: self.viewModel.state.settings)

        if !self.viewModel.state.document.isLocked {
            self.viewModel.process(action: .loadDocumentData(boundingBoxConverter: self.documentController))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !self.didAppear {
            if self.toolbarState.visible && !self.viewModel.state.document.isLocked {
                self.showAnnotationToolbar(state: self.toolbarState, statusBarVisible: self.statusBarVisible, animated: false)
            } else {
                self.hideAnnotationToolbar(fromPosition: self.toolbarState.position, statusBarVisible: self.statusBarVisible, animated: false)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.isCurrentlyVisible = true
        self.didAppear = true
    }

    deinit {
        DDLogInfo("PDFReaderViewController deinitialized")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if !self.didAppear {
            let state = self.toolbarState
            self.setConstraints(for: state.position, statusBarVisible: self.statusBarVisible)
            self.setDocumentTopConstraint(forToolbarState: state, statusBarVisible: self.statusBarVisible)
        }

        if self.documentController.view.frame.width < PDFReaderViewController.minToolbarWidth && self.toolbarState.visible && self.toolbarState.position == .top {
            self.closeAnnotationToolbar()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.updateUserInterfaceStyleIfNeeded(previousTraitCollection: previousTraitCollection)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let isCompactWidth = UIDevice.current.isCompactWidth(size: size)
        let sizeDidChange = isCompactWidth != self.isCompactWidth
        self.isCompactWidth = isCompactWidth

        guard self.viewIfLoaded != nil else { return }

        if self.isSidebarVisible && sizeDidChange {
            self.documentControllerLeft.constant = isCompactWidth ? 0 : PDFReaderLayout.sidebarWidth
        }

        coordinator.animate(alongsideTransition: { _ in
            if sizeDidChange {
                self.annotationToolbarController.prepareForSizeChange()
                self.annotationToolbarController.updateAdditionalButtons()
                self.setConstraints(for: self.toolbarState.position, statusBarVisible: self.statusBarVisible)
                self.setDocumentTopConstraint(forToolbarState: self.toolbarState, statusBarVisible: self.statusBarVisible)
                self.view.layoutIfNeeded()
                self.annotationToolbarController.sizeDidChange()
            }
        }, completion: nil)
    }

    override var prefersStatusBarHidden: Bool {
        return !self.statusBarVisible
    }

    // MARK: - Actions

    private func update(state: PDFReaderState) {
        if let success = state.unlockSuccessful, success {
            // Enable bar buttons
            for item in self.navigationItem.leftBarButtonItems ?? [] {
                item.isEnabled = true
            }
            for item in self.navigationItem.rightBarButtonItems ?? [] {
                item.isEnabled = true
                guard let checkbox = item.customView as? CheckboxButton else { continue }
                checkbox.deselectedTintColor = Asset.Colors.zoteroBlueWithDarkMode.color
            }
            // Load initial document data after document has been unlocked successfully
            self.viewModel.process(action: .loadDocumentData(boundingBoxConverter: self.documentController))
        }

        if state.changes.contains(.annotations) {
            // Hide popover if annotation has been deleted
            if let controller = (self.presentedViewController as? UINavigationController)?.viewControllers.first as? AnnotationPopover, let key = controller.annotationKey, !state.sortedKeys.contains(key) {
                self.dismiss(animated: true, completion: nil)
            }
        }

        if state.changes.contains(.interfaceStyle) {
            self.updateInterface(to: state.settings)
        }

        if state.changes.contains(.export) {
            self.update(state: state.exportState)
        }

        if state.changes.contains(.initialDataLoaded) {
            if state.selectedAnnotation != nil {
                self.toggleSidebar(animated: false)
            }
        }

        if let tool = state.changedColorForTool, self.activeAnnotationTool == tool, let color = state.toolColors[tool] {
            self.annotationToolbarController.set(activeColor: color)
        }

        if let error = state.error {
            self.coordinatorDelegate?.show(error: error)
        }
    }

    private func update(state: PDFExportState?) {
        var items = self.navigationItem.rightBarButtonItems ?? []

        guard let shareId = items.firstIndex(where: { $0.tag == NavigationBarButton.share.rawValue }) else { return }

        guard let state = state else {
            if items[shareId].customView != nil { // if activity indicator is visible, replace it with share button
                items[shareId] = self.shareButton
                self.navigationItem.rightBarButtonItems = items
            }
            return
        }

        switch state {
        case .preparing:
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            let button = UIBarButtonItem(customView: indicator)
            button.tag = NavigationBarButton.share.rawValue
            items[shareId] = button

        case .exported(let file):
            DDLogInfo("PDFReaderViewController: share pdf file - \(file.createUrl().absoluteString)")
            items[shareId] = self.shareButton
            self.coordinatorDelegate?.share(url: file.createUrl(), barButton: self.shareButton)

        case .failed(let error):
            DDLogError("PDFReaderViewController: could not export pdf - \(error)")
            self.coordinatorDelegate?.show(error: error)
            items[shareId] = self.shareButton
        }

        self.navigationItem.rightBarButtonItems = items
    }

    private func updateInterface(to settings: PDFSettings) {
        switch settings.appearanceMode {
        case .automatic:
            self.navigationController?.overrideUserInterfaceStyle = .unspecified
        case .light:
            self.navigationController?.overrideUserInterfaceStyle = .light
        case .dark:
            self.navigationController?.overrideUserInterfaceStyle = .dark
        }
    }

    func showToolOptions() {
        if !self.annotationToolbarController.view.isHidden, !self.annotationToolbarController.colorPickerButton.isHidden {
            self.showToolOptions(sender: .view(self.annotationToolbarController.colorPickerButton, nil))
            return
        }

        guard let item = self.navigationItem.rightBarButtonItems?.last else { return }
        self.showToolOptions(sender: .item(item))
    }

    func showToolOptions(sender: SourceView) {
        guard let tool = self.activeAnnotationTool else { return }

        let colorHex = self.viewModel.state.toolColors[tool]?.hexString
        let size: Float?
        switch tool {
        case .ink:
            size = Float(self.viewModel.state.activeLineWidth)
        case .eraser:
            size = Float(self.viewModel.state.activeEraserSize)
        default:
            size = nil
        }

        self.coordinatorDelegate?.showToolSettings(tool: tool, colorHex: colorHex, sizeValue: size, sender: sender, userInterfaceStyle: self.viewModel.state.interfaceStyle) { [weak self] newColor, newSize in
            self?.viewModel.process(action: .setToolOptions(color: newColor, size: newSize.flatMap(CGFloat.init), tool: tool))
        }
    }

    private func hideSidebarIfNeeded(forPosition position: ToolbarState.Position, animated: Bool) {
        guard self.isSidebarVisible &&
              (position == .pinned || (position == .top && self.annotationToolbarController.view.frame.width < PDFReaderViewController.minToolbarWidth)) else { return }
        self.toggleSidebar(animated: animated)
    }

    private func toggleSidebar(animated: Bool) {
        let shouldShow = !self.isSidebarVisible

        if self.toolbarState.position == .leading {
            if shouldShow {
                self.toolbarLeadingSafeArea.isActive = false
                self.toolbarLeading.isActive = true
            } else {
                self.toolbarLeading.isActive = false
                self.toolbarLeadingSafeArea.isActive = true
            }
        }
        // If the layout is compact, show annotation sidebar above pdf document.
        if !self.isCompactWidth {
            self.documentControllerLeft.constant = shouldShow ? PDFReaderLayout.sidebarWidth : 0
        } else if shouldShow && self.toolbarState.visible {
            self.closeAnnotationToolbar()
        }
        self.sidebarControllerLeft.constant = shouldShow ? 0 : -PDFReaderLayout.sidebarWidth

        if let button = self.navigationItem.leftBarButtonItems?.first(where: { $0.tag == PDFReaderViewController.sidebarButtonTag }) {
            self.setupAccessibility(forSidebarButton: button)
        }

        if !animated {
            self.sidebarController.view.isHidden = !shouldShow
            self.annotationToolbarController.prepareForSizeChange()
            self.view.layoutIfNeeded()
            self.annotationToolbarController.sizeDidChange()

            if !shouldShow {
                self.view.endEditing(true)
            }
            return
        }

        if shouldShow {
            self.sidebarController.view.isHidden = false
        } else {
            self.view.endEditing(true)
        }

        self.isSidebarTransitioning = true

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 5, options: [.curveEaseOut],
                       animations: {
                           self.annotationToolbarController.prepareForSizeChange()
                           self.view.layoutIfNeeded()
                           self.annotationToolbarController.sizeDidChange()
                       },
                       completion: { finished in
                           guard finished else { return }
                           if !shouldShow {
                               self.sidebarController.view.isHidden = true
                           }
                           self.isSidebarTransitioning = false
                       })
    }

    private func updateUserInterfaceStyleIfNeeded(previousTraitCollection: UITraitCollection?) {
        guard self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) && self.viewModel.state.settings.appearanceMode == .automatic else { return }
        self.viewModel.process(action: .userInterfaceStyleChanged(self.traitCollection.userInterfaceStyle))
    }

    func showSearch(pdfController: PDFViewController, text: String?) {
        self.coordinatorDelegate?.showSearch(pdfController: pdfController, text: text, sender: self.searchButton, userInterfaceStyle: self.viewModel.state.interfaceStyle, result: { [weak self] result in
            self?.documentController.highlight(result: result)
        })
    }

    private func showSettings(sender: UIBarButtonItem) {
        self.coordinatorDelegate?.showSettings(with: self.viewModel.state.settings, sender: sender, userInterfaceStyle: self.viewModel.state.interfaceStyle, completion: { [weak self] settings in
            guard let `self` = self, let interfaceStyle = self.presentingViewController?.traitCollection.userInterfaceStyle else { return }
            self.viewModel.process(action: .setSettings(settings: settings, currentUserInterfaceStyle: interfaceStyle))
        })
    }

    private func close() {
        if let page = self.documentController?.pdfController?.pageIndex {
            self.viewModel.process(action: .submitPendingPage(Int(page)))
        }
        self.viewModel.process(action: .changeIdleTimerDisabled(false))
        self.viewModel.process(action: .clearTmpAnnotationPreviews)
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Annotation Bar

    /// Return new position for given touch point and velocity of toolbar. The user can pan up/left/right to move the toolbar. If velocity > 1500, it's considered a swipe and the toolbar
    /// is moved in swipe direction. Otherwise the toolbar is pinned to closest point from touch.
    private func position(fromTouch point: CGPoint, frame: CGRect, containerFrame: CGRect, velocity: CGPoint, statusBarVisible: Bool) -> ToolbarState.Position {
        if velocity.y > -1500 && abs(velocity.x) < 1500 {
            let topViewBottomRightPoint = self.toolbarTopPreview.convert(CGPoint(x: self.toolbarTopPreview.bounds.maxX, y: self.toolbarTopPreview.bounds.maxY), to: self.view)

            if point.y < topViewBottomRightPoint.y {
                let pinnedViewBottomRightPoint = self.toolbarPinnedPreview.convert(CGPoint(x: self.toolbarPinnedPreview.frame.maxX, y: self.toolbarPinnedPreview.frame.maxY), to: self.view)
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

        // Move in direction of swipe

        if abs(velocity.y) > abs(velocity.x) && containerFrame.size.width >= PDFReaderViewController.minToolbarWidth {
            return .top
        }

        return velocity.x < 0 ? .leading : .trailing
    }

    private func velocity(from panVelocity: CGPoint, newPosition: ToolbarState.Position) -> CGFloat {
        let currentPosition: CGFloat
        let endPosition: CGFloat
        let velocity: CGFloat

        switch newPosition {
        case .top:
            velocity = panVelocity.y
            currentPosition = self.annotationToolbarController.view.frame.minY
            endPosition = self.view.safeAreaInsets.top

        case .leading:
            velocity = panVelocity.x
            currentPosition = self.annotationToolbarController.view.frame.minX
            endPosition = 0

        case .trailing:
            velocity = panVelocity.x
            currentPosition = self.annotationToolbarController.view.frame.maxX
            endPosition = self.view.frame.width

        case .pinned:
            velocity = panVelocity.y
            currentPosition = self.annotationToolbarController.view.frame.minY
            endPosition = self.view.safeAreaInsets.top
        }

        return abs(velocity / (endPosition - currentPosition))
    }

    private func toolbarDidPan(recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.toolbarInitialFrame = self.annotationToolbarController.view.frame

        case .changed:
            guard let originalFrame = self.toolbarInitialFrame else { return }
            let translation = recognizer.translation(in: self.annotationToolbarController.view)
            let location = recognizer.location(in: self.view)
            self.annotationToolbarController.view.frame = originalFrame.offsetBy(dx: translation.x, dy: translation.y)

            let position = self.position(fromTouch: location, frame: self.annotationToolbarController.view.frame, containerFrame: self.documentController.view.frame,
                                         velocity: CGPoint(), statusBarVisible: self.statusBarVisible)

            if self.toolbarPreviewsOverlay.isHidden && position != self.toolbarState.position {
                let size = min(self.documentController.view.frame.size.height, AnnotationToolbarViewController.fullVerticalHeight)
                self.updatePositionOverlayViews(for: size, containerSize: self.documentController.view.frame.size)
                self.toolbarPreviewsOverlay.isHidden = false

                UIView.animate(withDuration: 0.2, animations: {
                    self.navigationController?.navigationBar.alpha = 0
                }, completion: { finished in
                    guard finished else { return }
                    self.navigationController?.setNavigationBarHidden(true, animated: false)
                })
            }

            if !self.toolbarPreviewsOverlay.isHidden {
                self.setHighlightSelected(at: position)
            }

        case .ended, .failed:
            self.toolbarPreviewsOverlay.isHidden = true
            let velocity = recognizer.velocity(in: self.view)
            let location = recognizer.location(in: self.view)
            let position = self.position(fromTouch: location, frame: self.annotationToolbarController.view.frame, containerFrame: self.documentController.view.frame,
                                         velocity: velocity, statusBarVisible: self.statusBarVisible)
            let newState = ToolbarState(position: position, visible: true)

            if position == .top {
                self.statusBarVisible = true
            }
            self.set(toolbarPosition: position, oldPosition: self.toolbarState.position, velocity: velocity, statusBarVisible: self.statusBarVisible)
            self.toolbarState = newState
            self.toolbarInitialFrame = nil

        case .cancelled, .possible: break
        @unknown default: break
        }
    }

    private func updatePositionOverlayViews(for verticalHeight: CGFloat, containerSize: CGSize) {
        let topToolbarsAvailable = containerSize.width >= PDFReaderViewController.minToolbarWidth

        self.toolbarPinnedPreview.isHidden = !topToolbarsAvailable
        if !self.toolbarPinnedPreview.isHidden {
            self.toolbarPinnedPreviewHeight.constant = AnnotationToolbarViewController.size + self.topOffsets(statusBarVisible: self.statusBarVisible).statusBarHeight
        }
        self.toolbarTopPreview.isHidden = !topToolbarsAvailable
        self.toolbarLeadingPreviewHeight.constant = verticalHeight
        self.toolbarTrailingPreviewHeight.constant = verticalHeight

        var topInset: CGFloat
        if !self.toolbarPinnedPreview.isHidden && !self.toolbarTopPreview.isHidden {
            // Toolbars are visible, start from bottom point of `top` toolbar
            topInset = 0
        } else {
            // Toolbars are not visible, check whether both are hidden or just `top` is hidden and move accordingly
            topInset = -(AnnotationToolbarViewController.size + PDFReaderViewController.toolbarCompactInset)
            if self.toolbarPinnedPreview.isHidden {
                topInset -= AnnotationToolbarViewController.size
            }
        }
        topInset += PDFReaderViewController.toolbarCompactInset
        self.toolbarLeadingPreviewTop.constant = topInset
        self.toolbarTrailingPreviewTop.constant = topInset

        self.toolbarPreviewsOverlay.layoutIfNeeded()
    }

    private func set(toolbarPosition newPosition: ToolbarState.Position, oldPosition: ToolbarState.Position, velocity velocityPoint: CGPoint, statusBarVisible: Bool) {
        let navigationBarHidden = newPosition == .pinned || !statusBarVisible

        switch (newPosition, oldPosition) {
        case (.leading, .leading), (.trailing, .trailing), (.top, .top), (.pinned, .pinned):
            // Position didn't change, move to initial frame
            let frame = self.toolbarInitialFrame ?? CGRect()
            let velocity = self.velocity(from: velocityPoint, newPosition: newPosition)

            if !navigationBarHidden && self.navigationController?.navigationBar.isHidden == true {
                self.navigationController?.setNavigationBarHidden(false, animated: false)
                self.navigationController?.navigationBar.alpha = 0
            }

            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [.curveEaseOut], animations: {
                self.annotationToolbarController.view.frame = frame
                self.navigationController?.navigationBar.alpha = navigationBarHidden ? 0 : 1
                self.documentController.setInterface(hidden: !statusBarVisible)
            }, completion: { finished in
                guard finished && navigationBarHidden else { return }
                self.navigationController?.setNavigationBarHidden(true, animated: false)
            })

        case (.leading, .trailing), (.trailing, .leading), (.top, .pinned), (.pinned, .top):
            // Move from side to side or vertically
            let velocity = self.velocity(from: velocityPoint, newPosition: newPosition)
            self.setConstraints(for: newPosition, statusBarVisible: statusBarVisible)
            self.setDocumentTopConstraint(forToolbarState: ToolbarState(position: newPosition, visible: true), statusBarVisible: statusBarVisible)
            self.view.setNeedsLayout()

            self.hideSidebarIfNeeded(forPosition: newPosition, animated: true)

            if !navigationBarHidden && self.navigationController?.navigationBar.isHidden == true {
                self.navigationController?.setNavigationBarHidden(false, animated: false)
                self.navigationController?.navigationBar.alpha = 0
            }

            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: {
                self.view.layoutIfNeeded()
                self.navigationController?.navigationBar.alpha = navigationBarHidden ? 0 : 1
                self.documentController.setInterface(hidden: !statusBarVisible)
                self.navigationController?.setNeedsStatusBarAppearanceUpdate()
                self.setNeedsStatusBarAppearanceUpdate()
            }, completion: { finished in
                guard finished && navigationBarHidden else { return }
                self.navigationController?.setNavigationBarHidden(true, animated: false)
            })

        case (.top, .leading), (.top, .trailing), (.leading, .top), (.leading, .pinned), (.trailing, .top), (.trailing, .pinned), (.pinned, .leading), (.pinned, .trailing):
            let velocity = self.velocity(from: velocityPoint, newPosition: newPosition)
            UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: {
                let newFrame = self.annotationToolbarController.view.frame.offsetBy(dx: velocityPoint.x / 10, dy: velocityPoint.y / 10)
                self.annotationToolbarController.view.frame = newFrame
                self.annotationToolbarController.view.alpha = 0
            }, completion: { finished in
                guard finished else { return }

                if !navigationBarHidden && self.navigationController?.navigationBar.isHidden == true {
                    self.navigationController?.setNavigationBarHidden(false, animated: false)
                    self.navigationController?.navigationBar.alpha = 0
                }

                self.annotationToolbarController.prepareForSizeChange()
                self.setConstraints(for: newPosition, statusBarVisible: statusBarVisible)
                self.view.layoutIfNeeded()
                self.annotationToolbarController.sizeDidChange()
                self.view.layoutIfNeeded()
                self.setDocumentTopConstraint(forToolbarState: ToolbarState(position: newPosition, visible: true), statusBarVisible: statusBarVisible)

                self.hideSidebarIfNeeded(forPosition: newPosition, animated: true)

                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: {
                    self.annotationToolbarController.view.alpha = 1
                    self.view.layoutIfNeeded()
                    self.navigationController?.navigationBar.alpha = navigationBarHidden ? 0 : 1
                    self.documentController.setInterface(hidden: !statusBarVisible)
                    self.navigationController?.setNeedsStatusBarAppearanceUpdate()
                    self.setNeedsStatusBarAppearanceUpdate()
                }, completion: { finished in
                    guard finished && navigationBarHidden else { return }
                    self.navigationController?.setNavigationBarHidden(true, animated: false)
                })
            })
        }
    }

    private func setConstraints(for position: ToolbarState.Position, statusBarVisible: Bool) {
        let rotation: AnnotationToolbarViewController.Rotation = (position == .top || position == .pinned) ? .horizontal : .vertical
        if self.isCompactSize(for: rotation) {
            self.setCompactConstraints(for: position, statusBarVisible: statusBarVisible)
        } else {
            self.setFullConstraints(for: position, statusBarVisible: statusBarVisible)
        }
    }

    func topOffsets(statusBarVisible: Bool) -> (statusBarHeight: CGFloat, navigationBarHeight: CGFloat, total: CGFloat) {
        let statusBarOffset = statusBarVisible || UIDevice.current.userInterfaceIdiom != .pad ? self.statusBarHeight : 0
        let navigationBarOffset = statusBarVisible ? self.navigationBarHeight : 0
        return (statusBarOffset, navigationBarOffset, statusBarOffset + navigationBarOffset)
    }

    private func setDocumentTopConstraint(forToolbarState state: ToolbarState, statusBarVisible: Bool) {
        let (statusBarOffset, _, totalOffset) = self.topOffsets(statusBarVisible: statusBarVisible)

        if !state.visible {
            self.documentTop.constant = totalOffset
            return
        }

        switch state.position {
        case .pinned:
            self.documentTop.constant = statusBarOffset + AnnotationToolbarViewController.size
        case .top:
            self.documentTop.constant = totalOffset + AnnotationToolbarViewController.size
        case .trailing, .leading:
            self.documentTop.constant = totalOffset
        }
    }

    private func setFullConstraints(for position: ToolbarState.Position, statusBarVisible: Bool) {
        switch position {
        case .leading:
            self.toolbarTrailing.isActive = false
            if self.isSidebarVisible {
                self.toolbarLeadingSafeArea.isActive = false
                self.toolbarLeading.isActive = true
                self.toolbarLeading.constant = PDFReaderViewController.toolbarFullInsetInset
            } else {
                self.toolbarLeading.isActive = false
                self.toolbarLeadingSafeArea.isActive = true
                self.toolbarLeadingSafeArea.constant = PDFReaderViewController.toolbarFullInsetInset
            }
            self.toolbarTop.constant = PDFReaderViewController.toolbarFullInsetInset + self.topOffsets(statusBarVisible: statusBarVisible).total
            self.annotationToolbarController.set(rotation: .vertical, isCompactSize: false)

        case .trailing:
            self.toolbarLeading.isActive = false
            self.toolbarLeadingSafeArea.isActive = false
            self.toolbarTrailing.isActive = true
            self.toolbarTrailing.constant = PDFReaderViewController.toolbarFullInsetInset
            self.toolbarTop.constant = PDFReaderViewController.toolbarFullInsetInset + self.topOffsets(statusBarVisible: statusBarVisible).total
            self.annotationToolbarController.set(rotation: .vertical, isCompactSize: false)

        case .top:
            self.setupTopConstraints(isCompact: false, isPinned: false, statusBarVisible: statusBarVisible)

        case .pinned:
            self.setupTopConstraints(isCompact: false, isPinned: true, statusBarVisible: statusBarVisible)
        }
    }

    private func setCompactConstraints(for position: ToolbarState.Position, statusBarVisible: Bool) {
        switch position {
        case .leading:
            self.toolbarTrailing.isActive = false
            if self.isSidebarVisible {
                self.toolbarLeadingSafeArea.isActive = false
                self.toolbarLeading.isActive = true
                self.toolbarLeading.constant = PDFReaderViewController.toolbarCompactInset
            } else {
                self.toolbarLeading.isActive = false
                self.toolbarLeadingSafeArea.isActive = true
                self.toolbarLeadingSafeArea.constant = PDFReaderViewController.toolbarCompactInset
            }
            self.toolbarTop.constant = PDFReaderViewController.toolbarCompactInset + self.topOffsets(statusBarVisible: statusBarVisible).total
            self.annotationToolbarController.set(rotation: .vertical, isCompactSize: true)

        case .trailing:
            self.toolbarLeading.isActive = false
            self.toolbarLeadingSafeArea.isActive = false
            self.toolbarTrailing.isActive = true
            self.toolbarTrailing.constant = PDFReaderViewController.toolbarCompactInset
            self.toolbarTop.constant = PDFReaderViewController.toolbarCompactInset + self.topOffsets(statusBarVisible: statusBarVisible).total
            self.annotationToolbarController.set(rotation: .vertical, isCompactSize: true)

        case .top:
            self.setupTopConstraints(isCompact: true, isPinned: false, statusBarVisible: statusBarVisible)

        case .pinned:
            self.setupTopConstraints(isCompact: true, isPinned: true, statusBarVisible: statusBarVisible)
        }
    }

    private func setupTopConstraints(isCompact: Bool, isPinned: Bool, statusBarVisible: Bool) {
        self.toolbarLeadingSafeArea.isActive = false
        self.toolbarTrailing.isActive = true
        self.toolbarTrailing.constant = 0
        self.toolbarLeading.isActive = true
        self.toolbarLeading.constant = 0
        self.toolbarTop.constant = isPinned ? self.topOffsets(statusBarVisible: statusBarVisible).statusBarHeight : self.topOffsets(statusBarVisible: statusBarVisible).total
        self.annotationToolbarController.set(rotation: .horizontal, isCompactSize: isCompact)
    }

    private func showAnnotationToolbar(state: ToolbarState, statusBarVisible: Bool, animated: Bool) {
        self.annotationToolbarController.prepareForSizeChange()
        self.setConstraints(for: state.position, statusBarVisible: statusBarVisible)
        self.annotationToolbarController.view.isHidden = false
        self.view.layoutIfNeeded()
        self.annotationToolbarController.sizeDidChange()
        self.view.layoutIfNeeded()
        self.setDocumentTopConstraint(forToolbarState: state, statusBarVisible: statusBarVisible)

        self.hideSidebarIfNeeded(forPosition: state.position, animated: animated)

        let navigationBarHidden = !statusBarVisible || state.position == .pinned

        if !animated {
            self.annotationToolbarController.view.alpha = 1
            self.navigationController?.setNavigationBarHidden(navigationBarHidden, animated: false)
            self.navigationController?.navigationBar.alpha = navigationBarHidden ? 0 : 1
            self.view.layoutIfNeeded()
            return
        }

        if !navigationBarHidden && self.navigationController?.navigationBar.isHidden == true {
            self.navigationController?.setNavigationBarHidden(false, animated: false)
            self.navigationController?.navigationBar.alpha = 0
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.annotationToolbarController.view.alpha = 1
            self.navigationController?.navigationBar.alpha = navigationBarHidden ? 0 : 1
            self.view.layoutIfNeeded()
        }, completion: { finished in
            guard finished && navigationBarHidden else { return }
            self.navigationController?.setNavigationBarHidden(true, animated: false)
        })
    }

    private func hideAnnotationToolbar(fromPosition position: ToolbarState.Position, statusBarVisible: Bool, animated: Bool) {
        let newState = ToolbarState(position: position, visible: false)

        self.setDocumentTopConstraint(forToolbarState: newState, statusBarVisible: statusBarVisible)

        if !animated {
            self.view.layoutIfNeeded()
            self.annotationToolbarController.view.alpha = 0
            self.annotationToolbarController.view.isHidden = true
            self.navigationController?.navigationBar.alpha = statusBarVisible ? 1 : 0
            self.navigationController?.setNavigationBarHidden(!statusBarVisible, animated: false)
            return
        }

        if statusBarVisible && self.navigationController?.navigationBar.isHidden == true {
            self.navigationController?.setNavigationBarHidden(false, animated: false)
            self.navigationController?.navigationBar.alpha = 0
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.view.layoutIfNeeded()
            self.annotationToolbarController.view.alpha = 0
            self.navigationController?.navigationBar.alpha = statusBarVisible ? 1 : 0
        }, completion: { finished in
            guard finished else { return }
            self.annotationToolbarController.view.isHidden = true
            self.toolbarState = newState
            self.documentController.disableAnnotationTools()
            if !statusBarVisible {
                self.navigationController?.setNavigationBarHidden(true, animated: false)
            }
        })
    }

    private func setHighlightSelected(at position: ToolbarState.Position) {
        switch position {
        case .top:
            self.toolbarLeadingPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarLeadingPreview.dashColor = UIColor.systemGray4
            self.toolbarTrailingPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTrailingPreview.dashColor = UIColor.systemGray4
            if self.toolbarTopPreview.isHidden {
                // Even if `top` position is set, when UI is hidden there is only one visible preview on top and it's `toolbarPinnedPreview`, so we need to highlight that one
                self.toolbarPinnedPreview.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
                self.toolbarPinnedPreview.dashColor = Asset.Colors.zoteroBlueWithDarkMode.color
            } else {
                self.toolbarTopPreview.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
                self.toolbarTopPreview.dashColor = Asset.Colors.zoteroBlueWithDarkMode.color
                self.toolbarPinnedPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
                self.toolbarPinnedPreview.dashColor = UIColor.systemGray4
            }

        case .leading:
            self.toolbarLeadingPreview.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
            self.toolbarLeadingPreview.dashColor = Asset.Colors.zoteroBlueWithDarkMode.color
            self.toolbarTrailingPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTrailingPreview.dashColor = UIColor.systemGray4
            self.toolbarTopPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTopPreview.dashColor = UIColor.systemGray4
            self.toolbarPinnedPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarPinnedPreview.dashColor = UIColor.systemGray4

        case .trailing:
            self.toolbarLeadingPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarLeadingPreview.dashColor = UIColor.systemGray4
            self.toolbarTrailingPreview.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
            self.toolbarTrailingPreview.dashColor = Asset.Colors.zoteroBlueWithDarkMode.color
            self.toolbarPinnedPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarPinnedPreview.dashColor = UIColor.systemGray4
            self.toolbarTopPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTopPreview.dashColor = UIColor.systemGray4

        case .pinned:
            self.toolbarLeadingPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarLeadingPreview.dashColor = UIColor.systemGray4
            self.toolbarTrailingPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTrailingPreview.dashColor = UIColor.systemGray4
            self.toolbarTopPreview.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTopPreview.dashColor = UIColor.systemGray4
            self.toolbarPinnedPreview.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
            self.toolbarPinnedPreview.dashColor = Asset.Colors.zoteroBlueWithDarkMode.color
        }
    }

    // MARK: - Setups

    private func setupGestureRecognizer() {
        let panRecognizer = UIPanGestureRecognizer()
        panRecognizer.rx.event
                     .subscribe(with: self, onNext: { `self`, recognizer in
                         self.toolbarDidPan(recognizer: recognizer)
                     })
                    .disposed(by: self.disposeBag)
        self.annotationToolbarController.view.addGestureRecognizer(panRecognizer)
    }

    private func add(controller: UIViewController) {
        controller.willMove(toParent: self)
        self.addChild(controller)
        controller.didMove(toParent: self)
    }

    private func setupViews() {
        let documentController = PDFDocumentViewController(viewModel: self.viewModel, compactSize: self.isCompactWidth, initialUIHidden: !self.statusBarVisible)
        documentController.parentDelegate = self
        documentController.coordinatorDelegate = self.coordinatorDelegate
        documentController.view.translatesAutoresizingMaskIntoConstraints = false

        let sidebarController = PDFSidebarViewController(viewModel: self.viewModel)
        sidebarController.parentDelegate = self
        sidebarController.coordinatorDelegate = self.coordinatorDelegate
        sidebarController.boundingBoxConverter = documentController
        sidebarController.view.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = Asset.Colors.annotationSidebarBorderColor.color

        let annotationToolbar = AnnotationToolbarViewController()
        annotationToolbar.delegate = self
        annotationToolbar.view.translatesAutoresizingMaskIntoConstraints = false
        annotationToolbar.view.setContentHuggingPriority(.required, for: .horizontal)
        annotationToolbar.view.setContentHuggingPriority(.required, for: .vertical)

        let previewsOverlay = UIView()
        previewsOverlay.translatesAutoresizingMaskIntoConstraints = false
        previewsOverlay.backgroundColor = .clear
        previewsOverlay.isHidden = true

        let topSafeAreaSpacer = UIView()
        topSafeAreaSpacer.translatesAutoresizingMaskIntoConstraints = false
        topSafeAreaSpacer.backgroundColor = Asset.Colors.navbarBackground.color
        self.view.addSubview(topSafeAreaSpacer)

        let topPreview = DashedView(dashColor: .systemGray4)
        self.setup(toolbarPositionView: topPreview)
        let pinnedPreview = DashedView(dashColor: .systemGray4)
        self.setup(toolbarPositionView: pinnedPreview)
        let leadingPreview = DashedView(dashColor: .systemGray4)
        leadingPreview.layer.cornerRadius = 8
        self.setup(toolbarPositionView: leadingPreview)
        let trailingPreview = DashedView(dashColor: .systemGray4)
        trailingPreview.layer.cornerRadius = 8
        self.setup(toolbarPositionView: trailingPreview)

        self.add(controller: documentController)
        self.add(controller: sidebarController)
        self.add(controller: annotationToolbar)
        self.view.addSubview(documentController.view)
        self.view.addSubview(sidebarController.view)
        self.view.addSubview(separator)
        self.view.addSubview(annotationToolbar.view)
        self.view.insertSubview(previewsOverlay, belowSubview: annotationToolbar.view)
        previewsOverlay.addSubview(pinnedPreview)
        previewsOverlay.addSubview(topPreview)
        previewsOverlay.addSubview(leadingPreview)
        previewsOverlay.addSubview(trailingPreview)

        let documentLeftConstraint = documentController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
        let sidebarLeftConstraint = sidebarController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: -PDFReaderLayout.sidebarWidth)
        self.documentTop = documentController.view.topAnchor.constraint(equalTo: self.view.topAnchor)
        self.toolbarLeading = annotationToolbar.view.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset)
        self.toolbarLeading.priority = .init(999)
        self.toolbarTrailing = self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: annotationToolbar.view.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset)
        let toolbarLeadingSafe = annotationToolbar.view.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor)
        let toolbarTop = annotationToolbar.view.topAnchor.constraint(equalTo: self.view.topAnchor, constant: PDFReaderViewController.toolbarCompactInset)
        let leadingPreviewHeight = leadingPreview.heightAnchor.constraint(equalToConstant: 50)
        let trailingPreviewHeight = trailingPreview.heightAnchor.constraint(equalToConstant: 50)
        let leadingPreviewTop = leadingPreview.topAnchor.constraint(equalTo: topPreview.bottomAnchor, constant: PDFReaderViewController.toolbarCompactInset)
        let trailingPreviewTop = trailingPreview.topAnchor.constraint(equalTo: topPreview.bottomAnchor, constant: PDFReaderViewController.toolbarCompactInset)
        let pinnedPreviewHeight = pinnedPreview.heightAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size)

        NSLayoutConstraint.activate([
            topSafeAreaSpacer.topAnchor.constraint(equalTo: self.view.topAnchor),
            topSafeAreaSpacer.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            topSafeAreaSpacer.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            topSafeAreaSpacer.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            sidebarController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            sidebarController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            sidebarController.view.widthAnchor.constraint(equalToConstant: PDFReaderLayout.sidebarWidth),
            sidebarLeftConstraint,
            separator.widthAnchor.constraint(equalToConstant: PDFReaderLayout.separatorWidth),
            separator.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor),
            separator.topAnchor.constraint(equalTo: self.view.topAnchor),
            separator.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            documentController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.documentTop,
            documentController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            documentLeftConstraint,
            toolbarTop,
            toolbarLeadingSafe,
            previewsOverlay.topAnchor.constraint(equalTo: self.view.topAnchor),
            previewsOverlay.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            previewsOverlay.leadingAnchor.constraint(equalTo: documentController.view.leadingAnchor),
            previewsOverlay.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
            previewsOverlay.trailingAnchor.constraint(equalTo: trailingPreview.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset),
            pinnedPreview.topAnchor.constraint(equalTo: previewsOverlay.topAnchor),
            pinnedPreview.leadingAnchor.constraint(equalTo: previewsOverlay.leadingAnchor),
            previewsOverlay.trailingAnchor.constraint(equalTo: pinnedPreview.trailingAnchor),
            pinnedPreviewHeight,
            topPreview.topAnchor.constraint(equalTo: pinnedPreview.bottomAnchor, constant: PDFReaderViewController.toolbarCompactInset),
            topPreview.leadingAnchor.constraint(equalTo: previewsOverlay.leadingAnchor),
            previewsOverlay.trailingAnchor.constraint(equalTo: topPreview.trailingAnchor),
            topPreview.heightAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size),
            leadingPreview.leadingAnchor.constraint(equalTo: previewsOverlay.leadingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset),
            leadingPreviewTop,
            leadingPreviewHeight,
            leadingPreview.widthAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size),
            previewsOverlay.trailingAnchor.constraint(equalTo: trailingPreview.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset),
            trailingPreviewTop,
            trailingPreviewHeight,
            trailingPreview.widthAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size)
        ])

        self.documentController = documentController
        self.documentControllerLeft = documentLeftConstraint
        self.sidebarController = sidebarController
        self.sidebarControllerLeft = sidebarLeftConstraint
        self.annotationToolbarController = annotationToolbar
        self.toolbarTop = toolbarTop
        self.toolbarLeadingSafeArea = toolbarLeadingSafe
        self.toolbarPreviewsOverlay = previewsOverlay
        self.toolbarTopPreview = topPreview
        self.toolbarPinnedPreview = pinnedPreview
        self.toolbarLeadingPreview = leadingPreview
        self.toolbarLeadingPreviewHeight = leadingPreviewHeight
        self.toolbarLeadingPreviewTop = leadingPreviewTop
        self.toolbarTrailingPreview = trailingPreview
        self.toolbarTrailingPreviewHeight = trailingPreviewHeight
        self.toolbarTrailingPreviewTop = trailingPreviewTop
        self.toolbarPinnedPreviewHeight = pinnedPreviewHeight
    }

    private func setup(toolbarPositionView view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
        view.layer.masksToBounds = true
    }

    private func setupAccessibility(forSidebarButton button: UIBarButtonItem) {
        button.accessibilityLabel = self.isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
        button.title = self.isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
    }

    private func setupNavigationBar() {
        let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"), style: .plain, target: nil, action: nil)
        sidebarButton.isEnabled = !self.viewModel.state.document.isLocked
        self.setupAccessibility(forSidebarButton: sidebarButton)
        sidebarButton.tag = PDFReaderViewController.sidebarButtonTag
        sidebarButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.toggleSidebar(animated: true) }).disposed(by: self.disposeBag)

        let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
        closeButton.title = L10n.close
        closeButton.accessibilityLabel = L10n.close
        closeButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.close() }).disposed(by: self.disposeBag)

        let readerButton = UIBarButtonItem(image: Asset.Images.pdfRawReader.image, style: .plain, target: nil, action: nil)
        readerButton.isEnabled = !self.viewModel.state.document.isLocked
        readerButton.accessibilityLabel = L10n.Accessibility.Pdf.openReader
        readerButton.title = L10n.Accessibility.Pdf.openReader
        readerButton.rx.tap
                       .subscribe(with: self, onNext: { `self`, _ in
                           self.coordinatorDelegate?.showReader(document: self.viewModel.state.document, userInterfaceStyle: self.viewModel.state.interfaceStyle)
                       })
                       .disposed(by: self.disposeBag)

        self.navigationItem.leftBarButtonItems = [closeButton, sidebarButton, readerButton]
        self.navigationItem.rightBarButtonItems = self.rightBarButtonItems
    }

    private var rightBarButtonItems: [UIBarButtonItem] {
        var buttons = [self.settingsButton, self.shareButton, self.searchButton]

        if self.viewModel.state.library.metadataEditable {
            buttons.append(self.toolbarButton)
        }

        return buttons
    }

    private func setupObserving() {
        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(UIApplication.didBecomeActiveNotification)
                                  .observe(on: MainScheduler.instance)
                                  .subscribe(with: self, onNext: { `self`, notification in
                                      self.isCurrentlyVisible = true
                                      if let previousTraitCollection = self.previousTraitCollection {
                                          self.updateUserInterfaceStyleIfNeeded(previousTraitCollection: previousTraitCollection)
                                      }
                                      self.viewModel.process(action: .updateAnnotationPreviews)
                                      self.documentController.didBecomeActive()
                                  })
                                  .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(UIApplication.willResignActiveNotification)
                                  .observe(on: MainScheduler.instance)
                                  .subscribe(with: self, onNext: { `self`, notification in
                                      self.isCurrentlyVisible = false
                                      self.previousTraitCollection = self.traitCollection
                                      if let page = self.documentController?.pdfController?.pageIndex {
                                          self.viewModel.process(action: .submitPendingPage(Int(page)))
                                      }
                                  })
                                  .disposed(by: self.disposeBag)
    }
}

extension PDFReaderViewController: PDFReaderContainerDelegate {}

extension PDFReaderViewController: SidebarDelegate {
    func tableOfContentsSelected(page: UInt) {
        self.documentController.focus(page: page)
        if UIDevice.current.userInterfaceIdiom == .phone {
            self.toggleSidebar(animated: true)
        }
    }
}

extension PDFReaderViewController: PDFDocumentDelegate {
    func annotationTool(didChangeStateFrom oldState: PSPDFKit.Annotation.Tool?, to newState: PSPDFKit.Annotation.Tool?,
                        variantFrom oldVariant: PSPDFKit.Annotation.Variant?, to newVariant: PSPDFKit.Annotation.Variant?) {
        if let state = oldState {
            self.annotationToolbarController.set(selected: false, to: state, color: nil)
        }

        if let state = newState {
            let color = self.viewModel.state.toolColors[state]
            self.annotationToolbarController.set(selected: true, to: state, color: color)
        }
    }

    func didChange(undoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        self.annotationToolbarController.didChange(undoState: undoEnabled, redoState: redoEnabled)
    }

    func interfaceVisibilityDidChange(to isHidden: Bool) {
        let state = self.toolbarState
        let shouldChangeNavigationBarVisibility = !state.visible || state.position != .pinned

        if !isHidden && shouldChangeNavigationBarVisibility && self.navigationController?.navigationBar.isHidden == true {
            self.navigationController?.setNavigationBarHidden(false, animated: false)
            self.navigationController?.navigationBar.alpha = 0
        }

        self.statusBarVisible = !isHidden
        self.setDocumentTopConstraint(forToolbarState: state, statusBarVisible: self.statusBarVisible)
        self.setConstraints(for: state.position, statusBarVisible: self.statusBarVisible)

        UIView.animate(withDuration: 0.15, animations: {
            self.navigationController?.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsStatusBarAppearanceUpdate()
            self.view.layoutIfNeeded()
            if shouldChangeNavigationBarVisibility {
                self.navigationController?.navigationBar.alpha = isHidden ? 0 : 1
            }
        }, completion: { finished in
            guard finished && shouldChangeNavigationBarVisibility else { return }
            self.navigationController?.setNavigationBarHidden(isHidden, animated: false)
        })

        if isHidden && self.isSidebarVisible {
            self.toggleSidebar(animated: true)
        }
    }
}

extension PDFReaderViewController: ConflictViewControllerReceiver {
    func shows(object: SyncObject, libraryId: LibraryIdentifier) -> String? {
        guard object == .item && libraryId == self.viewModel.state.library.identifier else { return nil }
        return self.viewModel.state.key
    }

    func canDeleteObject(completion: @escaping (Bool) -> Void) {
        self.coordinatorDelegate?.showDeletedAlertForPdf(completion: completion)
    }
}

extension PDFReaderViewController: AnnotationBoundingBoxConverter {
    func convertFromDb(rect: CGRect, page: PageIndex) -> CGRect? {
        return self.documentController.convertFromDb(rect: rect, page: page)
    }

    func convertFromDb(point: CGPoint, page: PageIndex) -> CGPoint? {
        return self.documentController.convertFromDb(point: point, page: page)
    }

    func convertToDb(rect: CGRect, page: PageIndex) -> CGRect? {
        return self.documentController.convertToDb(rect: rect, page: page)
    }

    func convertToDb(point: CGPoint, page: PageIndex) -> CGPoint? {
        return self.documentController.convertToDb(point: point, page: page)
    }

    func sortIndexMinY(rect: CGRect, page: PageIndex) -> CGFloat? {
        return self.documentController.sortIndexMinY(rect: rect, page: page)
    }

    func textOffset(rect: CGRect, page: PageIndex) -> Int? {
        return self.documentController.textOffset(rect: rect, page: page)
    }
}

extension PDFReaderViewController: AnnotationToolbarDelegate {
    var rotation: AnnotationToolbarViewController.Rotation {
        switch self.toolbarState.position {
        case .leading, .trailing: return .vertical
        case .top, .pinned: return .horizontal
        }
    }

    func closeAnnotationToolbar() {
        (self.toolbarButton.customView as? CheckboxButton)?.isSelected = false
        self.hideAnnotationToolbar(fromPosition: self.toolbarState.position, statusBarVisible: self.statusBarVisible, animated: true)
    }

    var activeAnnotationTool: PSPDFKit.Annotation.Tool? {
        return self.documentController.pdfController?.annotationStateManager.state
    }

    var maxAvailableToolbarSize: CGFloat {
        guard self.toolbarState.visible, let documentController = self.documentController else { return 0 }

        switch self.toolbarState.position {
        case .top, .pinned:
            return self.isCompactWidth ? documentController.view.frame.size.width : (documentController.view.frame.size.width - (2 * PDFReaderViewController.toolbarFullInsetInset))
        case .trailing, .leading:
            let window = UIApplication.shared.windows.first(where: \.isKeyWindow)
            let topInset = window?.safeAreaInsets.top ?? 0
            let bottomInset = window?.safeAreaInsets.bottom ?? 0
            let interfaceIsHidden = self.navigationController?.isNavigationBarHidden ?? false
            return self.view.frame.size.height - (2 * PDFReaderViewController.toolbarCompactInset) - (interfaceIsHidden ? 0 : (topInset + documentController.scrubberBarHeight)) - bottomInset
        }
    }

    func isCompactSize(for rotation: AnnotationToolbarViewController.Rotation) -> Bool {
        switch rotation {
        case .horizontal:
            return self.isCompactWidth
        case .vertical:
            return self.view.frame.height <= 400
        }
    }

    func toggle(tool: PSPDFKit.Annotation.Tool, options: AnnotationToolOptions) {
        let color = self.viewModel.state.toolColors[tool]
        self.documentController.toggle(annotationTool: tool, color: color, tappedWithStylus: (options == .stylus))
    }

    var canUndo: Bool {
        return self.viewModel.state.document.undoController.undoManager.canUndo
    }

    func performUndo() {
        self.viewModel.state.document.undoController.undoManager.undo()
    }

    var canRedo: Bool {
        return self.viewModel.state.document.undoController.undoManager.canRedo
    }

    func performRedo() {
        self.viewModel.state.document.undoController.undoManager.redo()
    }
}

#endif
