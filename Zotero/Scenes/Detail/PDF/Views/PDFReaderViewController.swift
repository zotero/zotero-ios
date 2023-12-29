//
//  PDFReaderViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 31.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RxSwift

protocol PDFReaderContainerDelegate: AnyObject {
    var isSidebarVisible: Bool { get }

    func showSearch(pdfController: PDFViewController, text: String?)
}

class PDFReaderViewController: UIViewController {
    private enum NavigationBarButton: Int {
        case share = 1
        case sidebar = 7
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

    private static let toolbarCompactInset: CGFloat = 12
    private static let toolbarFullInsetInset: CGFloat = 20
    private static let minToolbarWidth: CGFloat = 300
    private static let annotationToolbarDragHandleHeight: CGFloat = 50
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag
    private let previewBackgroundColor: UIColor
    private let previewDashColor: UIColor
    private let previewSelectedBackgroundColor: UIColor
    private let previewSelectedDashColor: UIColor

    private weak var sidebarController: PDFSidebarViewController!
    private weak var sidebarControllerLeft: NSLayoutConstraint!
    private weak var documentController: PDFDocumentViewController!
    private weak var documentControllerLeft: NSLayoutConstraint!
    private weak var annotationToolbarController: AnnotationToolbarViewController!
    private weak var annotationToolbarDragHandleLongPressRecognizer: UILongPressGestureRecognizer!
    private var documentTop: NSLayoutConstraint!
    private weak var toolbarTop: NSLayoutConstraint!
    private var toolbarLeading: NSLayoutConstraint!
    private var toolbarLeadingSafeArea: NSLayoutConstraint!
    private var toolbarTrailing: NSLayoutConstraint!
    private var toolbarTrailingSafeArea: NSLayoutConstraint!
    private weak var toolbarPreviewsOverlay: UIView!
    private weak var toolbarLeadingPreview: DashedView!
    private weak var inbetweenTopDashedView: DashedView!
    private weak var toolbarLeadingPreviewHeight: NSLayoutConstraint!
    private weak var toolbarTrailingPreview: DashedView!
    private weak var toolbarTrailingPreviewHeight: NSLayoutConstraint!
    private weak var toolbarTopPreview: DashedView!
    private weak var toolbarPinnedPreview: DashedView!
    private weak var toolbarPinnedPreviewHeight: NSLayoutConstraint!
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
    private var previousTraitCollection: UITraitCollection?
    var isSidebarVisible: Bool { return self.sidebarControllerLeft?.constant == 0 }
    var key: String { return self.viewModel.state.key }
    private var statusBarHeight: CGFloat
    private var navigationBarHeight: CGFloat {
        return self.navigationController?.navigationBar.frame.height ?? 0.0
    }

    weak var coordinatorDelegate: (PdfReaderCoordinatorDelegate & PdfAnnotationsCoordinatorDelegate)?

    private lazy var shareButton: UIBarButtonItem = {
        var menuChildren: [UIMenuElement] = []

        let share = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)
        share.accessibilityLabel = L10n.Accessibility.Pdf.share
        share.title = L10n.Accessibility.Pdf.share
        share.tag = NavigationBarButton.share.rawValue

        let deferredMenu = UIDeferredMenuElement.uncached { [weak self] elementProvider in
            var elements: [UIMenuElement] = []
            defer {
                elementProvider(elements)
            }
            guard let self else { return }

            if let parentKey = viewModel.state.parentKey {
                let copyCitationAction = UIAction(title: L10n.Citation.copyCitation, image: .init(systemName: "doc.on.doc")) { [weak self] _ in
                    guard let self, let coordinatorDelegate else { return }
                    coordinatorDelegate.showCitation(for: parentKey, libraryId: viewModel.state.library.identifier)
                }
                elements.append(copyCitationAction)
                let copyBibliographyAction = UIAction(title: L10n.Citation.copyBibliography, image: .init(systemName: "doc.on.doc")) { [weak self] _ in
                    guard let self, let coordinatorDelegate else { return }
                    coordinatorDelegate.copyBibliography(using: self, for: parentKey, libraryId: viewModel.state.library.identifier)
                }
                elements.append(copyBibliographyAction)
            }

            let exportAttributes: UIMenuElement.Attributes = viewModel.state.document.isLocked ? [.disabled] : []
            let exportOriginalPDFAction = UIAction(title: L10n.Pdf.Export.export, image: .init(systemName: "square.and.arrow.up"), attributes: exportAttributes) { [weak self] _ in
                self?.viewModel.process(action: .export(includeAnnotations: false))
            }
            exportOriginalPDFAction.accessibilityValue = L10n.Accessibility.Pdf.export
            elements.append(exportOriginalPDFAction)

            if !viewModel.state.databaseAnnotations.isEmpty {
                let exportAnnotatedPDFAction = UIAction(title: L10n.Pdf.Export.exportAnnotated, image: .init(systemName: "square.and.arrow.up"), attributes: exportAttributes) { [weak self] _ in
                    self?.viewModel.process(action: .export(includeAnnotations: true))
                }
                exportAnnotatedPDFAction.accessibilityValue = L10n.Accessibility.Pdf.exportAnnotated
                elements.append(exportAnnotatedPDFAction)
            }
        }
        share.menu = UIMenu(children: [deferredMenu])
        return share
    }()
    private lazy var settingsButton: UIBarButtonItem = {
        let settings = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: nil, action: nil)
        settings.isEnabled = !self.viewModel.state.document.isLocked
        settings.accessibilityLabel = L10n.Accessibility.Pdf.settings
        settings.title = L10n.Accessibility.Pdf.settings
        settings.rx.tap
                .subscribe(onNext: { [weak self, weak settings] _ in
                    guard let self, let settings else { return }
                    self.showSettings(sender: settings)
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
                  guard let self = self, let controller = self.documentController.pdfController else { return }
                  self.showSearch(pdfController: controller, text: nil)
              })
              .disposed(by: self.disposeBag)
        return search
    }()
    private lazy var toolbarButton: UIBarButtonItem = {
        var configuration = UIButton.Configuration.plain()
        let image = UIImage(systemName: "pencil.and.outline")?.applyingSymbolConfiguration(.init(scale: .large))
        let checkbox = CheckboxButton(image: image!, contentInsets: NSDirectionalEdgeInsets(top: 11, leading: 6, bottom: 9, trailing: 6))
        checkbox.scalesLargeContentImage = true
        checkbox.deselectedBackgroundColor = .clear
        checkbox.deselectedTintColor = self.viewModel.state.document.isLocked ? .gray : Asset.Colors.zoteroBlueWithDarkMode.color
        checkbox.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        checkbox.selectedTintColor = .white
        checkbox.isSelected = !self.viewModel.state.document.isLocked && self.toolbarState.visible
        checkbox.rx.controlEvent(.touchUpInside)
                .subscribe(onNext: { [weak self, weak checkbox] _ in
                    guard let self, let checkbox else { return }
                    checkbox.isSelected = !checkbox.isSelected

                    self.toolbarState = ToolbarState(position: self.toolbarState.position, visible: checkbox.isSelected)

                    if checkbox.isSelected {
                        self.showAnnotationToolbar(state: self.toolbarState, statusBarVisible: self.statusBarVisible, animated: true)
                    } else {
                        self.hideAnnotationToolbar(newState: self.toolbarState, statusBarVisible: self.statusBarVisible, animated: true)
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
        self.isCompactWidth = compactSize
        self.disposeBag = DisposeBag()
        self.didAppear = false
        self.previewDashColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
        self.previewBackgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.15)
        self.previewSelectedDashColor = Asset.Colors.zoteroBlueWithDarkMode.color
        self.previewSelectedBackgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
        self.statusBarHeight = UIApplication
            .shared
            .connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene })
            .first?
            .windows
            .first(where: { $0.isKeyWindow })?
            .windowScene?
            .statusBarManager?
            .statusBarFrame
            .height ?? 0
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.set(userActivity: .pdfActivity(for: self.viewModel.state.key, libraryId: self.viewModel.state.library.identifier, collectionId: Defaults.shared.selectedCollectionId))

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
            self.setAnnotationToolbarHandleMinimumLongPressDuration(forPosition: self.toolbarState.position)
            if self.toolbarState.visible && !self.viewModel.state.document.isLocked {
                self.showAnnotationToolbar(state: self.toolbarState, statusBarVisible: self.statusBarVisible, animated: false)
            } else {
                self.hideAnnotationToolbar(newState: self.toolbarState, statusBarVisible: self.statusBarVisible, animated: false)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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

        self.isCompactWidth = UIDevice.current.isCompactWidth(size: size)

        guard self.viewIfLoaded != nil else { return }

        if self.isSidebarVisible {
            self.documentControllerLeft.constant = self.isCompactWidth ? 0 : PDFReaderLayout.sidebarWidth
        }

        coordinator.animate(alongsideTransition: { _ in
            self.statusBarHeight = self.view.safeAreaInsets.top - (self.navigationController?.isNavigationBarHidden == true ? 0 : self.navigationBarHeight)
            self.annotationToolbarController.prepareForSizeChange()
            self.annotationToolbarController.updateAdditionalButtons()
            self.setConstraints(for: self.toolbarState.position, statusBarVisible: self.statusBarVisible)
            self.setDocumentTopConstraint(forToolbarState: self.toolbarState, statusBarVisible: self.statusBarVisible)
            self.view.layoutIfNeeded()
            self.annotationToolbarController.sizeDidChange()
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
            if let controller = (self.presentedViewController as? UINavigationController)?.viewControllers.first as? AnnotationPopover,
               let key = controller.annotationKey, !state.sortedKeys.contains(key) {
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

        self.coordinatorDelegate?.showToolSettings(
            tool: tool,
            colorHex: colorHex,
            sizeValue: size,
            sender: sender,
            userInterfaceStyle: self.viewModel.state.interfaceStyle
        ) { [weak self] newColor, newSize in
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

        if let button = self.navigationItem.leftBarButtonItems?.first(where: { $0.tag == NavigationBarButton.sidebar.rawValue }) {
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
                       })
    }

    private func updateUserInterfaceStyleIfNeeded(previousTraitCollection: UITraitCollection?) {
        guard self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) && self.viewModel.state.settings.appearanceMode == .automatic else { return }
        self.viewModel.process(action: .userInterfaceStyleChanged(self.traitCollection.userInterfaceStyle))
    }

    func showSearch(pdfController: PDFViewController, text: String?) {
        self.coordinatorDelegate?.showSearch(pdfController: pdfController, text: text, sender: self.searchButton, userInterfaceStyle: self.viewModel.state.interfaceStyle, delegate: self)
    }

    private func showSettings(sender: UIBarButtonItem) {
        self.coordinatorDelegate?.showSettings(with: self.viewModel.state.settings, sender: sender, userInterfaceStyle: self.viewModel.state.interfaceStyle, completion: { [weak self] settings in
            guard let self, let interfaceStyle = self.presentingViewController?.traitCollection.userInterfaceStyle else { return }
            self.viewModel.process(action: .setSettings(settings: settings, currentUserInterfaceStyle: interfaceStyle))
        })
    }

    private func close() {
        if let page = self.documentController?.pdfController?.pageIndex {
            self.viewModel.process(action: .submitPendingPage(Int(page)))
        }
        self.viewModel.process(action: .changeIdleTimerDisabled(false))
        self.viewModel.process(action: .clearTmpData)
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Annotation Bar

    private func isSwipe(fromVelocity velocity: CGPoint) -> Bool {
        return velocity.y <= -1500 || abs(velocity.x) >= 1500
    }

    /// Return new position for given touch point and velocity of toolbar. The user can pan up/left/right to move the toolbar. If velocity > 1500, it's considered a swipe and the toolbar is moved
    /// in swipe direction. Otherwise the toolbar is pinned to closest point from touch.
    private func position(fromTouch point: CGPoint, frame: CGRect, containerFrame: CGRect, velocity: CGPoint, statusBarVisible: Bool) -> ToolbarState.Position {
        if self.isSwipe(fromVelocity: velocity) {
            // Move in direction of swipe
            if abs(velocity.y) > abs(velocity.x) && containerFrame.size.width >= PDFReaderViewController.minToolbarWidth {
                return .top
            }
            return velocity.x < 0 ? .leading : .trailing
        }

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

    private func didTapToolbar(recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.setHighlightSelected(at: self.toolbarState.position)
            self.showPreviews()

        case .ended, .failed:
            self.hidePreviewsIfNeeded()

        default: break
        }
    }

    private func toolbarDidPan(recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.toolbarInitialFrame = self.annotationToolbarController.view.frame

        case .changed:
            guard let originalFrame = self.toolbarInitialFrame else { return }
            let translation = recognizer.translation(in: self.annotationToolbarController.view)
            let location = recognizer.location(in: self.view)
            let position = self.position(
                fromTouch: location,
                frame: self.annotationToolbarController.view.frame,
                containerFrame: self.documentController.view.frame,
                velocity: CGPoint(),
                statusBarVisible: self.statusBarVisible
            )

            self.annotationToolbarController.view.frame = originalFrame.offsetBy(dx: translation.x, dy: translation.y)

            self.showPreviewsOnDragIfNeeded(translation: translation, velocity: recognizer.velocity(in: self.view), currentPosition: self.toolbarState.position)

            if !self.toolbarPreviewsOverlay.isHidden {
                self.setHighlightSelected(at: position)
            }

        case .ended, .failed:
            let velocity = recognizer.velocity(in: self.view)
            let location = recognizer.location(in: self.view)
            let position = self.position(
                fromTouch: location,
                frame: self.annotationToolbarController.view.frame,
                containerFrame: self.documentController.view.frame,
                velocity: velocity,
                statusBarVisible: self.statusBarVisible
            )
            let newState = ToolbarState(position: position, visible: true)

            if position == .top && self.toolbarState.position == .pinned {
                self.statusBarVisible = true
            }
            self.set(toolbarPosition: position, oldPosition: self.toolbarState.position, velocity: velocity, statusBarVisible: self.statusBarVisible)
            self.setAnnotationToolbarHandleMinimumLongPressDuration(forPosition: position)
            self.toolbarState = newState
            self.toolbarInitialFrame = nil

        default: break
        }
    }

    private func showPreviewsOnDragIfNeeded(translation: CGPoint, velocity: CGPoint, currentPosition: ToolbarState.Position) {
        guard self.toolbarPreviewsOverlay.isHidden else { return }

        let distance = sqrt((translation.x * translation.x) + (translation.y * translation.y))
        let distanceThreshold: CGFloat = (currentPosition == .pinned || currentPosition == .top) ? 0 : 70

        guard distance > distanceThreshold && !self.isSwipe(fromVelocity: velocity) else { return }

        self.showPreviews()
    }

    private func showPreviews() {
        self.updatePositionOverlayViews(
            currentHeight: self.annotationToolbarController.view.frame.height,
            containerSize: self.documentController.view.frame.size,
            position: self.toolbarState.position,
            statusBarVisible: self.statusBarVisible
        )
        self.toolbarPreviewsOverlay.alpha = 0
        self.toolbarPreviewsOverlay.isHidden = false

        UIView.animate(withDuration: 0.2, animations: {
            self.toolbarPreviewsOverlay.alpha = 1
            self.navigationController?.navigationBar.alpha = 0
        })
    }

    private func hidePreviewsIfNeeded() {
        guard self.toolbarPreviewsOverlay.alpha == 1 else { return }

        UIView.animate(withDuration: 0.2, animations: {
            self.navigationController?.navigationBar.alpha = 1
            self.toolbarPreviewsOverlay.alpha = 0
        }, completion: { finished in
            guard finished else { return }
            self.toolbarPreviewsOverlay.isHidden = true
        })
    }

    private func updatePositionOverlayViews(currentHeight: CGFloat, containerSize: CGSize, position: ToolbarState.Position, statusBarVisible: Bool) {
        let topToolbarsAvailable = containerSize.width >= PDFReaderViewController.minToolbarWidth
        let verticalHeight: CGFloat
        switch position {
        case .leading, .trailing:
            // Position the preview so that the bottom of preview matches actual bottom of toolbar, add offset for dashed border
            let offset = self.annotationToolbarController.size + (statusBarVisible ? 0 : self.annotationToolbarController.size)
            verticalHeight = currentHeight - offset + (DashedView.dashWidth * 2) + 1

        case .top, .pinned:
            verticalHeight = min(containerSize.height - currentHeight - (position == .pinned ? self.navigationBarHeight : 0), AnnotationToolbarViewController.estimatedVerticalHeight)
        }

        self.toolbarPinnedPreview.isHidden = !topToolbarsAvailable || (position == .top && !statusBarVisible)
        self.inbetweenTopDashedView.isHidden = self.toolbarPinnedPreview.isHidden
        if !self.toolbarPinnedPreview.isHidden {
            // Change height based on current position so that preview is shown around currently visible toolbar
            let baseHeight = position == .pinned ? self.annotationToolbarController.size : self.navigationBarHeight
            self.toolbarPinnedPreviewHeight.constant = baseHeight + self.topOffsets(statusBarVisible: statusBarVisible).statusBarHeight - (position == .top ? 1 : 0)
        }
        self.toolbarTopPreview.isHidden = !topToolbarsAvailable
        self.toolbarLeadingPreviewHeight.constant = verticalHeight
        self.toolbarTrailingPreviewHeight.constant = verticalHeight
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
                self.toolbarPreviewsOverlay.alpha = 0
                self.annotationToolbarController.view.frame = frame
                self.navigationController?.navigationBar.alpha = navigationBarHidden ? 0 : 1
                self.documentController.setInterface(hidden: !statusBarVisible)
            }, completion: { finished in
                guard finished else { return }

                self.toolbarPreviewsOverlay.isHidden = true

                if navigationBarHidden {
                    self.navigationController?.setNavigationBarHidden(true, animated: false)
                }
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
                self.toolbarPreviewsOverlay.alpha = 0
                self.navigationController?.navigationBar.alpha = navigationBarHidden ? 0 : 1
                self.documentController.setInterface(hidden: !statusBarVisible)
                self.navigationController?.setNeedsStatusBarAppearanceUpdate()
                self.setNeedsStatusBarAppearanceUpdate()
            }, completion: { finished in
                guard finished else { return }

                self.toolbarPreviewsOverlay.isHidden = true

                if navigationBarHidden {
                    self.navigationController?.setNavigationBarHidden(true, animated: false)
                }
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
                    self.toolbarPreviewsOverlay.alpha = 0
                    self.navigationController?.navigationBar.alpha = navigationBarHidden ? 0 : 1
                    self.documentController.setInterface(hidden: !statusBarVisible)
                    self.navigationController?.setNeedsStatusBarAppearanceUpdate()
                    self.setNeedsStatusBarAppearanceUpdate()
                }, completion: { finished in
                    guard finished else { return }

                    self.toolbarPreviewsOverlay.isHidden = true

                    if navigationBarHidden {
                        self.navigationController?.setNavigationBarHidden(true, animated: false)
                    }
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
            self.documentTop.constant = statusBarOffset + self.annotationToolbarController.size

        case .top:
            self.documentTop.constant = totalOffset + self.annotationToolbarController.size

        case .trailing, .leading:
            self.documentTop.constant = totalOffset
        }
    }

    private func setFullConstraints(for position: ToolbarState.Position, statusBarVisible: Bool) {
        switch position {
        case .leading:
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = false
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
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = true
            self.toolbarTrailingSafeArea.constant = PDFReaderViewController.toolbarFullInsetInset
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
            self.toolbarTrailingSafeArea.isActive = false
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
            self.toolbarTrailing.isActive = false
            self.toolbarTrailingSafeArea.isActive = true
            self.toolbarTrailingSafeArea.constant = PDFReaderViewController.toolbarCompactInset
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
        self.toolbarTrailingSafeArea.isActive = false
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

    private func hideAnnotationToolbar(newState: ToolbarState, statusBarVisible: Bool, animated: Bool) {
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
            self.documentController.disableAnnotationTools()
            if !statusBarVisible {
                self.navigationController?.setNavigationBarHidden(true, animated: false)
            }
        })
    }

    private func setAnnotationToolbarHandleMinimumLongPressDuration(forPosition position: ToolbarState.Position) {
        switch position {
        case .leading, .trailing:
            self.annotationToolbarDragHandleLongPressRecognizer.minimumPressDuration = 0.3

        case .top, .pinned:
            self.annotationToolbarDragHandleLongPressRecognizer.minimumPressDuration = 0
        }
    }

    private func setHighlightSelected(at position: ToolbarState.Position) {
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

    // MARK: - Setups

    private func setupGestureRecognizer() {
        let panRecognizer = UIPanGestureRecognizer()
        panRecognizer.delegate = self
        panRecognizer.rx.event
                     .subscribe(with: self, onNext: { `self`, recognizer in
                         self.toolbarDidPan(recognizer: recognizer)
                     })
                    .disposed(by: self.disposeBag)
        self.annotationToolbarController.view.addGestureRecognizer(panRecognizer)

        let longPressRecognizer = UILongPressGestureRecognizer()
        longPressRecognizer.delegate = self
        longPressRecognizer.rx.event
                     .subscribe(with: self, onNext: { `self`, recognizer in
                         self.didTapToolbar(recognizer: recognizer)
                     })
                    .disposed(by: self.disposeBag)
        self.annotationToolbarDragHandleLongPressRecognizer = longPressRecognizer
        self.annotationToolbarController.view.addGestureRecognizer(longPressRecognizer)
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

        let annotationToolbar = AnnotationToolbarViewController(size: self.navigationBarHeight)
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

        let topPreview = DashedView(type: .partialStraight(sides: [.left, .right, .bottom]))
        self.setup(toolbarPositionView: topPreview)
        let inbetweenTopDash = DashedView(type: .partialStraight(sides: .bottom))
        self.setup(toolbarPositionView: inbetweenTopDash)
        let pinnedPreview = DashedView(type: .partialStraight(sides: [.left, .right, .top]))
        self.setup(toolbarPositionView: pinnedPreview)
        let leadingPreview = DashedView(type: .rounded(cornerRadius: 8))
        leadingPreview.translatesAutoresizingMaskIntoConstraints = false
        self.setup(toolbarPositionView: leadingPreview)
        let trailingPreview = DashedView(type: .rounded(cornerRadius: 8))
        trailingPreview.translatesAutoresizingMaskIntoConstraints = false
        self.setup(toolbarPositionView: trailingPreview)

        let topPreviewContainer = UIStackView(arrangedSubviews: [pinnedPreview, inbetweenTopDash, topPreview])
        topPreviewContainer.translatesAutoresizingMaskIntoConstraints = false
        topPreviewContainer.axis = .vertical

        self.add(controller: documentController)
        self.add(controller: sidebarController)
        self.add(controller: annotationToolbar)
        self.view.addSubview(documentController.view)
        self.view.addSubview(sidebarController.view)
        self.view.addSubview(separator)
        self.view.addSubview(annotationToolbar.view)
        self.view.insertSubview(previewsOverlay, belowSubview: annotationToolbar.view)
        previewsOverlay.addSubview(topPreviewContainer)
        previewsOverlay.addSubview(leadingPreview)
        previewsOverlay.addSubview(trailingPreview)

        let documentLeftConstraint = documentController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
        let sidebarLeftConstraint = sidebarController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: -PDFReaderLayout.sidebarWidth)
        self.documentTop = documentController.view.topAnchor.constraint(equalTo: self.view.topAnchor)
        self.toolbarLeading = annotationToolbar.view.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset)
        self.toolbarLeading.priority = .init(999)
        self.toolbarLeadingSafeArea = annotationToolbar.view.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor)
        self.toolbarTrailing = self.view.trailingAnchor.constraint(equalTo: annotationToolbar.view.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset)
        self.toolbarTrailingSafeArea = self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: annotationToolbar.view.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset)
        let toolbarTop = annotationToolbar.view.topAnchor.constraint(equalTo: self.view.topAnchor, constant: PDFReaderViewController.toolbarCompactInset)
        let leadingPreviewHeight = leadingPreview.heightAnchor.constraint(equalToConstant: 50)
        let trailingPreviewHeight = trailingPreview.heightAnchor.constraint(equalToConstant: 50)
        let pinnedPreviewHeight = pinnedPreview.heightAnchor.constraint(equalToConstant: annotationToolbar.size)

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
            self.toolbarLeadingSafeArea,
            previewsOverlay.topAnchor.constraint(equalTo: self.view.topAnchor),
            previewsOverlay.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            previewsOverlay.leadingAnchor.constraint(equalTo: documentController.view.leadingAnchor),
            previewsOverlay.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            topPreviewContainer.topAnchor.constraint(equalTo: previewsOverlay.topAnchor),
            topPreviewContainer.leadingAnchor.constraint(equalTo: previewsOverlay.leadingAnchor),
            previewsOverlay.trailingAnchor.constraint(equalTo: topPreviewContainer.trailingAnchor),
            pinnedPreviewHeight,
            topPreview.heightAnchor.constraint(equalToConstant: annotationToolbar.size),
            leadingPreview.leadingAnchor.constraint(equalTo: previewsOverlay.safeAreaLayoutGuide.leadingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset),
            leadingPreview.topAnchor.constraint(equalTo: topPreviewContainer.bottomAnchor, constant: PDFReaderViewController.toolbarCompactInset),
            leadingPreviewHeight,
            leadingPreview.widthAnchor.constraint(equalToConstant: annotationToolbar.size),
            previewsOverlay.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: trailingPreview.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset),
            trailingPreview.topAnchor.constraint(equalTo: topPreviewContainer.bottomAnchor, constant: PDFReaderViewController.toolbarCompactInset),
            trailingPreviewHeight,
            trailingPreview.widthAnchor.constraint(equalToConstant: annotationToolbar.size),
            inbetweenTopDash.heightAnchor.constraint(equalToConstant: 2 / UIScreen.main.scale)
        ])

        self.documentController = documentController
        self.documentControllerLeft = documentLeftConstraint
        self.sidebarController = sidebarController
        self.sidebarControllerLeft = sidebarLeftConstraint
        self.annotationToolbarController = annotationToolbar
        self.toolbarTop = toolbarTop
        self.toolbarPreviewsOverlay = previewsOverlay
        self.toolbarTopPreview = topPreview
        self.toolbarPinnedPreview = pinnedPreview
        self.toolbarLeadingPreview = leadingPreview
        self.toolbarLeadingPreviewHeight = leadingPreviewHeight
        self.toolbarTrailingPreview = trailingPreview
        self.toolbarTrailingPreviewHeight = trailingPreviewHeight
        self.toolbarPinnedPreviewHeight = pinnedPreviewHeight
        self.inbetweenTopDashedView = inbetweenTopDash
    }

    private func setup(toolbarPositionView view: DashedView) {
        view.backgroundColor = self.previewBackgroundColor
        view.dashColor = self.previewDashColor
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
        sidebarButton.tag = NavigationBarButton.sidebar.rawValue
        sidebarButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.toggleSidebar(animated: true) }).disposed(by: self.disposeBag)

        let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
        closeButton.title = L10n.close
        closeButton.accessibilityLabel = L10n.close
        closeButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.close() }).disposed(by: self.disposeBag)

        let readerButton = UIBarButtonItem(image: Asset.Images.pdfRawReader.image, style: .plain, target: nil, action: nil)
        readerButton.isEnabled = !self.viewModel.state.document.isLocked
        readerButton.accessibilityLabel = L10n.Accessibility.Pdf.openReader
        readerButton.title = L10n.Accessibility.Pdf.openReader
        readerButton.rx
                    .tap
                    .subscribe(with: self, onNext: { `self`, _ in
                        self.coordinatorDelegate?.showReader(document: self.viewModel.state.document, userInterfaceStyle: self.viewModel.state.interfaceStyle)
                    })
                    .disposed(by: self.disposeBag)

        self.navigationItem.leftBarButtonItems = [closeButton, sidebarButton, readerButton]
        self.navigationItem.rightBarButtonItems = self.rightBarButtonItems
    }

    private var rightBarButtonItems: [UIBarButtonItem] {
        var buttons = [settingsButton, shareButton, searchButton]

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
                                  .subscribe(with: self, onNext: { `self`, _ in
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
                                  .subscribe(with: self, onNext: { `self`, _ in
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
    func annotationTool(
        didChangeStateFrom oldState: PSPDFKit.Annotation.Tool?,
        to newState: PSPDFKit.Annotation.Tool?,
        variantFrom oldVariant: PSPDFKit.Annotation.Variant?,
        to newVariant: PSPDFKit.Annotation.Variant?
    ) {
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
        self.toolbarState = ToolbarState(position: self.toolbarState.position, visible: false)
        self.hideAnnotationToolbar(newState: self.toolbarState, statusBarVisible: self.statusBarVisible, animated: true)
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
            let window = (view.scene as? UIWindowScene)?.windows.first(where: \.isKeyWindow)
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

extension PDFReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let longPressRecognizer = gestureRecognizer as? UILongPressGestureRecognizer else { return true }

        let location = longPressRecognizer.location(in: self.annotationToolbarController.view)
        let currentLocation: CGFloat
        let border: CGFloat

        switch self.toolbarState.position {
        case .pinned, .top:
            currentLocation = location.x
            border = self.annotationToolbarController.view.frame.width - PDFReaderViewController.annotationToolbarDragHandleHeight

        case .leading, .trailing:
            currentLocation = location.y
            border = self.annotationToolbarController.view.frame.height - PDFReaderViewController.annotationToolbarDragHandleHeight
        }
        return currentLocation >= border
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension PDFReaderViewController: PDFSearchDelegate {
    func didFinishSearch(with results: [SearchResult], for text: String?) {
        documentController.highlightSearchResults(results)
    }
    
    func didSelectSearchResult(_ result: SearchResult) {
        documentController.highlightSelectedSearchResult(result)
    }
}
