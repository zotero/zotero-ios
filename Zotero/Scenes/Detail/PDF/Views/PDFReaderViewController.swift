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
    private static let sidebarButtonTag = 7
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    var state: PDFReaderState { return viewModel.state }
    private weak var sidebarController: PDFSidebarViewController!
    private weak var sidebarControllerLeft: NSLayoutConstraint!
    private weak var documentController: PDFDocumentViewController!
    private weak var documentControllerLeft: NSLayoutConstraint!
    private weak var annotationToolbarController: AnnotationToolbarViewController!
    private var documentTop: NSLayoutConstraint!
    private var annotationToolbarHandler: AnnotationToolbarHandler!
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
    @CodableUserDefault(key: "PDFReaderToolbarState", defaultValue: AnnotationToolbarHandler.State(position: .leading, visible: true), encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var toolbarState: AnnotationToolbarHandler.State
    @UserDefault(key: "PDFReaderStatusBarVisible", defaultValue: true)
    var statusBarVisible: Bool {
        didSet {
            (self.navigationController as? NavigationViewController)?.statusBarVisible = self.statusBarVisible
        }
    }
    private var previousTraitCollection: UITraitCollection?
    var isSidebarVisible: Bool { return self.sidebarControllerLeft?.constant == 0 }
    var key: String { return self.viewModel.state.key }
    var statusBarHeight: CGFloat
    var navigationBarHeight: CGFloat {
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
                 guard let self, let share else { return }
                 self.coordinatorDelegate?.showPdfExportSettings(
                    sender: share,
                    userInterfaceStyle: self.viewModel.state.settings.appearanceMode.userInterfaceStyle
                 ) { [weak self] settings in
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
                    self.annotationToolbarHandler.set(hidden: !checkbox.isSelected, animated: true)
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
        self.setupObserving()
        self.updateInterface(to: self.viewModel.state.settings)

        if !self.viewModel.state.document.isLocked {
            self.viewModel.process(action: .loadDocumentData(boundingBoxConverter: self.documentController))
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        self.annotationToolbarHandler.viewIsAppearing(documentIsLocked: self.viewModel.state.document.isLocked)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    deinit {
        DDLogInfo("PDFReaderViewController deinitialized")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if self.documentController.view.frame.width < AnnotationToolbarHandler.minToolbarWidth && self.toolbarState.visible && self.toolbarState.position == .top {
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
            self.annotationToolbarHandler.viewWillTransitionToNewSize()
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
            if (self.presentedViewController as? UINavigationController)?.viewControllers.first is AnnotationPopover, let key = state.selectedAnnotationKey, !state.sortedKeys.contains(key) {
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

        if let tool = state.changedColorForTool, self.documentController.pdfController?.annotationStateManager.state == tool, let color = state.toolColors[tool] {
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
        guard let tool = self.documentController.pdfController?.annotationStateManager.state, let toolbarTool = tool.toolbarTool else { return }

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
            tool: toolbarTool,
            colorHex: colorHex,
            sizeValue: size,
            sender: sender,
            userInterfaceStyle: self.viewModel.state.settings.appearanceMode.userInterfaceStyle
        ) { [weak self] newColor, newSize in
            self?.viewModel.process(action: .setToolOptions(color: newColor, size: newSize.flatMap(CGFloat.init), tool: tool))
        }
    }

    private func toggleSidebar(animated: Bool) {
        let shouldShow = !self.isSidebarVisible

        if self.toolbarState.position == .leading {
            if shouldShow {
                self.annotationToolbarHandler.disableLeadingSafeConstraint()
            } else {
                self.annotationToolbarHandler.enableLeadingSafeConstraint()
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
        self.coordinatorDelegate?.showSearch(
            pdfController: pdfController,
            text: text,
            sender: self.searchButton,
            userInterfaceStyle: self.viewModel.state.settings.appearanceMode.userInterfaceStyle,
            delegate: self
        )
    }

    private func showSettings(sender: UIBarButtonItem) {
        let viewModel = self.coordinatorDelegate?.showSettings(with: self.viewModel.state.settings, sender: sender)
        
        viewModel?.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, state in
                guard let interfaceStyle = self.presentingViewController?.traitCollection.userInterfaceStyle else { return }
                let settings = PDFSettings(
                    transition: state.transition,
                    pageMode: state.pageMode,
                    direction: state.scrollDirection,
                    pageFitting: state.pageFitting,
                    appearanceMode: state.appearance,
                    idleTimerDisabled: state.idleTimerDisabled
                )
                self.viewModel.process(action: .setSettings(settings: settings, parentUserInterfaceStyle: interfaceStyle))
            })
            .disposed(by: disposeBag)
    }

    private func close() {
        if let page = self.documentController?.pdfController?.pageIndex {
            self.viewModel.process(action: .submitPendingPage(Int(page)))
        }
        self.viewModel.process(action: .changeIdleTimerDisabled(false))
        self.viewModel.process(action: .clearTmpData)
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func add(controller: UIViewController) {
        controller.willMove(toParent: self)
        self.addChild(controller)
        controller.didMove(toParent: self)
    }

    private func setupViews() {
        let topSafeAreaSpacer = UIView()
        topSafeAreaSpacer.translatesAutoresizingMaskIntoConstraints = false
        topSafeAreaSpacer.backgroundColor = Asset.Colors.navbarBackground.color

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

        let annotationToolbar = AnnotationToolbarViewController(tools: [.highlight, .note, .image, .ink, .eraser], undoRedoEnabled: true, size: self.navigationBarHeight)
        annotationToolbar.delegate = self

        self.add(controller: documentController)
        self.add(controller: sidebarController)
        self.add(controller: annotationToolbar)
        self.view.addSubview(topSafeAreaSpacer)
        self.view.addSubview(documentController.view)
        self.view.addSubview(sidebarController.view)
        self.view.addSubview(separator)
        self.view.addSubview(annotationToolbar.view)

        let documentLeftConstraint = documentController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
        let sidebarLeftConstraint = sidebarController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: -PDFReaderLayout.sidebarWidth)
        self.documentTop = documentController.view.topAnchor.constraint(equalTo: self.view.topAnchor)

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
            documentLeftConstraint
        ])

        self.documentController = documentController
        self.documentControllerLeft = documentLeftConstraint
        self.sidebarController = sidebarController
        self.sidebarControllerLeft = sidebarLeftConstraint
        self.annotationToolbarController = annotationToolbar

        self.annotationToolbarHandler = AnnotationToolbarHandler(controller: annotationToolbar, delegate: self)
        self.annotationToolbarHandler.didHide = { [weak self] in
            self?.documentController.disableAnnotationTools()
        }
        self.annotationToolbarHandler.performInitialLayout()
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
                self.coordinatorDelegate?.showReader(document: self.viewModel.state.document, userInterfaceStyle: self.viewModel.state.settings.appearanceMode.userInterfaceStyle)
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

extension PDFReaderViewController: AnnotationToolbarHandlerDelegate {
    var isNavigationBarHidden: Bool {
        self.navigationController?.navigationBar.isHidden ?? false
    }
    
    var isSidebarHidden: Bool {
        !self.isSidebarVisible
    }

    var toolbarLeadingAnchor: NSLayoutXAxisAnchor {
        return self.sidebarController.view.trailingAnchor
    }

    var toolbarLeadingSafeAreaAnchor: NSLayoutXAxisAnchor {
        return self.view.safeAreaLayoutGuide.leadingAnchor
    }

    var containerView: UIView {
        return self.view
    }

    var documentView: UIView {
        return self.documentController.view
    }

    func layoutIfNeeded() {
        self.view.layoutIfNeeded()
    }

    func setNeedsLayout() {
        self.view.setNeedsLayout()
    }

    func setNavigationBar(hidden: Bool, animated: Bool) {
        self.navigationController?.setNavigationBarHidden(hidden, animated: animated)
    }
    
    func setNavigationBar(alpha: CGFloat) {
        self.navigationController?.navigationBar.alpha = alpha
    }
    
    func topDidChange(forToolbarState state: AnnotationToolbarHandler.State) {
        let (statusBarOffset, _, totalOffset) = self.annotationToolbarHandler.topOffsets(statusBarVisible: self.statusBarVisible)

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

    func hideSidebarIfNeeded(forPosition position: AnnotationToolbarHandler.State.Position, isToolbarSmallerThanMinWidth: Bool, animated: Bool) {
        guard self.isSidebarVisible && (position == .pinned || (position == .top && isToolbarSmallerThanMinWidth)) else { return }
        self.toggleSidebar(animated: animated)
    }

    func setDocumentInterface(hidden: Bool) {
        self.documentController.setInterface(hidden: hidden)
    }

    func updateStatusBar() {
        self.navigationController?.setNeedsStatusBarAppearanceUpdate()
        self.setNeedsStatusBarAppearanceUpdate()
    }
}

extension PDFReaderViewController: AnnotationToolbarDelegate {
    func closeAnnotationToolbar() {
        (self.toolbarButton.customView as? CheckboxButton)?.isSelected = false
        self.annotationToolbarHandler.set(hidden: true, animated: true)
    }

    var activeAnnotationTool: AnnotationTool? {
        return self.documentController.pdfController?.annotationStateManager.state?.toolbarTool
    }

    var maxAvailableToolbarSize: CGFloat {
        guard self.toolbarState.visible, let documentController = self.documentController else { return 0 }

        switch self.toolbarState.position {
        case .top, .pinned:
            return self.isCompactWidth ? documentController.view.frame.size.width : (documentController.view.frame.size.width - (2 * AnnotationToolbarHandler.toolbarFullInsetInset))

        case .trailing, .leading:
            let window = (view.scene as? UIWindowScene)?.windows.first(where: \.isKeyWindow)
            let topInset = window?.safeAreaInsets.top ?? 0
            let bottomInset = window?.safeAreaInsets.bottom ?? 0
            let interfaceIsHidden = self.navigationController?.isNavigationBarHidden ?? false
            return self.view.frame.size.height - (2 * AnnotationToolbarHandler.toolbarCompactInset) - (interfaceIsHidden ? 0 : (topInset + documentController.scrubberBarHeight)) - bottomInset
        }
    }

    func toggle(tool: AnnotationTool, options: AnnotationToolOptions) {
        let pspdfkitTool = tool.pspdfkitTool
        let color = self.viewModel.state.toolColors[pspdfkitTool]
        self.documentController.toggle(annotationTool: pspdfkitTool, color: color, tappedWithStylus: (options == .stylus))
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
        if let state = oldState?.toolbarTool {
            self.annotationToolbarController.set(selected: false, to: state, color: nil)
        }

        if let state = newState {
            let color = self.viewModel.state.toolColors[state]
            if let tool = state.toolbarTool {
                self.annotationToolbarController.set(selected: true, to: tool, color: color)
            }
        }
    }

    func didChange(undoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        self.annotationToolbarController.didChange(undoState: undoEnabled, redoState: redoEnabled)
    }

    func interfaceVisibilityDidChange(to isHidden: Bool) {
        let shouldChangeNavigationBarVisibility = !self.toolbarState.visible || self.toolbarState.position != .pinned

        if !isHidden && shouldChangeNavigationBarVisibility && self.navigationController?.navigationBar.isHidden == true {
            self.navigationController?.setNavigationBarHidden(false, animated: false)
            self.navigationController?.navigationBar.alpha = 0
        }

        self.statusBarVisible = !isHidden
        self.annotationToolbarHandler.interfaceVisibilityDidChange()

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

extension PDFReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let longPressRecognizer = gestureRecognizer as? UILongPressGestureRecognizer else { return true }

        let location = longPressRecognizer.location(in: self.annotationToolbarController.view)
        let currentLocation: CGFloat
        let border: CGFloat

        switch self.toolbarState.position {
        case .pinned, .top:
            currentLocation = location.x
            border = self.annotationToolbarController.view.frame.width - AnnotationToolbarHandler.annotationToolbarDragHandleHeight

        case .leading, .trailing:
            currentLocation = location.y
            border = self.annotationToolbarController.view.frame.height - AnnotationToolbarHandler.annotationToolbarDragHandleHeight
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

extension PSPDFKit.Annotation.Tool {
    fileprivate var toolbarTool: AnnotationTool? {
        switch self {
        case .eraser:
            return .eraser

        case .highlight:
            return .highlight

        case .square:
            return .image

        case .ink:
            return .ink

        case .note:
            return .note

        default:
            return nil
        }
    }
}

extension AnnotationTool {
    fileprivate var pspdfkitTool: PSPDFKit.Annotation.Tool {
        switch self {
        case .eraser:
            return .eraser

        case .highlight:
            return .highlight

        case .image:
            return .square

        case .ink:
            return .ink

        case .note:
            return .note
        }
    }
}
