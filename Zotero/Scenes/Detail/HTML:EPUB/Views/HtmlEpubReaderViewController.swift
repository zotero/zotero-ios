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
    var containerTopInset: CGFloat { get }
    var isSidebarVisible: Bool { get }

    func show(url: URL)
    func toggleInterfaceVisibility()
    func setReaderBackground(color: UIColor)
}

class HtmlEpubReaderViewController: UIViewController, ReaderViewController {
    typealias DocumentController = HtmlEpubDocumentViewController
    typealias SidebarController = HtmlEpubSidebarViewController

    private enum NavigationBarButton: Int {
        case sidebar = 7
    }

    private let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    private unowned let dbStorage: DbStorage
    private unowned let documentWorkerController: DocumentWorkerController
    private unowned let remoteVoicesController: RemoteVoicesController
    private var readAloudHandler: ReadAloudViewHandler<HtmlEpubReaderViewController>?
    private weak var speechHighlighterTopConstraint: NSLayoutConstraint?
    let disposeBag: DisposeBag

    weak var documentController: HtmlEpubDocumentViewController?
    private weak var documentControllerTop: NSLayoutConstraint!
    weak var documentControllerLeft: NSLayoutConstraint?
    private weak var pageIndicator: UIView?
    private weak var pageIndicatorLabel: UILabel?
    private var documentBottomToSafeArea: NSLayoutConstraint?
    private var documentBottomToIndicator: NSLayoutConstraint?
    private var documentBottomToView: NSLayoutConstraint?
    private var pageIndicatorBottom: NSLayoutConstraint?
    weak var annotationToolbarController: AnnotationToolbarViewController?
    var annotationToolbarHandler: AnnotationToolbarHandler?
    weak var sidebarController: HtmlEpubSidebarViewController?
    weak var sidebarControllerLeft: NSLayoutConstraint?
    var navigationBarHeight: CGFloat {
        return self.navigationController?.navigationBar.frame.height ?? 0.0
    }
    private(set) var isCompactWidth: Bool
    var navigationBarLeadingItems: [UIBarButtonItem] = []
    var navigationBarTrailingFixedItems: [UIBarButtonItem] = []
    var navigationBarOverflowItems: [UIBarButtonItem] = []
    var statusBarHeight: CGFloat
    private var lastLayoutSize: CGSize?
    private var lastContainerInsets: NSDirectionalEdgeInsets?
    private var isChangingInterfaceVisibility: Bool
    var containerTopInset: CGFloat {
        return lastContainerInsets?.top ?? currentContainerInsets().top
    }
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
    private lazy var searchButton: UIBarButtonItem = {
        let search = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: nil, action: nil)
        search.accessibilityLabel = L10n.Accessibility.Pdf.searchPdf
        search.title = viewModel.state.originalFile.ext.lowercased() == "epub" ? L10n.Accessibility.Htmlepub.searchEpub : L10n.Accessibility.Htmlepub.searchHtml
        search.rx.tap
            .subscribe(onNext: { [weak self] _ in
                guard let self, let documentController else { return }
                coordinatorDelegate?.showSearch(
                    viewModel: viewModel,
                    documentController: documentController,
                    text: nil,
                    sender: searchButton,
                    userInterfaceStyle: presentedUserInterfaceStyle(for: viewModel.state.settings.appearance)
                )
            })
            .disposed(by: disposeBag)
        return search
    }()

    // MARK: - Lifecycle

    init(
        viewModel: ViewModel<HtmlEpubReaderActionHandler>,
        compactSize: Bool,
        dbStorage: DbStorage,
        documentWorkerController: DocumentWorkerController,
        remoteVoicesController: RemoteVoicesController
    ) {
        self.viewModel = viewModel
        self.dbStorage = dbStorage
        self.documentWorkerController = documentWorkerController
        self.remoteVoicesController = remoteVoicesController
        isCompactWidth = compactSize
        disposeBag = DisposeBag()
        isChangingInterfaceVisibility = false
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
        view.backgroundColor = .systemBackground
        observeViewModel()
        setupNavigationBar()
        setupViews()
        setupReadAloudIfNeeded()
        updateInterface(to: viewModel.state.settings)
        updateNavigationBarTrailingItems()

        func setupReadAloudIfNeeded() {
            guard FeatureGates.enabled.contains(.speech), let documentController else { return }
            let handler = ReadAloudViewHandler(
                key: viewModel.state.key,
                libraryId: viewModel.state.library.identifier,
                viewController: self,
                documentContainer: documentController.view,
                delegate: self,
                dbStorage: dbStorage,
                remoteVoicesController: remoteVoicesController,
                documentWorkerController: documentWorkerController
            )
            handler.delegate = self
            readAloudHandler = handler
            navigationBarLeadingItems.append(handler.createReadAloudButton(isSelected: false))
        }

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

            navigationBarLeadingItems = [closeButton, sidebarButton]
        }

        func setupViews() {
            let documentController = HtmlEpubDocumentViewController(viewModel: viewModel)
            documentController.parentDelegate = self
            documentController.view.translatesAutoresizingMaskIntoConstraints = false

            let annotationToolbar = AnnotationToolbarViewController(tools: Defaults.shared.htmlEpubAnnotationTools.map({ $0.type }), undoRedoEnabled: false, size: navigationBarHeight)
            annotationToolbar.delegate = self

            let pageIndicator = UIView()
            pageIndicator.translatesAutoresizingMaskIntoConstraints = false
            pageIndicator.backgroundColor = .systemGray6
            pageIndicator.layer.cornerRadius = 6
            pageIndicator.layer.masksToBounds = true
            pageIndicator.alpha = 0
            let pageIndicatorLabel = UILabel()
            pageIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
            pageIndicatorLabel.textColor = .label
            pageIndicatorLabel.font = .preferredFont(forTextStyle: .body)
            pageIndicatorLabel.textAlignment = .center
            pageIndicator.addSubview(pageIndicatorLabel)

            add(controller: documentController)
            add(controller: annotationToolbar)
            view.addSubview(documentController.view)
            view.addSubview(annotationToolbar.view)
            view.addSubview(pageIndicator)

            let documentLeftConstraint = documentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            let documentTopConstraint = documentController.view.topAnchor.constraint(equalTo: view.topAnchor)
            let documentBottomToSafeArea = view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: documentController.view.bottomAnchor)
            let documentBottomToIndicator = pageIndicator.topAnchor.constraint(equalTo: documentController.view.bottomAnchor, constant: 8)
            let documentBottomToView = view.bottomAnchor.constraint(equalTo: documentController.view.bottomAnchor)
            let pageIndicatorBottom = view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: pageIndicator.bottomAnchor, constant: 0)

            NSLayoutConstraint.activate([
                documentTopConstraint,
                documentBottomToSafeArea,
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: documentController.view.trailingAnchor),
                documentLeftConstraint,
                pageIndicator.centerXAnchor.constraint(equalTo: documentController.view.centerXAnchor),
                pageIndicatorBottom,
                pageIndicatorLabel.topAnchor.constraint(equalTo: pageIndicator.topAnchor, constant: 6),
                pageIndicator.bottomAnchor.constraint(equalTo: pageIndicatorLabel.bottomAnchor, constant: 6),
                pageIndicatorLabel.leadingAnchor.constraint(equalTo: pageIndicator.leadingAnchor, constant: 12),
                pageIndicator.trailingAnchor.constraint(equalTo: pageIndicatorLabel.trailingAnchor, constant: 12)
            ])

            self.documentController = documentController
            annotationToolbarController = annotationToolbar
            documentControllerTop = documentTopConstraint
            documentControllerLeft = documentLeftConstraint
            self.pageIndicator = pageIndicator
            self.pageIndicatorLabel = pageIndicatorLabel
            self.documentBottomToSafeArea = documentBottomToSafeArea
            self.documentBottomToIndicator = documentBottomToIndicator
            self.documentBottomToView = documentBottomToView
            self.pageIndicatorBottom = pageIndicatorBottom
            annotationToolbarHandler = AnnotationToolbarHandler(controller: annotationToolbar, delegate: self)
            annotationToolbarHandler!.performInitialLayout()
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
        updateContainerInsets(force: true)
        applyNavigationBarButtons(windowSize: windowSize)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Confirm any in-progress read-aloud highlight session, matching the PDF reader behaviour when leaving the screen.
        readAloudHandler?.confirmActiveHighlightSession()
    }

    deinit {
        viewModel.process(action: .changeIdleTimerDisabled(false))
        viewModel.process(action: .deinitialiseReader)
        DDLogInfo("HtmlEpubReaderViewController deinitialized")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let layoutSize = view.bounds.size
        let isSizeChange = lastLayoutSize != layoutSize
        lastLayoutSize = layoutSize
        updateStatusBarHeight(allowZero: isSizeChange)
        if isSizeChange || !isChangingInterfaceVisibility || isTopToolbarVisible(forToolbarState: toolbarState) {
            updateContainerInsets()
        }

        guard let documentController else { return }

        if documentController.view.frame.width < AnnotationToolbarHandler.minToolbarWidth && toolbarState.visible && toolbarState.position == .top {
            closeAnnotationToolbar()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        viewModel.process(action: .userInterfaceStyleChanged(currentSystemUserInterfaceStyle))
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        isCompactWidth = UIDevice.current.isCompactWidth(size: size)

        guard viewIfLoaded != nil else { return }

        applyNavigationBarButtons(windowSize: size)

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            updateStatusBarHeight(allowZero: true)
            annotationToolbarHandler?.viewWillTransitionToNewSize()
            updateContainerInsets(force: true)
        }, completion: { [weak self] _ in
            guard let self else { return }
            updateStatusBarHeight(allowZero: true)
            updateContainerInsets(force: true)
        })
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
            toolbarButton.checkboxButton?.isSelected = toolbarState.visible
            updateNavigationBarTrailingItems()
            applyNavigationBarButtons(windowSize: windowSize)
        }

        if state.changes.contains(.pages) {
            updatePageIndicator(from: state)
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

    private func updatePageIndicator(from state: HtmlEpubReaderState) {
        if let page = state.currentPage, let pagesCount = state.pagesCount {
            pageIndicatorLabel?.text = "\(page.label) of \(pagesCount)"
        }
        setPageIndicator(navBarHidden: navigationController?.navigationBar.isHidden ?? false, animated: true)
    }

    private func applyPageIndicator(navBarHidden: Bool) {
        guard let pageIndicator else { return }
        let hasInfo = viewModel.state.currentPage != nil && viewModel.state.pagesCount != nil
        let shouldShow = hasInfo && !navBarHidden
        // Pick the document's bottom anchor: full screen fills to the very bottom (under the home indicator), otherwise
        // it stops above the page indicator (when shown) or at the safe area.
        documentBottomToView?.isActive = false
        documentBottomToIndicator?.isActive = false
        documentBottomToSafeArea?.isActive = false
        if navBarHidden {
            documentBottomToView?.isActive = true
        } else if shouldShow {
            documentBottomToIndicator?.isActive = true
        } else {
            documentBottomToSafeArea?.isActive = true
        }
        pageIndicator.alpha = shouldShow ? 1 : 0
    }

    private func setPageIndicator(navBarHidden: Bool, animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.15) { [weak self] in
                self?.applyPageIndicator(navBarHidden: navBarHidden)
                self?.view.layoutIfNeeded()
            }
        } else {
            applyPageIndicator(navBarHidden: navBarHidden)
        }
    }

    // MARK: - Actions

    private func updateInterface(to settings: HtmlEpubSettings) {
        navigationController?.overrideUserInterfaceStyle = readerUserInterfaceStyle(for: settings.appearance)
        updatePresentedReaderInterface(to: settings)

        func readerUserInterfaceStyle(for appearance: ReaderSettingsState.Appearance) -> UIUserInterfaceStyle {
            switch appearance {
            case .automatic:
                return .unspecified

            case .light, .sepia:
                return .light

            case .dark:
                return .dark
            }
        }
    }

    private func presentedUserInterfaceStyle(for appearance: ReaderSettingsState.Appearance) -> UIUserInterfaceStyle {
        switch appearance {
        case .automatic:
            return currentSystemUserInterfaceStyle

        case .light, .sepia:
            return .light

        case .dark:
            return .dark
        }
    }

    private func updatePresentedReaderInterface(to settings: HtmlEpubSettings) {
        navigationController?.presentedViewController?.overrideUserInterfaceStyle = presentedUserInterfaceStyle(for: settings.appearance)
    }

    private var currentSystemUserInterfaceStyle: UIUserInterfaceStyle {
        let windowSceneStyle = view.window?.windowScene?.traitCollection.userInterfaceStyle
        let traitStyle = traitCollection.userInterfaceStyle
        return windowSceneStyle ?? traitStyle
    }

    private func toggleSidebar(animated: Bool) {
        toggleSidebar(animated: animated, sidebarButtonTag: NavigationBarButton.sidebar.rawValue)
    }

    private func showSettings(sender: UIBarButtonItem) {
        guard let settingsViewModel = coordinatorDelegate?.showSettings(with: viewModel.state.settings, sender: sender) else { return }
        updatePresentedReaderInterface(to: viewModel.state.settings)
        settingsViewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                guard let self else { return }
                let settings = HtmlEpubSettings(appearance: state.appearance)
                if settings.appearance == .automatic {
                    self.viewModel.process(action: .userInterfaceStyleChanged(currentSystemUserInterfaceStyle))
                }
                self.viewModel.process(action: .setSettings(settings))
            })
            .disposed(by: disposeBag)
    }

    private func close() {
        navigationController?.presentingViewController?.dismiss(animated: true)
    }

    private func updateStatusBarHeight(allowZero: Bool = false) {
        guard let newStatusBarHeight = (view.scene as? UIWindowScene)?.statusBarManager?.statusBarFrame.height else { return }
        let shouldUpdate = newStatusBarHeight > 0 || allowZero
        guard shouldUpdate else { return }
        statusBarHeight = newStatusBarHeight
    }

    private func currentContainerInsets(forToolbarState state: AnnotationToolbarHandler.State? = nil) -> NSDirectionalEdgeInsets {
        let state = state ?? toolbarState
        let toolbarHeight = isTopToolbarVisible(forToolbarState: state) ? (annotationToolbarController?.size ?? 0) : 0
        let top = statusBarHeight + navigationBarHeight + toolbarHeight

        return NSDirectionalEdgeInsets(top: top, leading: 0, bottom: 0, trailing: 0)
    }

    private func isTopToolbarVisible(forToolbarState state: AnnotationToolbarHandler.State) -> Bool {
        return state.visible && viewModel.state.library.metadataEditable && state.position == .top
    }

    private func updateContainerInsets(forToolbarState state: AnnotationToolbarHandler.State? = nil, force: Bool = false) {
        let insets = currentContainerInsets(forToolbarState: state)
        guard force || (insets != lastContainerInsets) else { return }

        lastContainerInsets = insets
        documentController?.containerInsets = insets
    }

    /// Populates the trailing navigation bar items. `search` and `settings` go into the overflow group (so they
    /// collapse into a "•••" menu when space is tight, in visual order search · settings), while the annotation
    /// toolbar toggle stays fixed inboard of them.
    private func updateNavigationBarTrailingItems() {
        navigationBarOverflowItems = [searchButton, settingsButton]
        navigationBarTrailingFixedItems = viewModel.state.library.metadataEditable ? [toolbarButton] : []
    }
}

extension HtmlEpubReaderViewController: AnnotationToolbarHandlerDelegate {
    var additionalToolbarInsets: NSDirectionalEdgeInsets {
        let leading = isSidebarVisible ? (documentControllerLeft?.constant ?? 0) : 0
        return NSDirectionalEdgeInsets(top: documentControllerTop.constant, leading: leading, bottom: 0, trailing: 0)
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
        setPageIndicator(navBarHidden: hidden, animated: animated)
    }

    func setNavigationBar(alpha: CGFloat) {
        navigationController?.navigationBar.alpha = alpha
    }

    func setDocumentInterface(hidden: Bool) {
    }
    
    func annotationToolbarWillChange(state: AnnotationToolbarHandler.State, statusBarVisible: Bool) {
        updateContainerInsets(forToolbarState: state)
    }

    func topDidChange(forToolbarState state: AnnotationToolbarHandler.State) {
        documentControllerTop.constant = 0
        if isChangingInterfaceVisibility && !isTopToolbarVisible(forToolbarState: state) {
            return
        }
        updateContainerInsets(forToolbarState: state)
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

    func isCompactSize(for rotation: AnnotationToolbarViewController.Rotation) -> Bool {
        switch rotation {
        case .horizontal:
            return isCompactWidth

        case .vertical:
            return view.frame.height <= 650
        }
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

    func setReaderBackground(color: UIColor) {
        view.backgroundColor = color
    }

    func toggleInterfaceVisibility() {
        let isHidden = !(navigationController?.navigationBar.isHidden ?? false)
        let shouldChangeNavigationBarVisibility = !toolbarState.visible || toolbarState.position != .pinned

        if !isHidden && shouldChangeNavigationBarVisibility && navigationController?.navigationBar.isHidden == true {
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.navigationBar.alpha = 0
        }

        isChangingInterfaceVisibility = true
        statusBarVisible = !isHidden
        annotationToolbarHandler?.interfaceVisibilityDidChange()
        if isTopToolbarVisible(forToolbarState: toolbarState) {
            updateContainerInsets(force: true)
        }

        UIView.animate(withDuration: 0.15, animations: { [weak self] in
            guard let self else { return }
            updateStatusBar()
            view.layoutIfNeeded()
            if shouldChangeNavigationBarVisibility {
                navigationController?.navigationBar.alpha = isHidden ? 0 : 1
                navigationController?.setNavigationBarHidden(isHidden, animated: false)
            }
            applyPageIndicator(navBarHidden: isHidden)
            view.layoutIfNeeded()
            annotationToolbarHandler?.interfaceVisibilityDidChange()
            if isTopToolbarVisible(forToolbarState: toolbarState) {
                updateContainerInsets(force: true)
            }
        }, completion: { [weak self] _ in
            guard let self else { return }
            isChangingInterfaceVisibility = false
            if isTopToolbarVisible(forToolbarState: toolbarState) {
                updateContainerInsets(force: true)
            }
        })

        if isHidden && isSidebarVisible {
            toggleSidebar(animated: true)
        }

        readAloudHandler?.readAloudControlsShouldChange(isNavbarHidden: isHidden)
    }
}

extension HtmlEpubReaderViewController: ParentWithSidebarController {
    func initializeSidebarIfNeeded() {
        guard sidebarController == nil, let annotationToolbarController else { return }
        let sidebarController = HtmlEpubSidebarViewController(viewModel: viewModel)
        sidebarController.parentDelegate = self
        sidebarController.coordinatorDelegate = coordinatorDelegate
        sidebarController.view.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = Asset.Colors.annotationSidebarBorderColor.color

        add(controller: sidebarController)
        view.insertSubview(sidebarController.view, aboveSubview: annotationToolbarController.view)
        view.insertSubview(separator, aboveSubview: sidebarController.view)

        let sidebarLeftConstraint = sidebarController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -PDFReaderLayout.sidebarWidth)
        NSLayoutConstraint.activate([
            sidebarController.view.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarController.view.widthAnchor.constraint(equalToConstant: PDFReaderLayout.sidebarWidth),
            sidebarLeftConstraint,
            separator.widthAnchor.constraint(equalToConstant: PDFReaderLayout.separatorWidth),
            separator.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor),
            separator.topAnchor.constraint(equalTo: view.topAnchor),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.sidebarController = sidebarController
        sidebarControllerLeft = sidebarLeftConstraint
        view.layoutIfNeeded()
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

extension HtmlEpubReaderViewController: SpeechManagerDelegate {
    var documentTitle: String? {
        return viewModel.state.title
    }

    var documentFile: FileData? {
        return viewModel.state.documentFile as? FileData
    }

    var documentPassword: String? {
        // HTML/EPUB documents are never locked/encrypted.
        return nil
    }

    // Read-aloud treats the whole HTML/EPUB document as a single structured-document-text page (index 0): its content
    // has no page geometry (DomAnchor), so all read-aloud paragraphs live on page 0. The reader's reflowable view pages
    // don't map to SDT pages, so these report the single page 0 (playback starts at the document beginning; page-follow
    // is not supported — see `moved(to:from:)`).
    func getCurrentPageIndex() -> Int {
        return 0
    }

    func getNextPageIndex(from currentPageIndex: Int) -> Int? {
        return nil
    }

    func getPreviousPageIndex(from currentPageIndex: Int) -> Int? {
        return nil
    }

    func pageIndex(forStructuredDocumentTextPage page: Int) -> Int? {
        return page == 0 ? 0 : nil
    }

    func moved(to pageIndex: Int, from previousPageIndex: Int) {
        // Visual page-follow during playback is not yet supported for HTML/EPUB (there is no structured-document-text
        // page → reader-location mapping). No-op for now; audio playback still advances through the whole document.
    }

    func focusPage(_ pageIndex: Int) {
        // See `moved(to:from:)`. No-op for now.
    }

    func readAloudReaderSegments(sdtPackData: Data, packVersion: Int, schemaMajorVersion: Int, completion: @escaping ([SpeechReaderSegment]?) -> Void) {
        guard let documentController else {
            completion(nil)
            return
        }
        // The reader is the source of truth for HTML/EPUB read-aloud: hand it the SDT pack, then fetch the segments
        // (with their SDT positions) used for playback, navigation, and annotation creation. Sentence granularity gives
        // the finest units; paragraphs are reconstructed from the `paragraphStart` flags.
        documentController.setSDTPack(bytes: sdtPackData, packVersion: packVersion, schemaMajorVersion: schemaMajorVersion)
        documentController.getReadAloudSegments(granularity: "sentence", completion: completion)
    }

    func readAloudVisibleStartBlockIndex(completion: @escaping (Int?) -> Void) {
        guard let documentController else {
            completion(nil)
            return
        }
        documentController.getReadAloudStartBlockIndex(completion: completion)
    }

    func readAloudHighlightChanged(rects: [CGRect], sdtStart: [Int]?, sdtEnd: [Int]?, pageIndex: Int) {
        // Spotlight the currently-spoken segment in the web view via its reader SDT position.
        guard let sdtStart, let sdtEnd else { return }
        documentController?.setReadAloudSpotlight(sdtStart: sdtStart, sdtEnd: sdtEnd)
    }

    func annotationPreviewChanged(rects: [CGRect], sdtStart: [Int]?, sdtEnd: [Int]?, pageIndex: Int, tool: AnnotationTool, color: String) {
        // Render/resize the live preview annotation in the reader. It is withheld from the database until confirm.
        guard let sdtStart, let sdtEnd else { return }
        documentController?.setReadAloudAnnotation(type: tool, color: color, sdtStart: sdtStart, sdtEnd: sdtEnd)
    }

    func createAnnotation(ofType tool: AnnotationTool, color: String, rects: [CGRect], sdtStart: [Int]?, sdtEnd: [Int]?, onPage pageIndex: Int) {
        // Confirmed highlight session: persist the preview annotation (single DB write via `onSaveAnnotations`).
        documentController?.confirmReadAloudAnnotation()
    }

    func clearAnnotationPreview() {
        // Session ended: discard any unconfirmed preview annotation from the reader (no-op if it was just confirmed).
        documentController?.cancelReadAloudAnnotation()
    }
}

extension HtmlEpubReaderViewController: ReadAloudViewDelegate {
    func readAloudToolbarChanged(height: CGFloat) {
        let toolbarHeightAboveSafeArea = max(0, height - view.safeAreaInsets.bottom)
        documentBottomToSafeArea?.constant = toolbarHeightAboveSafeArea
        pageIndicatorBottom?.constant = toolbarHeightAboveSafeArea + 8
        view.layoutIfNeeded()
    }

    func presentReadAloudOnboarding(language: String?, detectedLanguage: String, completion: @escaping (SpeechVoice?) -> Void) {
        coordinatorDelegate?.showReadAloudOnboarding(
            from: self,
            language: language,
            detectedLanguage: detectedLanguage,
            userInterfaceStyle: viewModel.state.settings.appearance.userInterfaceStyle,
            completion: completion
        )
    }

    func presentReadAloudVoicePicker(currentVoice: SpeechVoice, language: String?, detectedLanguage: String, selectionChanged: @escaping (ReadAloudVoiceChange) -> Void) {
        coordinatorDelegate?.showVoicePicker(
            for: currentVoice,
            language: language,
            detectedLanguage: detectedLanguage,
            userInterfaceStyle: viewModel.state.settings.appearance.userInterfaceStyle,
            selectionChanged: selectionChanged
        )
    }

    func presentReadAloudAddMoreTime() {
        coordinatorDelegate?.showReadAloudAddMoreTime(from: self)
    }

    func addReadAloudControlsViewToAnnotationToolbar(view: AnnotationToolbarLeadingView) {
        annotationToolbarHandler?.setLeadingView(view: view)
    }

    func removeReadAloudControlsViewFromAnnotationToolbar() {
        annotationToolbarHandler?.setLeadingView(view: nil)
    }

    func clearSpeechHighlight() {
        // Clear the read-aloud spotlight when playback stops.
        documentController?.clearReadAloudSpotlight()
    }

    func showSpeechHighlighterOverlay(_ overlay: ReadAloudHighlighterOverlayView, isCompact: Bool, speechControlsView: UIView?, animated: Bool) {
        view.addSubview(overlay)
        setupConstraints()
        if !animated {
            view.layoutIfNeeded()
        } else {
            overlay.alpha = 0
            view.layoutIfNeeded()
            UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
                overlay.alpha = 1
            }
        }

        func setupConstraints() {
            if isCompact {
                let bottomAnchor: NSLayoutYAxisAnchor
                if let speechControlsView, speechControlsView.superview != nil {
                    bottomAnchor = speechControlsView.topAnchor
                } else {
                    bottomAnchor = view.safeAreaLayoutGuide.bottomAnchor
                }
                NSLayoutConstraint.activate([
                    overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                    overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                    overlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
                ])
            } else {
                let topConstraint = overlay.topAnchor.constraint(equalTo: view.topAnchor, constant: containerTopInset + 20)
                speechHighlighterTopConstraint = topConstraint
                NSLayoutConstraint.activate([
                    topConstraint,
                    overlay.centerXAnchor.constraint(equalTo: documentController?.view.centerXAnchor ?? view.centerXAnchor),
                    overlay.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
                    overlay.widthAnchor.constraint(lessThanOrEqualToConstant: 500)
                ])
            }
        }
    }

    func hideSpeechHighlighterOverlay(_ overlay: ReadAloudHighlighterOverlayView) {
        speechHighlighterTopConstraint = nil
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn, animations: {
            overlay.alpha = 0
        }, completion: { _ in
            overlay.removeFromSuperview()
        })
    }

    func updateSpeechHighlightStyle(tool: AnnotationTool, color: String) {
        // Re-style the live preview annotation (same range, new tool/color) mid-session.
        guard let sdt = readAloudHandler?.speechManager.currentHighlightSDTRange else { return }
        documentController?.setReadAloudAnnotation(type: tool, color: color, sdtStart: sdt.start, sdtEnd: sdt.end)
    }
}
