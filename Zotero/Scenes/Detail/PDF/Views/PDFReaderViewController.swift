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
        }

        let position: Position
        let visible: Bool
    }

    private enum Animation {
        case fade(duration: TimeInterval)
        case sideToSide(duration: TimeInterval, velocity: CGFloat, options: UIView.AnimationOptions)

        func animate(animation: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
            switch self {
            case .fade(let duration):
                UIView.animate(withDuration: duration, animations: animation, completion: completion)

            case .sideToSide(let duration, let velocity, let options):
                UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: options, animations: animation, completion: completion)
            }
        }
    }

    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag
    private static let toolbarCompactInset: CGFloat = 12
    private static let toolbarFullInsetInset: CGFloat = 20

    private weak var sidebarController: PDFSidebarViewController!
    private weak var sidebarControllerLeft: NSLayoutConstraint!
    private weak var documentController: PDFDocumentViewController!
    private weak var documentControllerLeft: NSLayoutConstraint!
    private weak var annotationToolbarController: AnnotationToolbarViewController!
    private weak var toolbarTop: NSLayoutConstraint!
    private var toolbarLeading: NSLayoutConstraint!
    private var toolbarCenteredLeading: NSLayoutConstraint!
    private var toolbarTrailing: NSLayoutConstraint!
    private var toolbarCenteredTrailing: NSLayoutConstraint!
    private var toolbarCenter: NSLayoutConstraint!
    private weak var toolbarPositionsOverlay: UIView!
    private weak var toolbarLeadingView: DashedView!
    private weak var toolbarLeadingViewTop: NSLayoutConstraint!
    private weak var toolbarLeadingViewHeight: NSLayoutConstraint!
    private weak var toolbarTrailingView: DashedView!
    private weak var toolbarTrailingViewTop: NSLayoutConstraint!
    private weak var toolbarTrailingViewHeight: NSLayoutConstraint!
    private weak var toolbarTopView: DashedView!
    private weak var toolbarTopViewTop: NSLayoutConstraint!
    private weak var toolbarTopViewWidth: NSLayoutConstraint!
    private(set) var isSidebarTransitioning: Bool
    private(set) var isCompactSize: Bool
    @CodableUserDefault(key: "PDFReaderToolbarState", defaultValue: ToolbarState(position: .leading, visible: true), encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    private var toolbarState: ToolbarState
    private var toolbarInitialFrame: CGRect?
    var isSidebarVisible: Bool { return self.sidebarControllerLeft?.constant == 0 }
    var key: String { return self.viewModel.state.key }

    weak var coordinatorDelegate: (DetailPdfCoordinatorDelegate & DetailAnnotationsCoordinatorDelegate)?

    private lazy var shareButton: UIBarButtonItem = {
        let share = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)
        share.accessibilityLabel = L10n.Accessibility.Pdf.export
        share.tag = NavigationBarButton.share.rawValue
        share.rx.tap
             .subscribe(onNext: { [weak self, weak share] _ in
                 guard let `self` = self, let share = share else { return }
                 self.coordinatorDelegate?.showPdfExportSettings(sender: share) { [weak self] settings in
                     self?.viewModel.process(action: .export(settings))
                 }
             })
             .disposed(by: self.disposeBag)
        return share
    }()
    private lazy var settingsButton: UIBarButtonItem = {
        let settings = self.documentController.pdfController.settingsButtonItem
        settings.rx
                .tap
                .subscribe(onNext: { [weak self] _ in
                    self?.showSettings(sender: settings)
                })
                .disposed(by: self.disposeBag)
        return settings
    }()
    private lazy var searchButton: UIBarButtonItem = {
        let search = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: nil, action: nil)
        search.rx.tap
              .subscribe(onNext: { [weak self] _ in
                  guard let `self` = self else { return }
                  self.showSearch(pdfController: self.documentController.pdfController, text: nil)
              })
              .disposed(by: self.disposeBag)
        return search
    }()
    private var undoBarButton: UIBarButtonItem?
    private var redoBarButton: UIBarButtonItem?
    private lazy var toolbarButton: UIBarButtonItem = {
        let checkbox = CheckboxButton(type: .custom)
        checkbox.accessibilityLabel = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        checkbox.setImage(UIImage(systemName: "pencil.and.outline", withConfiguration: UIImage.SymbolConfiguration(scale: .large))?.withRenderingMode(.alwaysTemplate), for: .normal)
        checkbox.adjustsImageWhenHighlighted = false
        checkbox.layer.cornerRadius = 4
        checkbox.layer.masksToBounds = true
        checkbox.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        checkbox.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        checkbox.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        checkbox.selectedTintColor = .white
        checkbox.isSelected = self.toolbarState.visible
        checkbox.rx.controlEvent(.touchDown)
                .subscribe(onNext: { [weak self, weak checkbox] _ in
                    guard let `self` = self, let checkbox = checkbox else { return }
                    checkbox.isSelected = !checkbox.isSelected

                    self.toolbarState = ToolbarState(position: self.toolbarState.position, visible: checkbox.isSelected)

                    if checkbox.isSelected {
                        self.showAnnotationToolbar(at: self.toolbarState.position, animated: true)
                    } else {
                        self.hideAnnotationToolbar(animated: true)
                    }
                })
                .disposed(by: self.disposeBag)
        return UIBarButtonItem(customView: checkbox)
    }()

    init(viewModel: ViewModel<PDFReaderActionHandler>, compactSize: Bool) {
        self.viewModel = viewModel
        self.isSidebarTransitioning = false
        self.isCompactSize = compactSize
        self.disposeBag = DisposeBag()
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
        self.setConstraints(for: self.toolbarState.position)
        if self.toolbarState.visible {
            self.showAnnotationToolbar(at: self.toolbarState.position, animated: false)
        } else {
            self.hideAnnotationToolbar(animated: false)
        }
        self.setupNavigationBar()
        self.setupGestureRecognizer()
        self.setupObserving()
        self.updateInterface(to: self.viewModel.state.settings)

        self.viewModel.process(action: .loadDocumentData(boundingBoxConverter: self.documentController))

        if self.viewModel.state.selectedAnnotation != nil {
            self.toggleSidebar(animated: false)
        }
    }

    deinit {
        self.viewModel.process(action: .changeIdleTimerDisabled(false))
        self.coordinatorDelegate?.pdfDidDeinitialize()
        DDLogInfo("PDFReaderViewController deinitialized")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        self.viewModel.process(action: .userInterfaceStyleChanged(self.traitCollection.userInterfaceStyle))
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let isCompactSize = UIDevice.current.isCompactWidth(size: size)
        let sizeDidChange = isCompactSize != self.isCompactSize
        self.isCompactSize = isCompactSize

        guard self.viewIfLoaded != nil else { return }

        if self.isSidebarVisible && sizeDidChange {
            self.documentControllerLeft.constant = isCompactSize ? 0 : PDFReaderLayout.sidebarWidth
        }

        coordinator.animate(alongsideTransition: { _ in
            if sizeDidChange {
                self.navigationItem.rightBarButtonItems = self.createRightBarButtonItems(forCompactSize: isCompactSize)
                self.annotationToolbarController.updateAdditionalButtons()
                self.setConstraints(for: self.toolbarState.position)
                self.view.layoutIfNeeded()
                self.showToolbarButtonsThatFit(size: size)
            }
        }, completion: nil)
    }

    // MARK: - Actions

    private func update(state: PDFReaderState) {
        if state.changes.contains(.annotations) {
            // Hide popover if annotation has been deleted
            if let controller = (self.presentedViewController as? UINavigationController)?.viewControllers.first as? AnnotationPopover, let key = controller.annotationKey, !state.sortedKeys.contains(key) {
                self.dismiss(animated: true, completion: nil)
            }
        }

        if state.changes.contains(.interfaceStyle) || state.changes.contains(.settings) {
            self.updateInterface(to: state.settings)
        }

        if state.changes.contains(.export) {
            self.update(state: state.exportState)
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

    internal func showColorPicker(sender: UIButton) {
        self.coordinatorDelegate?.showColorPicker(selected: self.viewModel.state.activeColor.hexString, sender: sender, save: { [weak self] color in
            self?.viewModel.process(action: .setActiveColor(color))
        })
    }

    private func toggleSidebar(animated: Bool) {
        let shouldShow = !self.isSidebarVisible

        // If the layout is compact, show annotation sidebar above pdf document.
        if !UIDevice.current.isCompactWidth(size: self.view.frame.size) {
            self.documentControllerLeft.constant = shouldShow ? PDFReaderLayout.sidebarWidth : 0
        }
        self.sidebarControllerLeft.constant = shouldShow ? 0 : -PDFReaderLayout.sidebarWidth

        self.navigationItem.leftBarButtonItems?.last?.accessibilityLabel = shouldShow ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen

        if !animated {
            self.sidebarController.view.isHidden = !shouldShow
            self.view.layoutIfNeeded()

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

        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 1,
                       initialSpringVelocity: 5,
                       options: [.curveEaseOut],
                       animations: {
                           self.view.layoutIfNeeded()
                       },
                       completion: { finished in
                           guard finished else { return }
                           if !shouldShow {
                               self.sidebarController.view.isHidden = true
                           }
                           self.isSidebarTransitioning = false
                       })
    }

    func showSearch(pdfController: PDFViewController, text: String?) {
        self.coordinatorDelegate?.showSearch(pdfController: pdfController, text: text, sender: self.searchButton, result: { [weak self] result in
            self?.documentController.highlight(result: result)
        })
    }

    private func showSettings(sender: UIBarButtonItem) {
        self.coordinatorDelegate?.showSettings(with: self.viewModel.state.settings, sender: sender, completion: { [weak self] settings in
            self?.viewModel.process(action: .setSettings(settings))
        })
    }

    private func close() {
        self.viewModel.process(action: .clearTmpAnnotationPreviews)
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    /// Return new position for given center and velocity of toolbar. The user can pan up/left/right to move the toolbar. If velocity > 1500, it's considered a swipe and the toolbar
    /// is moved in swipe direction. Otherwise the toolbar is pinned to closest point from center.
    private func position(fromCenter point: CGPoint, frame: CGRect, velocity: CGPoint) -> ToolbarState.Position {
        if velocity.y > -1500 && abs(velocity.x) < 1500 {
            // Move to closest point. Use different threshold for vertical/horizontal rotation.
            let threshold: CGFloat
            if frame.height > frame.width {
                threshold = self.isCompactSize ? 150 : 100
            } else {
                threshold = 200
            }
            if point.y < threshold {
                return .top
            }

            return point.x > self.view.frame.width / 2 ? .trailing : .leading
        }

        // Move in direction of swipe

        if abs(velocity.y) > abs(velocity.x) {
            // Vertical movement
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
            self.annotationToolbarController.view.frame = originalFrame.offsetBy(dx: translation.x, dy: translation.y)

            let position = self.position(fromCenter: self.annotationToolbarController.view.center, frame: self.annotationToolbarController.view.frame, velocity: CGPoint())

            if self.toolbarPositionsOverlay.isHidden && position != self.toolbarState.position {
                let size = max(self.annotationToolbarController.view.frame.width, self.annotationToolbarController.view.frame.height)
                self.updatePositionOverlayViews(for: size)
                self.toolbarPositionsOverlay.isHidden = false
            }

            if !self.toolbarPositionsOverlay.isHidden {
                self.setHighlightSelected(at: position)
            }

        case .cancelled, .ended, .failed:
            let velocity = recognizer.velocity(in: self.view)
            let position = self.position(fromCenter: self.annotationToolbarController.view.center, frame: self.annotationToolbarController.view.frame, velocity: velocity)
            let newState = ToolbarState(position: position, visible: true)

            self.toolbarPositionsOverlay.isHidden = true
            self.set(toolbarPosition: position, oldPosition: self.toolbarState.position, velocity: velocity)
            self.toolbarState = newState
            self.toolbarInitialFrame = nil

        case .possible: break
        @unknown default: break
        }
    }

    private func updatePositionOverlayViews(for size: CGFloat) {
        self.toolbarLeadingViewHeight.constant = size
        self.toolbarTrailingViewHeight.constant = size
        if self.isCompactSize {
            self.toolbarTopViewWidth.constant = self.view.frame.width
            self.toolbarTopView.layer.cornerRadius = 0
            self.toolbarTopViewTop.constant = 0
            let topInset = AnnotationToolbarViewController.size + PDFReaderViewController.toolbarCompactInset
            self.toolbarLeadingViewTop.constant = topInset
            self.toolbarTrailingViewTop.constant = topInset
        } else {
            self.toolbarTopViewWidth.constant = size
            self.toolbarTopView.layer.cornerRadius = 8
            self.toolbarTopViewTop.constant = PDFReaderViewController.toolbarFullInsetInset
            self.toolbarLeadingViewTop.constant = PDFReaderViewController.toolbarFullInsetInset
            self.toolbarTrailingViewTop.constant = PDFReaderViewController.toolbarFullInsetInset
        }
        self.toolbarPositionsOverlay.layoutIfNeeded()
    }

    private func set(toolbarPosition newPosition: ToolbarState.Position, oldPosition: ToolbarState.Position, velocity velocityPoint: CGPoint) {
        switch (newPosition, oldPosition) {
            case (.leading, .leading), (.trailing, .trailing), (.top, .top):
                // Position didn't change, move to initial frame
                let frame = self.toolbarInitialFrame ?? CGRect()
                let velocity = self.velocity(from: velocityPoint, newPosition: newPosition)
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [.curveEaseOut], animations: {
                    self.annotationToolbarController.view.frame = frame
                })

            case (.leading, .trailing), (.trailing, .leading):
                // Move from side to side
                let velocity = self.velocity(from: velocityPoint, newPosition: newPosition)
                self.setConstraints(for: newPosition)
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [.curveEaseOut], animations: {
                    self.view.layoutIfNeeded()
                })

            case (.top, .leading), (.top, .trailing), (.leading, .top), (.trailing, .top):
                let velocity = self.velocity(from: velocityPoint, newPosition: newPosition)
                UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: {
                    let newFrame = self.annotationToolbarController.view.frame.offsetBy(dx: velocityPoint.x / 10, dy: velocityPoint.y / 10)
                    self.annotationToolbarController.view.frame = newFrame
                    self.annotationToolbarController.view.alpha = 0
                }, completion: { finished in
                    guard finished else { return }

                    self.setConstraints(for: newPosition)
                    self.view.layoutIfNeeded()
                    self.showToolbarButtonsThatFit(size: self.view.frame.size)

                    UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: velocity, options: [], animations: {
                        self.annotationToolbarController.view.alpha = 1
                    })
                })
        }
    }

    private func setConstraints(for position: ToolbarState.Position) {
        if self.isCompactSize {
            self.setCompactConstraints(for: position)
        } else {
            self.setFullConstraints(for: position)
        }
    }

    private func showToolbarButtonsThatFit(size: CGSize) {
        let maxSize: CGFloat

        switch self.toolbarState.position {
        case .top:
            maxSize = self.isCompactSize ? size.width : (size.width - (2 * PDFReaderViewController.toolbarFullInsetInset))
        case .trailing, .leading:
            let interfaceIsHidden = self.navigationController?.isNavigationBarHidden ?? false
            maxSize = size.height - (2 * PDFReaderViewController.toolbarCompactInset) - (interfaceIsHidden ? 0 : (self.view.safeAreaInsets.top + self.documentController.scrubberBarHeight))
        }

        self.annotationToolbarController.showToolsThatFit(containerMaxSize: maxSize)
    }

    private func setFullConstraints(for position: ToolbarState.Position) {
        switch position {
        case .leading:
            self.toolbarCenteredTrailing.isActive = false
            self.toolbarCenteredLeading.isActive = false
            self.toolbarCenter.isActive = false
            self.toolbarTrailing.isActive = false
            self.toolbarLeading.isActive = true
            self.toolbarLeading.constant = PDFReaderViewController.toolbarFullInsetInset
            self.toolbarTop.constant = PDFReaderViewController.toolbarFullInsetInset
            self.annotationToolbarController.set(rotation: .vertical, isCompactSize: self.isCompactSize)

        case .trailing:
            self.toolbarCenteredTrailing.isActive = false
            self.toolbarCenteredLeading.isActive = false
            self.toolbarCenter.isActive = false
            self.toolbarLeading.isActive = false
            self.toolbarTrailing.isActive = true
            self.toolbarTrailing.constant = PDFReaderViewController.toolbarFullInsetInset
            self.toolbarTop.constant = PDFReaderViewController.toolbarFullInsetInset
            self.annotationToolbarController.set(rotation: .vertical, isCompactSize: self.isCompactSize)

        case .top:
            self.toolbarTrailing.isActive = false
            self.toolbarLeading.isActive = false
            self.toolbarCenteredTrailing.isActive = true
            self.toolbarCenteredLeading.isActive = true
            self.toolbarCenter.isActive = true
            self.toolbarTop.constant = PDFReaderViewController.toolbarCompactInset
            self.annotationToolbarController.set(rotation: .horizontal, isCompactSize: self.isCompactSize)
        }
    }

    private func setCompactConstraints(for position: ToolbarState.Position) {
        switch position {
        case .leading:
            self.toolbarCenteredTrailing.isActive = false
            self.toolbarCenteredLeading.isActive = false
            self.toolbarCenter.isActive = false
            self.toolbarTrailing.isActive = false
            self.toolbarLeading.isActive = true
            self.toolbarLeading.constant = PDFReaderViewController.toolbarFullInsetInset
            self.toolbarTop.constant = PDFReaderViewController.toolbarFullInsetInset
            self.annotationToolbarController.set(rotation: .vertical, isCompactSize: self.isCompactSize)

        case .trailing:
            self.toolbarCenteredTrailing.isActive = false
            self.toolbarCenteredLeading.isActive = false
            self.toolbarCenter.isActive = false
            self.toolbarLeading.isActive = false
            self.toolbarTrailing.isActive = true
            self.toolbarTrailing.constant = PDFReaderViewController.toolbarFullInsetInset
            self.toolbarTop.constant = PDFReaderViewController.toolbarFullInsetInset
            self.annotationToolbarController.set(rotation: .vertical, isCompactSize: self.isCompactSize)

        case .top:
            self.toolbarCenteredTrailing.isActive = false
            self.toolbarCenteredLeading.isActive = false
            self.toolbarCenter.isActive = false
            self.toolbarTrailing.isActive = true
            self.toolbarTrailing.constant = 0
            self.toolbarLeading.isActive = true
            self.toolbarLeading.constant = 0
            self.toolbarTop.constant = 0
            self.annotationToolbarController.set(rotation: .horizontal, isCompactSize: self.isCompactSize)
        }
    }

    private func showAnnotationToolbar(at position: ToolbarState.Position, animated: Bool) {
        self.setConstraints(for: position)
        self.annotationToolbarController.view.isHidden = false
        self.view.layoutIfNeeded()
        self.showToolbarButtonsThatFit(size: self.view.frame.size)

        if !animated {
            self.annotationToolbarController.view.alpha = 1
            return
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.annotationToolbarController.view.alpha = 1
        })
    }

    private func hideAnnotationToolbar(animated: Bool) {
        if !animated {
            self.view.layoutIfNeeded()
            self.annotationToolbarController.view.alpha = 0
            self.annotationToolbarController.view.isHidden = true
            return
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.view.layoutIfNeeded()
            self.annotationToolbarController.view.alpha = 0
        }, completion: { finished in
            guard finished else { return }
            self.annotationToolbarController.view.isHidden = true
        })
    }

    private func setHighlightSelected(at position: ToolbarState.Position) {
        switch position {
        case .top:
            self.toolbarLeadingView.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarLeadingView.dashColor = UIColor.systemGray4
            self.toolbarTrailingView.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTrailingView.dashColor = UIColor.systemGray4
            self.toolbarTopView.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
            self.toolbarTopView.dashColor = Asset.Colors.zoteroBlueWithDarkMode.color

        case .leading:
            self.toolbarLeadingView.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
            self.toolbarLeadingView.dashColor = Asset.Colors.zoteroBlueWithDarkMode.color
            self.toolbarTrailingView.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTrailingView.dashColor = UIColor.systemGray4
            self.toolbarTopView.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTopView.dashColor = UIColor.systemGray4

        case .trailing:
            self.toolbarLeadingView.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarLeadingView.dashColor = UIColor.systemGray4
            self.toolbarTrailingView.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color.withAlphaComponent(0.5)
            self.toolbarTrailingView.dashColor = Asset.Colors.zoteroBlueWithDarkMode.color
            self.toolbarTopView.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
            self.toolbarTopView.dashColor = UIColor.systemGray4
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
        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false

        let documentController = PDFDocumentViewController(viewModel: self.viewModel, compactSize: self.isCompactSize)
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

        let positionsOverlay = UIView()
        positionsOverlay.translatesAutoresizingMaskIntoConstraints = false
        positionsOverlay.backgroundColor = .clear
        positionsOverlay.isHidden = true

        let topPosition = DashedView(dashColor: .systemGray4)
        self.setup(toolbarPositionView: topPosition)
        let leadingPosition = DashedView(dashColor: .systemGray4)
        leadingPosition.layer.cornerRadius = 8
        self.setup(toolbarPositionView: leadingPosition)
        let trailingPosition = DashedView(dashColor: .systemGray4)
        trailingPosition.layer.cornerRadius = 8
        self.setup(toolbarPositionView: trailingPosition)

        self.add(controller: documentController)
        self.add(controller: sidebarController)
        self.add(controller: annotationToolbar)
        container.addSubview(documentController.view)
        container.addSubview(sidebarController.view)
        container.addSubview(separator)
        self.view.addSubview(container)
        self.view.addSubview(annotationToolbar.view)
        self.view.insertSubview(positionsOverlay, belowSubview: annotationToolbar.view)
        positionsOverlay.addSubview(topPosition)
        positionsOverlay.addSubview(leadingPosition)
        positionsOverlay.addSubview(trailingPosition)

        let documentLeftConstraint = documentController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        let sidebarLeftConstraint = sidebarController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: -PDFReaderLayout.sidebarWidth)
        self.toolbarLeading = annotationToolbar.view.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset)
        self.toolbarCenteredLeading = annotationToolbar.view.leadingAnchor.constraint(greaterThanOrEqualTo: sidebarController.view.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset)
        self.toolbarTrailing = self.view.trailingAnchor.constraint(equalTo: annotationToolbar.view.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset)
        self.toolbarCenteredTrailing = self.view.trailingAnchor.constraint(greaterThanOrEqualTo: annotationToolbar.view.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset)
        self.toolbarCenter = annotationToolbar.view.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        let toolbarTop = annotationToolbar.view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: PDFReaderViewController.toolbarCompactInset)
        let topWidth = topPosition.widthAnchor.constraint(equalToConstant: 50)
        let leadingHeight = leadingPosition.heightAnchor.constraint(equalToConstant: 50)
        let trailingHeight = trailingPosition.heightAnchor.constraint(equalToConstant: 50)
        let topPositionTop = topPosition.topAnchor.constraint(equalTo: positionsOverlay.topAnchor, constant: PDFReaderViewController.toolbarCompactInset)
        let leadingPositionTop = leadingPosition.topAnchor.constraint(equalTo: positionsOverlay.topAnchor, constant: PDFReaderViewController.toolbarCompactInset)
        let trailingPositionTop = trailingPosition.topAnchor.constraint(equalTo: positionsOverlay.topAnchor, constant: PDFReaderViewController.toolbarCompactInset)

        NSLayoutConstraint.activate([
            sidebarController.view.topAnchor.constraint(equalTo: container.topAnchor),
            sidebarController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebarController.view.widthAnchor.constraint(equalToConstant: PDFReaderLayout.sidebarWidth),
            sidebarLeftConstraint,
            separator.widthAnchor.constraint(equalToConstant: PDFReaderLayout.separatorWidth),
            separator.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor),
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            documentController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            documentController.view.topAnchor.constraint(equalTo: container.topAnchor),
            documentController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            documentLeftConstraint,
            toolbarTop,
            container.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            positionsOverlay.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            positionsOverlay.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            positionsOverlay.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            positionsOverlay.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            topPositionTop,
            topPosition.centerXAnchor.constraint(equalTo: positionsOverlay.centerXAnchor),
            topPosition.heightAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size),
            leadingPositionTop,
            leadingPosition.leadingAnchor.constraint(equalTo: positionsOverlay.leadingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset),
            leadingPosition.widthAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size),
            trailingPositionTop,
            positionsOverlay.trailingAnchor.constraint(equalTo: trailingPosition.trailingAnchor, constant: PDFReaderViewController.toolbarFullInsetInset),
            trailingPosition.widthAnchor.constraint(equalToConstant: AnnotationToolbarViewController.size),
            topWidth,
            leadingHeight,
            trailingHeight
        ])

        self.documentController = documentController
        self.documentControllerLeft = documentLeftConstraint
        self.sidebarController = sidebarController
        self.sidebarControllerLeft = sidebarLeftConstraint
        self.annotationToolbarController = annotationToolbar
        self.toolbarPositionsOverlay = positionsOverlay
        self.toolbarLeadingView = leadingPosition
        self.toolbarTrailingView = trailingPosition
        self.toolbarTopView = topPosition
        self.toolbarTop = toolbarTop
        self.toolbarTopViewWidth = topWidth
        self.toolbarLeadingViewHeight = leadingHeight
        self.toolbarTrailingViewHeight = trailingHeight
        self.toolbarTopViewTop = topPositionTop
        self.toolbarLeadingViewTop = leadingPositionTop
        self.toolbarTrailingViewTop = trailingPositionTop
    }

    private func setup(toolbarPositionView view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
        view.layer.masksToBounds = true
    }

    private func setupNavigationBar() {
        let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"), style: .plain, target: nil, action: nil)
        sidebarButton.accessibilityLabel = self.isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
        sidebarButton.rx.tap
                     .subscribe(with: self, onNext: { `self`, _ in self.toggleSidebar(animated: true) })
                     .disposed(by: self.disposeBag)
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
        closeButton.rx.tap
                   .subscribe(with: self, onNext: { `self`, _ in self.close() })
                   .disposed(by: self.disposeBag)
        let readerButton = UIBarButtonItem(image: self.documentController.pdfController.readerViewButtonItem.image, style: .plain, target: nil, action: nil)
        readerButton.accessibilityLabel = self.isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
        readerButton.rx.tap
                    .subscribe(with: self, onNext: { `self`, _ in self.coordinatorDelegate?.showReader(document: self.viewModel.state.document) })
                    .disposed(by: self.disposeBag)

        self.navigationItem.leftBarButtonItems = [closeButton, sidebarButton, readerButton]
        self.navigationItem.rightBarButtonItems = self.createRightBarButtonItems(forCompactSize: self.isCompactSize)
    }

    private func createRightBarButtonItems(forCompactSize isCompact: Bool) -> [UIBarButtonItem] {
        var buttons = [self.settingsButton, self.shareButton, self.searchButton]

        if !isCompact {
            let undo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.left"), style: .plain, target: nil, action: nil)
            undo.isEnabled = self.viewModel.state.document.undoController.undoManager.canUndo
            undo.tag = NavigationBarButton.undo.rawValue
            undo.rx
                .tap
                .subscribe(onNext: { [weak self] _ in
                    guard let `self` = self, self.viewModel.state.document.undoController.undoManager.canUndo else { return }
                    self.viewModel.state.document.undoController.undoManager.undo()
                })
                .disposed(by: self.disposeBag)
            self.undoBarButton = undo

            let redo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.right"), style: .plain, target: nil, action: nil)
            redo.isEnabled = self.viewModel.state.document.undoController.undoManager.canRedo
            redo.tag = NavigationBarButton.redo.rawValue
            redo.rx
                .tap
                .subscribe(onNext: { [weak self] _ in
                    guard let `self` = self, self.viewModel.state.document.undoController.undoManager.canRedo else { return }
                    self.viewModel.state.document.undoController.undoManager.redo()
                })
                .disposed(by: self.disposeBag)
            self.redoBarButton = redo

            buttons.insert(contentsOf: [redo, undo], at: 2)
        }

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
            self.annotationToolbarController.set(selected: false, to: state)
        }

        if let state = newState {
            self.annotationToolbarController.set(selected: true, to: state)
        }
    }

    func didChange(undoState undoEnabled: Bool, redoState redoEnabled: Bool) {

    }

    func interfaceVisibilityDidChange(to isHidden: Bool) {
        self.navigationController?.setNavigationBarHidden(isHidden, animated: true)
        UIView.animate(withDuration: 0.15) {
            self.view.layoutIfNeeded()
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
        case .top: return .horizontal
        }
    }

    func closeAnnotationToolbar() {
        (self.toolbarButton.customView as? CheckboxButton)?.isSelected = false
        self.hideAnnotationToolbar(animated: true)
    }

    var activeAnnotationColor: UIColor {
        return self.viewModel.state.activeColor
    }

    var activeAnnotationTool: PSPDFKit.Annotation.Tool? {
        return self.documentController.pdfController.annotationStateManager.state
    }

    func toggle(tool: PSPDFKit.Annotation.Tool, options: AnnotationToolOptions) {
        self.documentController.toggle(annotationTool: tool, tappedWithStylus: (options == .stylus))
    }

    func showInkSettings(sender: UIView) {
        self.coordinatorDelegate?.showSliderSettings(sender: sender, title: L10n.Pdf.AnnotationPopover.lineWidth, initialValue: self.viewModel.state.activeLineWidth,
                                                     valueChanged: { [weak self] newValue in
            self?.viewModel.process(action: .setActiveLineWidth(newValue))
        })
    }

    func showEraserSettings(sender: UIView) {
        self.coordinatorDelegate?.showSliderSettings(sender: sender, title: L10n.Pdf.AnnotationPopover.size, initialValue: self.viewModel.state.activeEraserSize,
                                                     valueChanged: { [weak self] newValue in
            self?.viewModel.process(action: .setActiveEraserSize(newValue))
        })
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
