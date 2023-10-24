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
    internal var navigationBarHeight: CGFloat {
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
//        checkbox.deselectedTintColor = self.viewModel.state.document.isLocked ? .gray : Asset.Colors.zoteroBlueWithDarkMode.color
        checkbox.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        checkbox.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        checkbox.selectedTintColor = .white
        checkbox.isSelected = self.toolbarState.visible// && !self.viewModel.state.document.isLocked
        checkbox.rx.controlEvent(.touchUpInside)
                .subscribe(onNext: { [weak self, weak checkbox] _ in
                    guard let self = self, let checkbox = checkbox else { return }
                    checkbox.isSelected = !checkbox.isSelected
                    self.annotationToolbarHandler.set(hidden: !checkbox.isSelected, animated: true)
                })
                .disposed(by: self.disposeBag)
        let barButton = UIBarButtonItem(customView: checkbox)
//        barButton.isEnabled = !self.viewModel.state.document.isLocked
        barButton.accessibilityLabel = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.title = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.largeContentSizeImage = UIImage(systemName: "pencil.and.outline", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        return barButton
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
        navigationItem.rightBarButtonItem = toolbarButton

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
            closeButton.rx.tap.subscribe(with: self, onNext: { _, _ in self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil) }).disposed(by: self.disposeBag)

            let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"), style: .plain, target: nil, action: nil)
            setupAccessibility(forSidebarButton: sidebarButton)
            sidebarButton.tag = Self.sidebarButtonTag
            sidebarButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.toggleSidebar(animated: true) }).disposed(by: self.disposeBag)

            self.navigationItem.leftBarButtonItems = [closeButton, sidebarButton]
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
                .disposed(by: self.disposeBag)
            self.navigationItem.searchController = searchController
        }

        func setupViews() {
            let documentController = HtmlEpubDocumentViewController(viewModel: self.viewModel)
            documentController.view.translatesAutoresizingMaskIntoConstraints = false

            let annotationToolbar = AnnotationToolbarViewController(tools: [.highlight, .note], size: self.navigationBarHeight)
            annotationToolbar.delegate = self

            let sidebarController = HtmlEpubSidebarViewController(viewModel: self.viewModel)
            sidebarController.parentDelegate = self
            sidebarController.coordinatorDelegate = self.coordinatorDelegate
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

            let documentLeftConstraint = documentController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
            let sidebarLeftConstraint = sidebarController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: -PDFReaderLayout.sidebarWidth)
            let documentTopConstraint = documentController.view.topAnchor.constraint(equalTo: self.view.topAnchor)

            NSLayoutConstraint.activate([
                documentTopConstraint,
                view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: documentController.view.bottomAnchor),
                view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: documentController.view.trailingAnchor),
                sidebarController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                sidebarController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                sidebarController.view.widthAnchor.constraint(equalToConstant: PDFReaderLayout.sidebarWidth),
                sidebarLeftConstraint,
                separator.widthAnchor.constraint(equalToConstant: PDFReaderLayout.separatorWidth),
                separator.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor),
                separator.topAnchor.constraint(equalTo: self.view.topAnchor),
                separator.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
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
                self.addChild(controller)
                controller.didMove(toParent: self)
            }
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        self.annotationToolbarHandler.viewIsAppearing(documentIsLocked: false)
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

        guard self.viewIfLoaded != nil else { return }

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

        func show(error: HtmlEpubReaderState.Error) {
        }
    }

    // MARK: - Actions

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
            self.documentLeft.constant = shouldShow ? PDFReaderLayout.sidebarWidth : 0
        } else if shouldShow && self.toolbarState.visible {
            self.closeAnnotationToolbar()
        }
        self.sidebarLeft.constant = shouldShow ? 0 : -PDFReaderLayout.sidebarWidth

        if let button = self.navigationItem.leftBarButtonItems?.first(where: { $0.tag == Self.sidebarButtonTag }) {
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

    private func setupAccessibility(forSidebarButton button: UIBarButtonItem) {
        button.accessibilityLabel = self.isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
        button.title = self.isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
    }
}

extension HtmlEpubReaderViewController: AnnotationToolbarHandlerDelegate {
    var isNavigationBarHidden: Bool {
        self.navigationController?.navigationBar.isHidden ?? false
    }

    var isSidebarHidden: Bool {
        return false
    }

    var containerView: UIView {
        return self.view
    }

    var documentView: UIView {
        return self.view
    }

    var toolbarLeadingAnchor: NSLayoutXAxisAnchor {
        return self.view.leadingAnchor
    }

    var toolbarLeadingSafeAreaAnchor: NSLayoutXAxisAnchor {
        return self.view.safeAreaLayoutGuide.leadingAnchor
    }

    func layoutIfNeeded() {
        self.view.layoutIfNeeded()
    }

    func setNeedsLayout() {
        self.view.setNeedsLayout()
    }

    func hideSidebarIfNeeded(forPosition position: AnnotationToolbarHandler.State.Position, isToolbarSmallerThanMinWidth: Bool, animated: Bool) {
    }

    func setNavigationBar(hidden: Bool, animated: Bool) {
        self.navigationController?.setNavigationBarHidden(hidden, animated: animated)
    }

    func setNavigationBar(alpha: CGFloat) {
        self.navigationController?.navigationBar.alpha = alpha
    }

    func setDocumentInterface(hidden: Bool) {
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

    func updateStatusBar() {
        self.navigationController?.setNeedsStatusBarAppearanceUpdate()
        self.setNeedsStatusBarAppearanceUpdate()
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
        return self.view.frame.width
    }

    func toggle(tool: AnnotationTool, options: AnnotationToolOptions) {
        guard let color = self.viewModel.state.toolColors[tool] else { return }

        let oldTool = self.viewModel.state.activeTool
        self.viewModel.process(action: .toggleTool(tool))

        self.documentController?.set(tool: self.viewModel.state.activeTool.flatMap({ ($0, color) }))

        if let tool = self.viewModel.state.activeTool {
            self.annotationToolbarController.set(selected: true, to: tool, color: color)
        } else if let oldTool {
            self.annotationToolbarController.set(selected: false, to: oldTool, color: color)
        }
    }

    func showToolOptions(sender: SourceView) {
    }

    func closeAnnotationToolbar() {
        (self.toolbarButton.customView as? CheckboxButton)?.isSelected = false
        self.annotationToolbarHandler.set(hidden: true, animated: true)
    }

    func performUndo() {
    }

    func performRedo() {
    }
}

extension HtmlEpubReaderViewController: HtmlEpubReaderContainerDelegate {}
