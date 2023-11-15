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
}

class HtmlEpubReaderViewController: UIViewController {
    private let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    private let disposeBag: DisposeBag
    private static let sidebarButtonTag = 7

    private weak var documentController: HtmlEpubDocumentViewController?
    private weak var documentTop: NSLayoutConstraint!
    private weak var documentLeft: NSLayoutConstraint!
    private weak var annotationToolbarController: AnnotationToolbarViewController!
    private var annotationToolbarHandler: AnnotationToolbarHandler!
    private weak var sidebarController: HtmlEpubSidebarViewController!
    private weak var sidebarLeft: NSLayoutConstraint!
    var navigationBarHeight: CGFloat {
        return self.navigationController?.navigationBar.frame.height ?? 0.0
    }
    private(set) var isCompactWidth: Bool
    var statusBarHeight: CGFloat
    weak var coordinatorDelegate: (HtmlEpubReaderCoordinatorDelegate&HtmlEpubSidebarCoordinatorDelegate)?
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
    var isSidebarVisible: Bool { return self.sidebarLeft?.constant == 0 }
    private lazy var toolbarButton: UIBarButtonItem = {
        let checkbox = CheckboxButton(type: .custom)
        checkbox.setImage(UIImage(systemName: "pencil.and.outline", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .normal)
        checkbox.adjustsImageWhenHighlighted = false
        checkbox.scalesLargeContentImage = true
        checkbox.layer.cornerRadius = 4
        checkbox.layer.masksToBounds = true
        checkbox.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        checkbox.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        checkbox.selectedTintColor = .white
        checkbox.deselectedTintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        checkbox.isSelected = toolbarState.visible
        checkbox.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: { [weak self, weak checkbox] _ in
                guard let self = self, let checkbox = checkbox else { return }
                checkbox.isSelected = !checkbox.isSelected
                self.annotationToolbarHandler.set(hidden: !checkbox.isSelected, animated: true)
            })
            .disposed(by: disposeBag)
        let barButton = UIBarButtonItem(customView: checkbox)
        barButton.accessibilityLabel = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.title = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.largeContentSizeImage = UIImage(systemName: "pencil.and.outline", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        return barButton
    }()
    private lazy var settingsButton: UIBarButtonItem = {
        let settings = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: nil, action: nil)
        settings.accessibilityLabel = L10n.Accessibility.Pdf.settings
        settings.title = L10n.Accessibility.Pdf.settings
        settings.rx.tap
            .subscribe(onNext: { [weak self, weak settings] _ in
                guard let self, let settings else { return }
                self.coordinatorDelegate?.showSettings(
                    with: self.viewModel.state.settings,
                    sender: settings,
                    completion: { [weak self] settings in
                        guard let self else { return }
                        self.viewModel.process(action: .setSettings(settings))
                    }
                )
            })
            .disposed(by: disposeBag)
        return settings
    }()

    // MARK: - Lifecycle

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>, compactSize: Bool) {
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

    override func loadView() {
        self.view = UIView()
        self.view.backgroundColor = .systemBackground
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        observeViewModel()
        setupNavigationBar()
        setupSearch()
        setupViews()
        navigationController?.overrideUserInterfaceStyle = viewModel.state.settings.interfaceStyle
        navigationItem.rightBarButtonItems = [settingsButton, toolbarButton]

        func observeViewModel() {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(with: self, onNext: { `self`, state in
                    self.process(state: state)
                })
                .disposed(by: disposeBag)
        }

        func setupNavigationBar() {
            let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
            closeButton.title = L10n.close
            closeButton.accessibilityLabel = L10n.close
            closeButton.rx.tap.subscribe(with: self, onNext: { _, _ in self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil) }).disposed(by: disposeBag)

            let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"), style: .plain, target: nil, action: nil)
            setupAccessibility(forSidebarButton: sidebarButton)
            sidebarButton.tag = Self.sidebarButtonTag
            sidebarButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.toggleSidebar(animated: true) }).disposed(by: disposeBag)

            navigationItem.leftBarButtonItems = [closeButton, sidebarButton]
        }

        func setupSearch() {
            let searchController = UISearchController()
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.hidesNavigationBarDuringPresentation = false
            searchController.searchBar.placeholder = "Search Document"
            searchController.searchBar.autocapitalizationType = .none

            searchController.searchBar
                .rx
                .text
                .observe(on: MainScheduler.instance)
                .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                .subscribe(onNext: { [weak self] text in
                    self?.viewModel.process(action: .searchDocument(text ?? ""))
                })
                .disposed(by: disposeBag)

            searchController.searchBar
                .rx
                .cancelButtonClicked
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    self?.viewModel.process(action: .searchDocument(""))
                })
                .disposed(by: disposeBag)

            navigationItem.searchController = searchController
        }

        func setupViews() {
            let documentController = HtmlEpubDocumentViewController(viewModel: viewModel)
            documentController.parentDelegate = self
            documentController.view.translatesAutoresizingMaskIntoConstraints = false

            let annotationToolbar = AnnotationToolbarViewController(tools: [.highlight, .note], size: navigationBarHeight)
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
            let documentTopConstraint = documentController.view.topAnchor.constraint(equalTo: view.topAnchor)

            NSLayoutConstraint.activate([
                documentTopConstraint,
                view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: documentController.view.bottomAnchor),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: documentController.view.trailingAnchor),
                sidebarController.view.topAnchor.constraint(equalTo: view.topAnchor),
                sidebarController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                sidebarController.view.widthAnchor.constraint(equalToConstant: PDFReaderLayout.sidebarWidth),
                sidebarLeftConstraint,
                separator.widthAnchor.constraint(equalToConstant: PDFReaderLayout.separatorWidth),
                separator.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor),
                separator.topAnchor.constraint(equalTo: view.topAnchor),
                separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                documentLeftConstraint
            ])

            self.documentController = documentController
            self.sidebarController = sidebarController
            self.annotationToolbarController = annotationToolbar
            self.documentTop = documentTopConstraint
            self.documentLeft = documentLeftConstraint
            self.sidebarLeft = sidebarLeftConstraint
            self.annotationToolbarHandler = AnnotationToolbarHandler(controller: annotationToolbar, delegate: self)
            self.annotationToolbarHandler.performInitialLayout()

            func add(controller: UIViewController) {
                controller.willMove(toParent: self)
                addChild(controller)
                controller.didMove(toParent: self)
            }
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        annotationToolbarHandler.viewIsAppearing(documentIsLocked: false)
    }

    deinit {
        DDLogInfo("HtmlEpubReaderViewController deinitialized")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if (documentController?.view.frame.width ?? 0) < AnnotationToolbarHandler.minToolbarWidth && toolbarState.visible && toolbarState.position == .top {
            closeAnnotationToolbar()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        isCompactWidth = UIDevice.current.isCompactWidth(size: size)

        guard viewIfLoaded != nil else { return }

        coordinator.animate(alongsideTransition: { _ in
            self.statusBarHeight = self.view.safeAreaInsets.top - (self.navigationController?.isNavigationBarHidden == true ? 0 : self.navigationBarHeight)
            self.annotationToolbarHandler.viewWillTransitionToNewSize()
        }, completion: nil)
    }

    // MARK: - State

    private func process(state: HtmlEpubReaderState) {
        if let error = state.error {
            show(error: error)
        }

        if state.changes.contains(.toolColor), let color = state.activeTool.flatMap({ state.toolColors[$0] }) {
            annotationToolbarController.set(activeColor: color)
        }

        if state.changes.contains(.settings) {
            navigationController?.overrideUserInterfaceStyle = state.settings.interfaceStyle
        }

        handleAnnotationPopover()

        func show(error: HtmlEpubReaderState.Error) {
        }

        func handleAnnotationPopover() {
            if let key = state.selectedAnnotationKey {
                if !isSidebarVisible, let rect = state.selectedAnnotationRect {
                    let observable = coordinatorDelegate?.showAnnotationPopover(
                        viewModel: viewModel,
                        sourceRect: rect,
                        popoverDelegate: self,
                        userInterfaceStyle: viewModel.state.settings.interfaceStyle
                    )
                    observe(key: key, popoverObservable: observable)
                }
            } else if navigationController?.presentedViewController is AnnotationPopover ||
               (navigationController?.presentedViewController as? UINavigationController)?.topViewController is AnnotationPopover {
                navigationController?.dismiss(animated: true)
            }
        }

        func observe(key: String, popoverObservable observable: PublishSubject<AnnotationPopoverState>?) {
            guard let observable else { return }
            observable.subscribe(with: self) { `self`, state in
                if state.changes.contains(.color) {
                    self.viewModel.process(action: .setColor(key: key, color: state.color))
                }
                if state.changes.contains(.comment) {
                    self.viewModel.process(action: .setComment(key: key, comment: state.comment))
                }
                if state.changes.contains(.deletion) {
                    self.viewModel.process(action: .removeAnnotation(key))
                }
                if state.changes.contains(.tags) {
                    self.viewModel.process(action: .setTags(key: key, tags: state.tags))
                }
                if state.changes.contains(.pageLabel) || state.changes.contains(.highlight) {
                    self.viewModel.process(action:
                        .updateAnnotationProperties(
                            key: key,
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

    private func toggleSidebar(animated: Bool) {
        let shouldShow = !isSidebarVisible

        if toolbarState.position == .leading {
            if shouldShow {
                annotationToolbarHandler.disableLeadingSafeConstraint()
            } else {
                annotationToolbarHandler.enableLeadingSafeConstraint()
            }
        }
        // If the layout is compact, show annotation sidebar above pdf document.
        if !isCompactWidth {
            documentLeft.constant = shouldShow ? PDFReaderLayout.sidebarWidth : 0
        } else if shouldShow && toolbarState.visible {
            closeAnnotationToolbar()
        }
        sidebarLeft.constant = shouldShow ? 0 : -PDFReaderLayout.sidebarWidth

        if let button = navigationItem.leftBarButtonItems?.first(where: { $0.tag == Self.sidebarButtonTag }) {
            setupAccessibility(forSidebarButton: button)
        }

        if !animated {
            sidebarController.view.isHidden = !shouldShow
            annotationToolbarController.prepareForSizeChange()
            view.layoutIfNeeded()
            annotationToolbarController.sizeDidChange()

            if !shouldShow {
                view.endEditing(true)
            }
            return
        }

        if shouldShow {
            sidebarController.view.isHidden = false
        } else {
            view.endEditing(true)
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

    private func setupAccessibility(forSidebarButton button: UIBarButtonItem) {
        button.accessibilityLabel = isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
        button.title = isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
    }
}

extension HtmlEpubReaderViewController: AnnotationToolbarHandlerDelegate {
    var isNavigationBarHidden: Bool {
        navigationController?.navigationBar.isHidden ?? false
    }

    var isSidebarHidden: Bool {
        return !isSidebarVisible
    }

    var containerView: UIView {
        return view
    }

    var documentView: UIView {
        return view
    }

    var toolbarLeadingAnchor: NSLayoutXAxisAnchor {
        return sidebarController.view.trailingAnchor
    }

    var toolbarLeadingSafeAreaAnchor: NSLayoutXAxisAnchor {
        return view.safeAreaLayoutGuide.leadingAnchor
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

    func topDidChange(forToolbarState state: AnnotationToolbarHandler.State) {
        let (statusBarOffset, _, totalOffset) = annotationToolbarHandler.topOffsets(statusBarVisible: statusBarVisible)

        if !state.visible {
            documentTop.constant = totalOffset
            return
        }

        switch state.position {
        case .pinned:
            documentTop.constant = statusBarOffset + annotationToolbarController.size

        case .top:
            documentTop.constant = totalOffset + annotationToolbarController.size

        case .trailing, .leading:
            documentTop.constant = totalOffset
        }
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

    var activeAnnotationTool: AnnotationTool? {
        return .highlight
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
        guard let color = viewModel.state.toolColors[tool] else { return }

        let oldTool = viewModel.state.activeTool
        viewModel.process(action: .toggleTool(tool))

        if let oldTool {
            annotationToolbarController.set(selected: false, to: oldTool, color: color)
        }
        if let tool = viewModel.state.activeTool {
            annotationToolbarController.set(selected: true, to: tool, color: color)
        }
    }

    func showToolOptions(sender: SourceView) {
        guard let tool = viewModel.state.activeTool else { return }
        let colorHex = viewModel.state.toolColors[tool]?.hexString

        coordinatorDelegate?.showToolSettings(
            tool: tool,
            colorHex: colorHex,
            sizeValue: nil,
            sender: sender,
            userInterfaceStyle: viewModel.state.settings.interfaceStyle
        ) { [weak self] newColor, newSize in
            self?.viewModel.process(action: .setToolOptions(color: newColor, size: newSize.flatMap(CGFloat.init), tool: tool))
        }
    }

    func closeAnnotationToolbar() {
        (toolbarButton.customView as? CheckboxButton)?.isSelected = false
        annotationToolbarHandler.set(hidden: true, animated: true)
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

extension HtmlEpubReaderViewController: HtmlEpubReaderContainerDelegate {}
