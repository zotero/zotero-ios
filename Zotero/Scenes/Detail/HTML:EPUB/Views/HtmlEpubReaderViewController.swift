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

class HtmlEpubReaderViewController: UIViewController {
    private let url: URL
    private let disposeBag: DisposeBag

    private weak var documentController: HtmlEpubDocumentViewController?
    private weak var annotationToolbarController: AnnotationToolbarViewController!
    private var annotationToolbarHandler: AnnotationToolbarHandler!
    private var documentTop: NSLayoutConstraint!
    internal var navigationBarHeight: CGFloat {
        return self.navigationController?.navigationBar.frame.height ?? 0.0
    }
    private(set) var isCompactWidth: Bool
    var statusBarHeight: CGFloat
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

    init(url: URL, compactSize: Bool) {
        self.url = url
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

        self.setupNavigationBar()
        self.setupViews()
        self.navigationItem.rightBarButtonItem = self.toolbarButton
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        self.isCompactWidth = UIDevice.current.isCompactWidth(size: size)

        guard self.viewIfLoaded != nil else { return }

        coordinator.animate(alongsideTransition: { _ in
            self.statusBarHeight = self.view.safeAreaInsets.top - (self.navigationController?.isNavigationBarHidden == true ? 0 : self.navigationBarHeight)
            self.annotationToolbarHandler.viewWillTransitionToNewSize()
        }, completion: nil)
    }

    private func add(controller: UIViewController) {
        controller.willMove(toParent: self)
        self.addChild(controller)
        controller.didMove(toParent: self)
    }

    private func close() {
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    private func setupNavigationBar() {
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
        closeButton.title = L10n.close
        closeButton.accessibilityLabel = L10n.close
        closeButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.close() }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = closeButton
    }

    private func setupViews() {
        let documentController = HtmlEpubDocumentViewController(url: self.url)
        documentController.view.translatesAutoresizingMaskIntoConstraints = false

        let annotationToolbar = AnnotationToolbarViewController(tools: [.highlight, .note], size: self.navigationBarHeight)
        annotationToolbar.delegate = self

        self.add(controller: documentController)
        self.add(controller: annotationToolbar)
        self.view.addSubview(documentController.view)
        self.view.addSubview(annotationToolbar.view)

        self.documentTop = documentController.view.topAnchor.constraint(equalTo: self.view.topAnchor)

        NSLayoutConstraint.activate([
            self.documentTop,
            self.view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: documentController.view.bottomAnchor),
            self.view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: documentController.view.leadingAnchor),
            self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: documentController.view.trailingAnchor)
        ])

        self.documentController = documentController
        self.annotationToolbarController = annotationToolbar
        self.annotationToolbarHandler = AnnotationToolbarHandler(controller: annotationToolbar, delegate: self)
        self.annotationToolbarHandler.performInitialLayout()
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
    
    var activeAnnotationTool: AnnotationToolbarViewController.Tool? {
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
    
    func toggle(tool: AnnotationToolbarViewController.Tool, options: AnnotationToolOptions) {
        self.documentController?.set(tool: tool)
    }
    
    func showToolOptions(sender: SourceView) {
    }
    
    func closeAnnotationToolbar() {
    }
    
    func performUndo() {
    }

    func performRedo() {
    }
}
