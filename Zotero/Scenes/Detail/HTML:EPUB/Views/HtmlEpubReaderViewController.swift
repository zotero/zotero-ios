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

class HtmlEpubReaderViewController: UIViewController, ParentWithSidebarController {
    typealias DocumentController = HtmlEpubDocumentViewController
    typealias SidebarController = HtmlEpubSidebarViewController

    private enum NavigationBarButton: Int {
        case sidebar = 7
    }

    private let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    let disposeBag: DisposeBag

    weak var documentController: HtmlEpubDocumentViewController?
    private weak var documentControllerTop: NSLayoutConstraint!
    weak var documentControllerLeft: NSLayoutConstraint?
    weak var annotationToolbarController: AnnotationToolbarViewController?
    var annotationToolbarHandler: AnnotationToolbarHandler?
    weak var sidebarController: HtmlEpubSidebarViewController?
    weak var sidebarControllerLeft: NSLayoutConstraint?
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
        view.backgroundColor = .systemBackground
        observeViewModel()
        setupNavigationBar()
        setupSearch()
        setupViews()
        navigationController?.overrideUserInterfaceStyle = viewModel.state.settings.appearance.userInterfaceStyle
        navigationItem.rightBarButtonItems = [settingsButton, toolbarButton]

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
                .skip(1)
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

            let annotationToolbar = AnnotationToolbarViewController(tools: [.highlight, .underline, .note], undoRedoEnabled: false, size: navigationBarHeight)
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
            annotationToolbarController = annotationToolbar
            documentControllerTop = documentTopConstraint
            documentControllerLeft = documentLeftConstraint
            sidebarControllerLeft = sidebarLeftConstraint
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
    }

    deinit {
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
        }, completion: nil)
    }

    // MARK: - State

    private func process(state: HtmlEpubReaderState) {
        if let error = state.error {
            show(error: error)
        }

        if state.changes.contains(.toolColor), let color = state.activeTool.flatMap({ state.toolColors[$0] }) {
            annotationToolbarController?.set(activeColor: color)
        }

        if state.changes.contains(.activeTool) {
            select(activeTool: state.activeTool)
        }

        if state.changes.contains(.settings) {
            navigationController?.overrideUserInterfaceStyle = state.settings.appearance.userInterfaceStyle
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

        func show(error: HtmlEpubReaderState.Error) {
        }

        func showPopover(forKey key: String, rect: CGRect) {
            guard !isSidebarVisible else { return }
            let observable = coordinatorDelegate?.showAnnotationPopover(
                viewModel: viewModel,
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
                if state.changes.contains(.pageLabel) || state.changes.contains(.highlight) {
                    viewModel.process(action:
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
        toggleSidebar(animated: animated, sidebarButtonTag: NavigationBarButton.sidebar.rawValue)
    }

    private func showSettings(sender: UIBarButtonItem) {
        guard let viewModel = coordinatorDelegate?.showSettings(with: viewModel.state.settings, sender: sender) else { return }
        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                let settings = HtmlEpubSettings(appearance: state.appearance, idleTimerDisabled: state.idleTimerDisabled)
                self?.viewModel.process(action: .setSettings(settings))
            })
            .disposed(by: disposeBag)
    }

    private func close() {
        viewModel.process(action: .changeIdleTimerDisabled(false))
        navigationController?.presentingViewController?.dismiss(animated: true)
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
    }

    func setNavigationBar(alpha: CGFloat) {
        navigationController?.navigationBar.alpha = alpha
    }

    func setDocumentInterface(hidden: Bool) {
    }

    func topDidChange(forToolbarState state: AnnotationToolbarHandler.State) {
        guard let annotationToolbarHandler, let annotationToolbarController else { return }
        let (statusBarOffset, _, totalOffset) = annotationToolbarHandler.topOffsets(statusBarVisible: statusBarVisible)

        if !state.visible {
            documentControllerTop.constant = totalOffset
            return
        }

        switch state.position {
        case .pinned:
            documentControllerTop.constant = statusBarOffset + annotationToolbarController.size

        case .top:
            documentControllerTop.constant = totalOffset + annotationToolbarController.size

        case .trailing, .leading:
            documentControllerTop.constant = totalOffset
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

    func showToolOptions(sender: SourceView) {
        guard let tool = viewModel.state.activeTool else { return }
        let colorHex = viewModel.state.toolColors[tool]?.hexString

        coordinatorDelegate?.showToolSettings(
            tool: tool,
            colorHex: colorHex,
            sizeValue: nil,
            sender: sender,
            userInterfaceStyle: viewModel.state.settings.appearance.userInterfaceStyle
        ) { [weak self] newColor, newSize in
            self?.viewModel.process(action: .setToolOptions(color: newColor, size: newSize.flatMap(CGFloat.init), tool: tool))
        }
    }

    func closeAnnotationToolbar() {
        (toolbarButton.customView as? CheckboxButton)?.isSelected = false
        annotationToolbarHandler?.set(hidden: true, animated: true)
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
