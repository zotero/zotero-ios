//
//  HtmlEpubReaderViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24.08.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

protocol HtmlEpubReaderContainerDelegate: AnyObject {
    var statusBarHeight: CGFloat { get }
    var navigationBarHeight: CGFloat { get }
    var isSidebarVisible: Bool { get }

    func show(url: URL)
    func toggleInterfaceVisibility()
}

class HtmlEpubReaderViewController: UIViewController, ReaderViewController, ParentWithSidebarController {
    typealias DocumentController = HtmlEpubDocumentViewController
    typealias SidebarController = HtmlEpubSidebarViewController

    private enum NavigationBarButton: Int {
        case sidebar = 7
    }

    private let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    let disposeBag: DisposeBag

    weak var documentController: HtmlEpubDocumentViewController?
    weak var documentControllerLeft: NSLayoutConstraint?
    private var documentTopConstraintFullscreen: NSLayoutConstraint!
    weak var annotationToolbarController: AnnotationToolbarViewController?
    var annotationToolbarHandler: AnnotationToolbarHandler?
    weak var sidebarController: HtmlEpubSidebarViewController?
    weak var sidebarControllerLeft: NSLayoutConstraint?
    var navigationBarHeight: CGFloat {
        return self.navigationController?.navigationBar.frame.height ?? 0.0
    }
    private(set) var isCompactWidth: Bool
    var statusBarHeight: CGFloat
    var key: String { return viewModel.state.key }
    
    weak var coordinatorDelegate: HtmlEpubReaderCoordinatorDelegate?
    @CodableUserDefault(
        key: "HtmlEpubReaderToolbarState",
        defaultValue: AnnotationToolbarHandler.State(position: .leading, visible: true),
        encoder: Defaults.jsonEncoder,
        decoder: Defaults.jsonDecoder
    )
    var toolbarState: AnnotationToolbarHandler.State
    @UserDefault(key: "HtmlEpubReaderStatusBarVisible", defaultValue: true)
    var statusBarVisible: Bool {
        didSet {
            (self.navigationController as? NavigationViewController)?.statusBarVisible = self.statusBarVisible
        }
    }
    var isSidebarVisible: Bool { return self.sidebarControllerLeft?.constant == 0 }
    var isDocumentLocked: Bool { return false }
    private(set) var activeAnnotationTool: AnnotationTool?
    lazy var toolbarButton: UIBarButtonItem = {
        return createToolbarButton()
    }()
    private lazy var settingsButton: UIBarButtonItem = {
        let settings = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: nil, action: nil)
        settings.accessibilityLabel = L10n.Accessibility.Pdf.settings
        settings.title = L10n.Accessibility.Pdf.settings
        settings.rx.tap
            .subscribe(onNext: { [weak self, weak settings] _ in
                guard let self, let settings else { return }
                showSettings(sender: settings)
            })
            .disposed(by: disposeBag)
        return settings
    }()
    
    private lazy var typesettingButton: UIBarButtonItem = {
        let typesetting = UIBarButtonItem(image: UIImage(systemName: "textformat.size"), style: .plain, target: nil, action: nil)
        typesetting.accessibilityLabel = "Typesetting"
        typesetting.title = "Typesetting"
        typesetting.rx.tap
            .subscribe(onNext: { [weak self] _ in
                guard let self else { return }
                showTypesettingMenu()
            })
            .disposed(by: disposeBag)
        return typesetting
    }()
    private lazy var searchButton: UIBarButtonItem = {
        let search = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: nil, action: nil)
        search.accessibilityLabel = L10n.Accessibility.Pdf.searchPdf
        search.title = viewModel.state.originalFile.ext.lowercased() == "epub" ? L10n.Accessibility.Htmlepub.searchEpub : L10n.Accessibility.Htmlepub.searchHtml
        search.rx.tap
            .subscribe(onNext: { [weak self] _ in
                guard let self, let documentController else { return }
                coordinatorDelegate?.showSearch(viewModel: viewModel, documentController: documentController, text: nil, sender: searchButton, userInterfaceStyle: viewModel.state.interfaceStyle)
            })
            .disposed(by: disposeBag)
        return search
    }()

    // MARK: - Lifecycle

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>, compactSize: Bool) {
        self.viewModel = viewModel
        isCompactWidth = compactSize
        disposeBag = DisposeBag()
        statusBarHeight = UIApplication
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

        setActivity()
        viewModel.process(action: .changeIdleTimerDisabled(true))
        view.backgroundColor = .clear
        observeViewModel()
        setupNavigationBar()
        setupViews()
        updateInterface(to: viewModel.state.settings)
        navigationItem.rightBarButtonItems = createRightBarButtonItems()

        func observeViewModel() {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] state in
                    self?.process(state: state)
                })
                .disposed(by: disposeBag)
        }

        func setupNavigationBar() {
            let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
            closeButton.title = L10n.close
            closeButton.accessibilityLabel = L10n.close
            closeButton.rx.tap.subscribe(onNext: { [weak self] _ in self?.close() }).disposed(by: disposeBag)

            let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"), style: .plain, target: nil, action: nil)
            setupAccessibility(forSidebarButton: sidebarButton)
            sidebarButton.tag = NavigationBarButton.sidebar.rawValue
            sidebarButton.rx.tap.subscribe(onNext: { [weak self] _ in self?.toggleSidebar(animated: true) }).disposed(by: disposeBag)

            navigationItem.leftBarButtonItems = [closeButton, sidebarButton]
        }

        func setupViews() {
            let documentController = HtmlEpubDocumentViewController(viewModel: viewModel)
            documentController.parentDelegate = self
            documentController.view.translatesAutoresizingMaskIntoConstraints = false

            let annotationToolbar = AnnotationToolbarViewController(tools: Defaults.shared.htmlEpubAnnotationTools.map({ $0.type }), undoRedoEnabled: false, size: navigationBarHeight)
            annotationToolbar.delegate = self

            let sidebarController = HtmlEpubSidebarViewController(viewModel: viewModel)
            sidebarController.parentDelegate = self
            sidebarController.coordinatorDelegate = coordinatorDelegate
            sidebarController.view.translatesAutoresizingMaskIntoConstraints = false

            let separator = UIView()
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.backgroundColor = Asset.Colors.annotationSidebarBorderColor.color

            add(controller: documentController)
            add(controller: annotationToolbar)
            add(controller: sidebarController)
            view.addSubview(documentController.view)
            view.addSubview(annotationToolbar.view)
            view.addSubview(sidebarController.view)
            view.addSubview(separator)

            let documentLeftConstraint = documentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            let sidebarLeftConstraint = sidebarController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -PDFReaderLayout.sidebarWidth)
            
            // Create both top constraints for Option 2B: Dynamic constraint swapping
            let documentTopConstraintFullscreen = documentController.view.topAnchor.constraint(equalTo: view.topAnchor)
            documentTopConstraintFullscreen.isActive = true

            NSLayoutConstraint.activate([
                documentController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                documentController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                documentLeftConstraint,
                sidebarController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                sidebarController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                sidebarController.view.widthAnchor.constraint(equalToConstant: PDFReaderLayout.sidebarWidth),
                sidebarLeftConstraint,
                separator.widthAnchor.constraint(equalToConstant: PDFReaderLayout.separatorWidth),
                separator.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor),
                separator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                separator.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            self.documentController = documentController
            self.sidebarController = sidebarController
            annotationToolbarController = annotationToolbar
            documentControllerLeft = documentLeftConstraint
            sidebarControllerLeft = sidebarLeftConstraint
            self.documentTopConstraintFullscreen = documentTopConstraintFullscreen
            annotationToolbarHandler = AnnotationToolbarHandler(controller: annotationToolbar, delegate: self)
            annotationToolbarHandler!.performInitialLayout()

            func add(controller: UIViewController) {
                controller.willMove(toParent: self)
                addChild(controller)
                controller.didMove(toParent: self)
            }
        }

        func setActivity() {
            let kind: OpenItem.Kind
            switch viewModel.state.documentFile.ext.lowercased() {
            case "epub":
                kind = .epub(libraryId: viewModel.state.library.identifier, key: viewModel.state.key)

            case "html", "htm":
                kind = .html(libraryId: viewModel.state.library.identifier, key: viewModel.state.key)

            default:
                return
            }
            let openItem = OpenItem(kind: kind, userIndex: 0)
            set(userActivity: .contentActivity(with: [openItem], libraryId: viewModel.state.library.identifier, collectionId: Defaults.shared.selectedCollectionId).set(title: viewModel.state.title))
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        annotationToolbarHandler?.viewIsAppearing(editingEnabled: viewModel.state.library.metadataEditable)
        updateWebViewTransform()
    }

    deinit {
        viewModel.process(action: .changeIdleTimerDisabled(false))
        viewModel.process(action: .deinitialiseReader)
        DDLogInfo("HtmlEpubReaderViewController deinitialized")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let documentController else { return }
        if documentController.view.frame.width < AnnotationToolbarHandler.minToolbarWidth && toolbarState.visible && toolbarState.position == .top {
            closeAnnotationToolbar()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        isCompactWidth = UIDevice.current.isCompactWidth(size: size)

        guard viewIfLoaded != nil else { return }

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            statusBarHeight = view.safeAreaInsets.top - (navigationController?.isNavigationBarHidden == true ? 0 : navigationBarHeight)
            annotationToolbarHandler?.viewWillTransitionToNewSize()
            updateWebViewTransform()
        }, completion: nil)
    }

    override var prefersStatusBarHidden: Bool {
        return !statusBarVisible
    }

    // MARK: - State

    private func process(state: HtmlEpubReaderState) {
        if let error = state.error {
            coordinatorDelegate?.show(error: error)
        }

        if state.changes.contains(.toolColor), let color = state.activeTool.flatMap({ state.toolColors[$0] }) {
            annotationToolbarController?.set(activeColor: color)
        }

        if state.changes.contains(.activeTool) {
            select(activeTool: state.activeTool)
        }

        if state.changes.contains(.appearance) {
            updateInterface(to: state.settings)
        }

        if state.changes.contains(.md5) {
            coordinatorDelegate?.showDocumentChangedAlert { [weak self] in
                self?.close()
            }
            return
        }

        if state.changes.contains(.library) {
            let hidden = !state.library.metadataEditable || !toolbarState.visible
            annotationToolbarHandler?.set(hidden: hidden, animated: true)
            (toolbarButton.customView as? CheckboxButton)?.isSelected = toolbarState.visible
            navigationItem.rightBarButtonItems = createRightBarButtonItems()
        }

        if state.changes.contains(.popover) {
            if let key = state.annotationPopoverKey, let rect = state.annotationPopoverRect {
                showPopover(forKey: key, rect: rect)
            } else {
                hidePopover()
            }
        }

        func select(activeTool tool: AnnotationTool?) {
            if let tool = activeAnnotationTool {
                annotationToolbarController?.set(selected: false, to: tool, color: nil)
                activeAnnotationTool = nil
            }

            if let tool {
                let color = viewModel.state.toolColors[tool]
                annotationToolbarController?.set(selected: true, to: tool, color: color)
                activeAnnotationTool = tool
            }
        }

        func showPopover(forKey key: String, rect: CGRect) {
            guard !isSidebarVisible else { return }
            let observable = coordinatorDelegate?.showAnnotationPopover(
                state: viewModel.state,
                sourceRect: rect,
                popoverDelegate: self,
                userInterfaceStyle: viewModel.state.settings.appearance.userInterfaceStyle
            )
            observe(key: key, popoverObservable: observable)
        }

        func hidePopover() {
            guard navigationController?.presentedViewController is AnnotationPopover ||
                  (navigationController?.presentedViewController as? UINavigationController)?.topViewController is AnnotationPopover
            else { return }
            navigationController?.dismiss(animated: true)
        }

        func observe(key: String, popoverObservable observable: PublishSubject<AnnotationPopoverState>?) {
            guard let observable else { return }
            observable.subscribe { [weak self] state in
                guard let self else { return }
                if state.changes.contains(.color) {
                    viewModel.process(action: .setColor(key: key, color: state.color))
                }
                if state.changes.contains(.comment) {
                    viewModel.process(action: .setComment(key: key, comment: state.comment))
                }
                if state.changes.contains(.deletion) {
                    viewModel.process(action: .removeAnnotation(key))
                }
                if state.changes.contains(.tags) {
                    viewModel.process(action: .setTags(key: key, tags: state.tags))
                }
                if state.changes.contains(.pageLabel) || state.changes.contains(.highlight) || state.changes.contains(.type) {
                    viewModel.process(action:
                        .updateAnnotationProperties(
                            key: key,
                            type: state.type,
                            color: state.color,
                            lineWidth: state.lineWidth,
                            pageLabel: state.pageLabel,
                            updateSubsequentLabels: state.updateSubsequentLabels,
                            highlightText: state.highlightText
                        )
                    )
                }
            }
            .disposed(by: disposeBag)
        }
    }

    // MARK: - Actions

    private func updateInterface(to settings: HtmlEpubSettings) {
        switch settings.appearance {
        case .automatic:
            navigationController?.overrideUserInterfaceStyle = .unspecified

        case .light, .sepia:
            navigationController?.overrideUserInterfaceStyle = .light

        case .dark:
            navigationController?.overrideUserInterfaceStyle = .dark
        }

        let appearance = Appearance.from(appearanceMode: settings.appearance, interfaceStyle: viewModel.state.interfaceStyle)
        switch appearance {
        case .light:
            view.backgroundColor = .white

        case .sepia:
            view.backgroundColor = UIColor(red: 0.98, green: 0.95, blue: 0.89, alpha: 1.0)

        case .dark:
            view.backgroundColor = .black
        }
    }

    private func toggleSidebar(animated: Bool) {
        toggleSidebar(animated: animated, sidebarButtonTag: NavigationBarButton.sidebar.rawValue)
    }

    private func showSettings(sender: UIBarButtonItem) {
        guard let viewModel = coordinatorDelegate?.showSettings(with: viewModel.state.settings, sender: sender) else { return }
        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                guard let self else { return }
                let settings = HtmlEpubSettings(
                    appearance: state.appearance,
                    typesetting: self.viewModel.state.settings.typesetting,
                    customFont: self.viewModel.state.settings.customFont
                )
                self.viewModel.process(action: .setSettings(settings))
            })
            .disposed(by: disposeBag)
    }

    private func close() {
        navigationController?.presentingViewController?.dismiss(animated: true)
    }

    private func createRightBarButtonItems() -> [UIBarButtonItem] {
        var buttons = [settingsButton, searchButton, typesettingButton]
        if viewModel.state.library.metadataEditable {
            buttons.append(toolbarButton)
        }
        return buttons
    }
    
    // MARK: - Font & Typesetting
    
    private func showFontManagement() {
        let fontVC = FontManagementViewController(documentKey: viewModel.state.key)
        fontVC.delegate = self
        let navController = UINavigationController(rootViewController: fontVC)
        navigationController?.present(navController, animated: true)
    }
    
    private func showTypesettingMenu() {
        let settings = FontManager.shared.typesettingSettings(forDocument: viewModel.state.key)
        let typesettingVC = TypesettingMenuViewController(settings: settings, documentKey: viewModel.state.key)
        typesettingVC.delegate = self
        let navController = UINavigationController(rootViewController: typesettingVC)
        
        // Hide navigation bar to save space
        navController.navigationBar.isHidden = true
        
        // Configure as popover with 60% screen height and no dimming
        navController.modalPresentationStyle = .pageSheet
        if let sheet = navController.sheetPresentationController {
            let screenHeight = UIScreen.main.bounds.height
            let detent = UISheetPresentationController.Detent.custom { _ in
                return screenHeight * 0.6
            }
            sheet.detents = [detent]
            sheet.prefersGrabberVisible = false
            sheet.largestUndimmedDetentIdentifier = detent.identifier
        }
        
        navigationController?.present(navController, animated: true)
    }
    
    private func applyCurrentTypesettingSettings() {
        guard let documentController, let webView = documentController.webView else {
            DDLogWarn("HtmlEpubReaderViewController: Cannot apply typesetting - documentController or webView is nil")
            return
        }
        
        DDLogInfo("HtmlEpubReaderViewController: Applying current typesetting settings for document \(viewModel.state.key)")
        
        let fontManager = FontManager.shared
        let settings = fontManager.typesettingSettings(forDocument: viewModel.state.key)
        
        // Apply custom font if set
        var appliedSettings = settings
        if let customFontFamily = fontManager.font(forDocument: viewModel.state.key) {
            DDLogInfo("HtmlEpubReaderViewController: Using custom font: \(customFontFamily)")
            appliedSettings.fontFamily = customFontFamily
        } else {
            DDLogInfo("HtmlEpubReaderViewController: No custom font set, using default: \(appliedSettings.fontFamily ?? "system")")
        }
        
        // Apply settings to web view
        TypesettingApplicator.applySettings(
            appliedSettings,
            appearance: viewModel.state.settings.appearance,
            to: webView
        )
        
        // Update HtmlEpubSettings
        let updatedSettings = HtmlEpubSettings(
            appearance: viewModel.state.settings.appearance,
            typesetting: appliedSettings,
            customFont: fontManager.font(forDocument: viewModel.state.key)
        )
        viewModel.process(action: .setSettings(updatedSettings))
    }
}

extension HtmlEpubReaderViewController: AnnotationToolbarHandlerDelegate {
    var additionalToolbarInsets: NSDirectionalEdgeInsets {
        let leading = isSidebarVisible ? (documentControllerLeft?.constant ?? 0) : 0
        // With safeAreaLayoutGuide, top inset is always 0 since the view starts at safe area
        return NSDirectionalEdgeInsets(top: 0, leading: leading, bottom: 0, trailing: 0)
    }

    var isNavigationBarHidden: Bool {
        navigationController?.navigationBar.isHidden ?? false
    }

    var containerView: UIView {
        return view
    }

    func layoutIfNeeded() {
        view.layoutIfNeeded()
    }

    func setNeedsLayout() {
        view.setNeedsLayout()
    }

    func hideSidebarIfNeeded(forPosition position: AnnotationToolbarHandler.State.Position, isToolbarSmallerThanMinWidth: Bool, animated: Bool) {
        guard isSidebarVisible && (position == .pinned || (position == .top && isToolbarSmallerThanMinWidth)) else { return }
        toggleSidebar(animated: animated)
    }

    func setNavigationBar(hidden: Bool, animated: Bool) {
        navigationController?.setNavigationBarHidden(hidden, animated: animated)
    }

    func setNavigationBar(alpha: CGFloat) {
        navigationController?.navigationBar.alpha = alpha
    }

    func setDocumentInterface(hidden: Bool) {
    }
    
    func annotationToolbarWillChange(state: AnnotationToolbarHandler.State, statusBarVisible: Bool) {
    }

    func topDidChange(forToolbarState state: AnnotationToolbarHandler.State) {
        view.layoutIfNeeded()
    }

    func updateStatusBar() {
        navigationController?.setNeedsStatusBarAppearanceUpdate()
        setNeedsStatusBarAppearanceUpdate()
    }
}

extension HtmlEpubReaderViewController: AnnotationToolbarDelegate {
    var rotation: AnnotationToolbarViewController.Rotation {
        return .horizontal
    }

    var canUndo: Bool {
        return false
    }

    var canRedo: Bool {
        return false
    }

    var maxAvailableToolbarSize: CGFloat {
        return view.frame.width
    }

    func toggle(tool: AnnotationTool, options: AnnotationToolOptions) {
        viewModel.process(action: .toggleTool(tool))
    }

    func showToolOptions(sourceItem: UIPopoverPresentationControllerSourceItem) {
        guard let tool = viewModel.state.activeTool else { return }
        let colorHex = viewModel.state.toolColors[tool]?.hexString

        coordinatorDelegate?.showToolSettings(
            tool: tool,
            colorHex: colorHex,
            sizeValue: nil,
            sourceItem: sourceItem,
            userInterfaceStyle: viewModel.state.settings.appearance.userInterfaceStyle
        ) { [weak self] newColor, newSize in
            self?.viewModel.process(action: .setToolOptions(color: newColor, size: newSize.flatMap(CGFloat.init), tool: tool))
        }
    }

    func performUndo() {
    }

    func performRedo() {
    }
}

extension HtmlEpubReaderViewController: UIPopoverPresentationControllerDelegate {
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        viewModel.process(action: .deselectSelectedAnnotation)
    }
}

extension HtmlEpubReaderViewController: HtmlEpubReaderContainerDelegate {
    func show(url: URL) {
        coordinatorDelegate?.show(url: url)
    }

    private func updateWebViewTransform() {
        let isHidden = navigationController?.navigationBar.isHidden ?? false
        let offset: CGFloat = isHidden ? 0 : (navigationController?.navigationBar.frame.maxY ?? 0)
        documentController?.webView?.transform = offset == 0 ? .identity : CGAffineTransform(translationX: 0, y: offset)
    }

    func toggleInterfaceVisibility() {
        let isHidden = !(navigationController?.navigationBar.isHidden ?? false)
        let shouldChangeNavigationBarVisibility = !toolbarState.visible || toolbarState.position != .pinned

        if !isHidden && shouldChangeNavigationBarVisibility && navigationController?.navigationBar.isHidden == true {
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.navigationBar.alpha = 0
        }

        statusBarVisible = !isHidden
        annotationToolbarHandler?.interfaceVisibilityDidChange()

        if shouldChangeNavigationBarVisibility {
            // Calculate the target transform BEFORE hiding the nav bar (so frame.maxY is valid)
            let targetOffset: CGFloat = isHidden ? 0 : (navigationController?.navigationBar.frame.maxY ?? 0)

            UIView.animate(withDuration: 0.2) {
                self.updateStatusBar()
                self.navigationController?.navigationBar.alpha = isHidden ? 0 : 1
                self.navigationController?.setNavigationBarHidden(isHidden, animated: false)
                // Shift WebView content visually without changing its size (no reflow)
                self.documentController?.webView?.transform = targetOffset == 0 ? .identity : CGAffineTransform(translationX: 0, y: targetOffset)
                self.view.layoutIfNeeded()
            }
        } else {
            UIView.animate(withDuration: 0.15) { [weak self] in
                guard let self else { return }
                updateStatusBar()
                view.layoutIfNeeded()
            }
        }

        if isHidden && isSidebarVisible {
            toggleSidebar(animated: true)
        }
    }
}

extension HtmlEpubReaderViewController: ReaderAnnotationsDelegate {
    func parseAndCacheIfNeededAttributedText(for annotation: ReaderAnnotation, with font: UIFont) -> NSAttributedString? {
        guard let text = annotation.text, !text.isEmpty else { return nil }

        if let attributedText = viewModel.state.texts[annotation.key]?.1[font] {
            return attributedText
        }

        viewModel.process(action: .parseAndCacheText(key: annotation.key, text: text, font: font))
        return viewModel.state.texts[annotation.key]?.1[font]
    }

    func parseAndCacheIfNeededAttributedComment(for annotation: ReaderAnnotation) -> NSAttributedString? {
        let comment = annotation.comment
        guard !comment.isEmpty else { return nil }

        if let attributedComment = viewModel.state.comments[annotation.key] {
            return attributedComment
        }

        viewModel.process(action: .parseAndCacheComment(key: annotation.key, comment: comment))
        return viewModel.state.comments[annotation.key]
    }
}

extension HtmlEpubReaderViewController: HtmlEpubSidebarDelegate {
    func tableOfContentsSelected(location: [String: Any]) {
        documentController?.show(location: location)
        if isSidebarVisible && sidebarController?.view.frame.width == view.frame.width {
            toggleSidebar(animated: true)
        }
    }
}

// MARK: - FontManagementDelegate

extension HtmlEpubReaderViewController: FontManagementDelegate {
    func fontManagementDidSelectFont(_ font: FontMetadata?, forDocument documentKey: String?) {
        applyCurrentTypesettingSettings()
    }
    
    func fontManagementDidUpdateSettings() {
        applyCurrentTypesettingSettings()
    }
}

// MARK: - TypesettingMenuDelegate

extension HtmlEpubReaderViewController: TypesettingMenuDelegate {
    func typesettingMenuDidUpdateSettings(_ settings: TypesettingSettings) {
        applyCurrentTypesettingSettings()
    }
}
