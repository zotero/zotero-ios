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
    var isToolbarVisible: Bool { get }
    var documentTopOffset: CGFloat { get }

    func showSearch(pdfController: PDFViewController, text: String?)
}

class PDFReaderViewController: UIViewController {
    private enum NavigationBarButton: Int {
        case share = 1
        case sidebar = 7
    }

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
    private var intraDocumentNavigationHandler: IntraDocumentNavigationButtonsHandler?
    private var selectedText: String?
    private(set) var isCompactWidth: Bool
    @CodableUserDefault(key: "PDFReaderToolbarState", defaultValue: AnnotationToolbarHandler.State(position: .leading, visible: true), encoder: Defaults.jsonEncoder, decoder: Defaults.jsonDecoder)
    var toolbarState: AnnotationToolbarHandler.State
    @UserDefault(key: "PDFReaderStatusBarVisible", defaultValue: true)
    private var _statusBarVisible: Bool
    var statusBarVisible: Bool {
        get {
            return _statusBarVisible || viewModel.state.document.isLocked
        }

        set {
            _statusBarVisible = newValue
            (navigationController as? NavigationViewController)?.statusBarVisible = newValue
        }
    }
    private var previousTraitCollection: UITraitCollection?
    var isSidebarVisible: Bool { return sidebarControllerLeft?.constant == 0 }
    var isToolbarVisible: Bool { return toolbarState.visible }
    var key: String { return viewModel.state.key }

    private unowned let openItemsController: OpenItemsController
    weak var coordinatorDelegate: (PdfReaderCoordinatorDelegate & PdfAnnotationsCoordinatorDelegate & OpenItemsPresenter)?

    private lazy var shareButton: UIBarButtonItem = {
        var menuChildren: [UIMenuElement] = []

        let share = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)
        share.accessibilityLabel = L10n.Accessibility.Pdf.share
        share.isEnabled = !viewModel.state.document.isLocked
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
    private lazy var openItemsButton: UIBarButtonItem = {
        let openItems = UIBarButtonItem.openItemsBarButtonItem()
        if let sessionIdentifier {
            let deferredOpenItemsMenuElement = openItemsController.deferredOpenItemsMenuElement(
                for: sessionIdentifier,
                showMenuForCurrentItem: true,
                openItemPresenterProvider: { [weak self] in
                    self?.coordinatorDelegate
                },
                completion: { [weak self] changedCurrentItem, openItemsChanged in
                    guard let self else { return }
                    if changedCurrentItem {
                        close(dismiss: false)
                    } else if openItemsChanged {
                        openItemsController.setOpenItemsUserActivity(from: self, libraryId: viewModel.state.library.identifier, title: viewModel.state.title)
                    }
                }
            )
            let openItemsMenu = UIMenu(title: L10n.Accessibility.Pdf.openItems, options: [.displayInline], children: [deferredOpenItemsMenuElement])
            openItems.menu = UIMenu(children: [openItemsMenu])
        }
        return openItems
    }()
    private lazy var settingsButton: UIBarButtonItem = {
        let settings = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: nil, action: nil)
        settings.isEnabled = !viewModel.state.document.isLocked
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
        search.isEnabled = !viewModel.state.document.isLocked
        search.accessibilityLabel = L10n.Accessibility.Pdf.searchPdf
        search.title = L10n.Accessibility.Pdf.searchPdf
        search.rx.tap
            .subscribe(onNext: { [weak self] _ in
                guard let self, let controller = documentController.pdfController else { return }
                showSearch(pdfController: controller, text: nil)
            })
            .disposed(by: disposeBag)
        return search
    }()
    private lazy var toolbarButton: UIBarButtonItem = {
        var configuration = UIButton.Configuration.plain()
        let image = UIImage(systemName: "pencil.and.outline")?.applyingSymbolConfiguration(.init(scale: .large))
        let checkbox = CheckboxButton(image: image!, contentInsets: NSDirectionalEdgeInsets(top: 11, leading: 6, bottom: 9, trailing: 6))
        checkbox.scalesLargeContentImage = true
        checkbox.deselectedBackgroundColor = .clear
        checkbox.deselectedTintColor = viewModel.state.document.isLocked ? .gray : Asset.Colors.zoteroBlueWithDarkMode.color
        checkbox.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        checkbox.selectedTintColor = .white
        checkbox.isSelected = !viewModel.state.document.isLocked && toolbarState.visible
        checkbox.rx.controlEvent(.touchUpInside)
            .subscribe(onNext: { [weak self, weak checkbox] _ in
                guard let self, let checkbox else { return }
                checkbox.isSelected = !checkbox.isSelected
                annotationToolbarHandler.set(hidden: !checkbox.isSelected, animated: true)
            })
            .disposed(by: disposeBag)
        let barButton = UIBarButtonItem(customView: checkbox)
        barButton.isEnabled = !viewModel.state.document.isLocked
        barButton.accessibilityLabel = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.title = L10n.Accessibility.Pdf.toggleAnnotationToolbar
        barButton.largeContentSizeImage = UIImage(systemName: "pencil.and.outline", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        return barButton
    }()

    override var keyCommands: [UIKeyCommand]? {
        var keyCommands: [UIKeyCommand] = [
            .init(title: L10n.Pdf.Search.title, action: #selector(search), input: "f", modifierFlags: [.command])
        ]
        if intraDocumentNavigationHandler?.showsBackButton == true {
            keyCommands += [
                .init(title: L10n.back, action: #selector(performBackAction), input: "[", modifierFlags: [.command]),
                .init(title: L10n.back, action: #selector(performBackAction), input: UIKeyCommand.inputLeftArrow, modifierFlags: [.command])
            ]
        }
        if intraDocumentNavigationHandler?.showsForwardButton == true {
            keyCommands += [
                .init(title: L10n.forward, action: #selector(performForwardAction), input: "]", modifierFlags: [.command]),
                .init(title: L10n.forward, action: #selector(performForwardAction), input: UIKeyCommand.inputRightArrow, modifierFlags: [.command])
            ]
        }
        return keyCommands
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if sender is UIKeyCommand {
            switch action {
            case #selector(UIResponderStandardEditActions.copy(_:)):
                return selectedText != nil

            case #selector(search), #selector(performBackAction), #selector(performForwardAction):
                return true

            case #selector(undo(_:)):
                return canUndo

            case #selector(redo(_:)):
                return canRedo

            default:
                break
            }
        }
        return false
    }

    init(viewModel: ViewModel<PDFReaderActionHandler>, compactSize: Bool, openItemsController: OpenItemsController) {
        self.viewModel = viewModel
        isCompactWidth = compactSize
        self.openItemsController = openItemsController
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        openItemsController.setOpenItemsUserActivity(from: self, libraryId: viewModel.state.library.identifier, title: viewModel.state.title)
        viewModel.process(action: .changeIdleTimerDisabled(true))
        view.backgroundColor = .systemGray6
        setupViews()
        setupObserving()

        if !viewModel.state.document.isLocked {
            viewModel.process(action: .loadDocumentData(boundingBoxConverter: documentController))
        }

        setupNavigationBar()
        updateInterface(to: viewModel.state.settings)

        func setupViews() {
            let topSafeAreaSpacer = UIView()
            topSafeAreaSpacer.translatesAutoresizingMaskIntoConstraints = false
            topSafeAreaSpacer.backgroundColor = Asset.Colors.navbarBackground.color

            let documentController = PDFDocumentViewController(viewModel: viewModel, compactSize: isCompactWidth, initialUIHidden: !statusBarVisible)
            documentController.parentDelegate = self
            documentController.coordinatorDelegate = coordinatorDelegate
            documentController.view.translatesAutoresizingMaskIntoConstraints = false

            let sidebarController = PDFSidebarViewController(viewModel: viewModel)
            sidebarController.parentDelegate = self
            sidebarController.coordinatorDelegate = coordinatorDelegate
            sidebarController.boundingBoxConverter = documentController
            sidebarController.view.translatesAutoresizingMaskIntoConstraints = false

            let separator = UIView()
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.backgroundColor = Asset.Colors.annotationSidebarBorderColor.color

            let annotationToolbar = AnnotationToolbarViewController(tools: [.highlight, .underline, .note, .freeText, .image, .ink, .eraser], undoRedoEnabled: true, size: navigationBarHeight)
            annotationToolbar.delegate = self

            let intraDocumentNavigationHandler = IntraDocumentNavigationButtonsHandler(
                back: { [weak self] in
                    self?.documentController?.performBackAction()
                },
                forward: { [weak self] in
                    self?.documentController?.performForwardAction()
                },
                delegate: self
            )
            let backButton = intraDocumentNavigationHandler.backButton
            let forwardButton = intraDocumentNavigationHandler.forwardButton

            add(controller: documentController)
            add(controller: sidebarController)
            add(controller: annotationToolbar)
            view.addSubview(topSafeAreaSpacer)
            view.addSubview(documentController.view)
            view.addSubview(sidebarController.view)
            view.addSubview(separator)
            view.addSubview(annotationToolbar.view)
            view.addSubview(backButton)
            view.addSubview(forwardButton)

            let documentLeftConstraint = documentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            let sidebarLeftConstraint = sidebarController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -PDFReaderLayout.sidebarWidth)
            documentTop = documentController.view.topAnchor.constraint(equalTo: view.topAnchor)

            NSLayoutConstraint.activate([
                topSafeAreaSpacer.topAnchor.constraint(equalTo: view.topAnchor),
                topSafeAreaSpacer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                topSafeAreaSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                topSafeAreaSpacer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                sidebarController.view.topAnchor.constraint(equalTo: view.topAnchor),
                sidebarController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                sidebarController.view.widthAnchor.constraint(equalToConstant: PDFReaderLayout.sidebarWidth),
                sidebarLeftConstraint,
                separator.widthAnchor.constraint(equalToConstant: PDFReaderLayout.separatorWidth),
                separator.trailingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor),
                separator.topAnchor.constraint(equalTo: view.topAnchor),
                separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                documentController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                documentTop,
                documentController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                documentLeftConstraint,
                backButton.leadingAnchor.constraint(equalTo: documentController.view.leadingAnchor, constant: 20),
                documentController.view.bottomAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 40),
                forwardButton.trailingAnchor.constraint(equalTo: documentController.view.trailingAnchor, constant: -20),
                forwardButton.heightAnchor.constraint(equalTo: backButton.heightAnchor),
                forwardButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor)
            ])

            self.documentController = documentController
            documentControllerLeft = documentLeftConstraint
            self.sidebarController = sidebarController
            sidebarControllerLeft = sidebarLeftConstraint
            annotationToolbarController = annotationToolbar
            self.intraDocumentNavigationHandler = intraDocumentNavigationHandler

            annotationToolbarHandler = AnnotationToolbarHandler(controller: annotationToolbar, delegate: self)
            annotationToolbarHandler.didHide = { [weak self] in
                self?.documentController.disableAnnotationTools()
            }
            annotationToolbarHandler.performInitialLayout()

            func add(controller: UIViewController) {
                controller.willMove(toParent: self)
                addChild(controller)
                controller.didMove(toParent: self)
            }
        }

        func setupNavigationBar() {
            let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"), style: .plain, target: nil, action: nil)
            sidebarButton.isEnabled = !viewModel.state.document.isLocked
            setupAccessibility(forSidebarButton: sidebarButton)
            sidebarButton.tag = NavigationBarButton.sidebar.rawValue
            sidebarButton.rx.tap.subscribe(onNext: { [weak self] _ in self?.toggleSidebar(animated: true) }).disposed(by: disposeBag)

            let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
            closeButton.title = L10n.close
            closeButton.accessibilityLabel = L10n.close
            closeButton.rx.tap.subscribe(onNext: { [weak self] _ in self?.close(dismiss: true) }).disposed(by: disposeBag)

            let readerButton = UIBarButtonItem(image: Asset.Images.pdfRawReader.image, style: .plain, target: nil, action: nil)
            readerButton.isEnabled = !viewModel.state.document.isLocked
            readerButton.accessibilityLabel = L10n.Accessibility.Pdf.openReader
            readerButton.title = L10n.Accessibility.Pdf.openReader
            readerButton.rx.tap
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    coordinatorDelegate?.showReader(document: viewModel.state.document, userInterfaceStyle: viewModel.state.settings.appearanceMode.userInterfaceStyle)
                })
                .disposed(by: disposeBag)

            navigationItem.leftBarButtonItems = [closeButton, sidebarButton, readerButton]
            navigationItem.rightBarButtonItems = createRightBarButtonItems(for: viewModel.state)
        }

        func setupObserving() {
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] state in
                    self?.update(state: state)
                })
                .disposed(by: disposeBag)

            if let sessionIdentifier {
                openItemsController.observable(for: sessionIdentifier)
                    .observe(on: MainScheduler.instance)
                    .subscribe(onNext: { [weak self] items in
                        self?.viewModel.process(action: .updateOpenItems(items: items))
                    })
                    .disposed(by: disposeBag)
            }

            NotificationCenter.default.rx
                .notification(UIApplication.didBecomeActiveNotification)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    if let previousTraitCollection {
                        updateUserInterfaceStyleIfNeeded(previousTraitCollection: previousTraitCollection)
                    }
                    viewModel.process(action: .updateAnnotationPreviews)
                    documentController.didBecomeActive()
                })
                .disposed(by: disposeBag)

            NotificationCenter.default.rx
                .notification(UIApplication.willResignActiveNotification)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    previousTraitCollection = traitCollection
                    if let page = documentController?.pdfController?.pageIndex {
                        viewModel.process(action: .submitPendingPage(Int(page)))
                    }
                })
                .disposed(by: disposeBag)
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        let editingEnabled = viewModel.state.library.metadataEditable && !viewModel.state.document.isLocked
        annotationToolbarHandler.viewIsAppearing(editingEnabled: editingEnabled)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    deinit {
        viewModel.process(action: .changeIdleTimerDisabled(false))
        DDLogInfo("PDFReaderViewController deinitialized")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if documentController.view.frame.width < AnnotationToolbarHandler.minToolbarWidth && toolbarState.visible && toolbarState.position == .top {
            closeAnnotationToolbar()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateUserInterfaceStyleIfNeeded(previousTraitCollection: previousTraitCollection)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        isCompactWidth = UIDevice.current.isCompactWidth(size: size)

        guard viewIfLoaded != nil else { return }

        if isSidebarVisible {
            documentControllerLeft.constant = isCompactWidth ? 0 : PDFReaderLayout.sidebarWidth
            // If the layout is compact and toolbar is visible, then close it.
            if isCompactWidth && toolbarState.visible {
                closeAnnotationToolbar()
            }
        }

        coordinator.animate { [weak self] _ in
            guard let self else { return }
            annotationToolbarHandler.viewWillTransitionToNewSize()
            intraDocumentNavigationHandler?.containerViewWillTransitionToNewSize()
        }
    }

    override var prefersStatusBarHidden: Bool {
        return !statusBarVisible
    }

    // MARK: - Actions

    private func update(state: PDFReaderState) {
        if state.changes.contains(.md5) {
            coordinatorDelegate?.showDocumentChangedAlert { [weak self] in
                self?.close(dismiss: true)
            }
            return
        }

        if let success = state.unlockSuccessful, success {
            // Enable bar buttons
            for item in navigationItem.leftBarButtonItems ?? [] {
                item.isEnabled = true
            }
            for item in navigationItem.rightBarButtonItems ?? [] {
                item.isEnabled = true
                guard let checkbox = item.customView as? CheckboxButton else { continue }
                checkbox.deselectedTintColor = Asset.Colors.zoteroBlueWithDarkMode.color
            }
            interfaceVisibilityDidChange(to: !toolbarState.visible)
            // Load initial document data after document has been unlocked successfully
            viewModel.process(action: .loadDocumentData(boundingBoxConverter: documentController))
        }

        if state.changes.contains(.selectionDeletion) {
            // Hide popover if annotation has been deleted
            if let navigationController = presentedViewController as? UINavigationController, navigationController.viewControllers.first is AnnotationPopover, !navigationController.isBeingDismissed {
                dismiss(animated: true, completion: nil)
            }
        }

        if state.changes.contains(.appearance) {
            updateInterface(to: state.settings)
        }

        if state.changes.contains(.export) {
            update(state: state.exportState)
        }

        if state.changes.contains(.initialDataLoaded) {
            if state.selectedAnnotation != nil {
                toggleSidebar(animated: false)
            }
        }

        if state.changes.contains(.library) {
            let hidden = !state.library.metadataEditable || !toolbarState.visible
            if !state.library.metadataEditable {
                documentController.disableAnnotationTools()
            }
            annotationToolbarHandler.set(hidden: hidden, animated: true)
            (toolbarButton.customView as? CheckboxButton)?.isSelected = toolbarState.visible
        }
        if state.changes.contains(.library) || state.changes.contains(.openItems) {
            navigationItem.rightBarButtonItems = createRightBarButtonItems(for: state)
        }

        if let tool = state.changedColorForTool, documentController.pdfController?.annotationStateManager.state == tool, let color = state.toolColors[tool] {
            annotationToolbarController.set(activeColor: color)
        }

        if let error = state.error {
            coordinatorDelegate?.show(error: error)
        }

        func update(state: PDFExportState?) {
            var items = navigationItem.rightBarButtonItems ?? []

            guard let shareId = items.firstIndex(where: { $0.tag == NavigationBarButton.share.rawValue }) else { return }

            guard let state else {
                if items[shareId].customView != nil { // if activity indicator is visible, replace it with share button
                    items[shareId] = shareButton
                    navigationItem.rightBarButtonItems = items
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
                items[shareId] = shareButton
                coordinatorDelegate?.share(url: file.createUrl(), barButton: shareButton)

            case .failed(let error):
                DDLogError("PDFReaderViewController: could not export pdf - \(error)")
                coordinatorDelegate?.show(error: error)
                items[shareId] = shareButton
            }

            navigationItem.rightBarButtonItems = items
        }
    }

    private func updateInterface(to settings: PDFSettings) {
        switch settings.appearanceMode {
        case .automatic:
            navigationController?.overrideUserInterfaceStyle = .unspecified

        case .light, .sepia:
            navigationController?.overrideUserInterfaceStyle = .light

        case .dark:
            navigationController?.overrideUserInterfaceStyle = .dark
        }
    }

    func showToolOptions() {
        if !annotationToolbarController.view.isHidden, !annotationToolbarController.colorPickerButton.isHidden {
            showToolOptions(sender: .view(annotationToolbarController.colorPickerButton, nil))
            return
        }

        guard let item = navigationItem.rightBarButtonItems?.last else { return }
        showToolOptions(sender: .item(item))
    }

    func showToolOptions(sender: SourceView) {
        guard let tool = documentController.pdfController?.annotationStateManager.state, let toolbarTool = tool.toolbarTool else { return }

        let colorHex = viewModel.state.toolColors[tool]?.hexString
        let size: Float?
        switch tool {
        case .ink:
            size = Float(viewModel.state.activeLineWidth)

        case .eraser:
            size = Float(viewModel.state.activeEraserSize)

        case .freeText:
            size = Float(self.viewModel.state.activeFontSize)

        default:
            size = nil
        }

        coordinatorDelegate?.showToolSettings(
            tool: toolbarTool,
            colorHex: colorHex,
            sizeValue: size,
            sender: sender,
            userInterfaceStyle: viewModel.state.settings.appearanceMode.userInterfaceStyle
        ) { [weak self] newColor, newSize in
            self?.viewModel.process(action: .setToolOptions(color: newColor, size: newSize.flatMap(CGFloat.init), tool: tool))
        }
    }

    private func toggleSidebar(animated: Bool) {
        let shouldShow = !isSidebarVisible

        // If the layout is compact, show annotation sidebar above pdf document.
        if !isCompactWidth {
            documentControllerLeft.constant = shouldShow ? PDFReaderLayout.sidebarWidth : 0
        } else if shouldShow && toolbarState.visible {
            closeAnnotationToolbar()
        }
        sidebarControllerLeft.constant = shouldShow ? 0 : -PDFReaderLayout.sidebarWidth
        if toolbarState.visible {
            annotationToolbarHandler.recalculateConstraints()
        }

        if let button = navigationItem.leftBarButtonItems?.first(where: { $0.tag == NavigationBarButton.sidebar.rawValue }) {
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

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 5, options: [.curveEaseOut], animations: { [weak self] in
            guard let self else { return }
            annotationToolbarController.prepareForSizeChange()
            view.layoutIfNeeded()
            annotationToolbarController.sizeDidChange()
        }, completion: { [weak self] finished in
            guard let self, finished else { return }
            if !shouldShow {
                sidebarController.view.isHidden = true
            }
        })
    }

    private func updateUserInterfaceStyleIfNeeded(previousTraitCollection: UITraitCollection?) {
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        viewModel.process(action: .userInterfaceStyleChanged(traitCollection.userInterfaceStyle))
    }

    func showSearch(pdfController: PDFViewController, text: String?) {
        coordinatorDelegate?.showSearch(
            pdfController: pdfController,
            text: text,
            sender: searchButton,
            userInterfaceStyle: viewModel.state.settings.appearanceMode.userInterfaceStyle,
            delegate: self
        )
    }

    private func showSettings(sender: UIBarButtonItem) {
        guard let settingsViewModel = coordinatorDelegate?.showSettings(with: viewModel.state.settings, sender: sender) else { return }
        settingsViewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                guard let self else { return }
                let settings = PDFSettings(
                    transition: state.transition,
                    pageMode: state.pageMode,
                    direction: state.scrollDirection,
                    pageFitting: state.pageFitting,
                    appearanceMode: state.appearance,
                    isFirstPageAlwaysSingle: state.isFirstPageAlwaysSingle
                )
                viewModel.process(action: .setSettings(settings: settings))
            })
            .disposed(by: disposeBag)
    }

    private func close(dismiss: Bool) {
        if let page = documentController?.pdfController?.pageIndex {
            viewModel.process(action: .submitPendingPage(Int(page)))
        }
        viewModel.process(action: .clearTmpData)
        guard dismiss else { return }
        navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    @objc private func search() {
        guard let pdfController = documentController.pdfController else { return }
        showSearch(pdfController: pdfController, text: nil)
    }

    @objc private func performBackAction() {
        documentController.performBackAction()
    }

    @objc private func performForwardAction() {
        documentController.performForwardAction()
    }

    @objc private func undo(_ sender: Any?) {
        performUndo()
    }

    @objc private func redo(_ sender: Any?) {
        performRedo()
    }

    // MARK: - Setups

    private func setupAccessibility(forSidebarButton button: UIBarButtonItem) {
        button.accessibilityLabel = isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
        button.title = isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
    }

    private func createRightBarButtonItems(for state: PDFReaderState) -> [UIBarButtonItem] {
        var buttons = [settingsButton, shareButton, searchButton]
        if FeatureGates.enabled.contains(.multipleOpenItems) {
            buttons.insert(openItemsButton, at: 1)
            openItemsButton.image = .openItemsImage(count: state.openItemsCount)
        }

        if state.library.metadataEditable {
            buttons.append(toolbarButton)
        }

        return buttons
    }
}

extension PDFReaderViewController {
    // MARK: - UIResponderStandardEditActions
    override func copy(_ sender: Any?) {
        UIPasteboard.general.string = selectedText
    }
}

extension PDFReaderViewController: PDFReaderContainerDelegate {
    var documentTopOffset: CGFloat {
        documentTop.constant
    }
}

extension PDFReaderViewController: AnnotationToolbarHandlerDelegate {
    var statusBarHeight: CGFloat {
        guard let view = viewIfLoaded else { return 0 }
        if let statusBarManager = (view.scene as? UIWindowScene)?.statusBarManager, !statusBarManager.isStatusBarHidden {
            return statusBarManager.statusBarFrame.height
        } else {
            return max(view.safeAreaInsets.top - (navigationController?.isNavigationBarHidden == true ? 0 : navigationBarHeight), 0)
        }
    }

    var isNavigationBarHidden: Bool {
        navigationController?.navigationBar.isHidden ?? false
    }

    var navigationBarHeight: CGFloat {
        return navigationController?.navigationBar.frame.height ?? 0.0
    }

    var additionalToolbarInsets: NSDirectionalEdgeInsets {
        let top = documentTopOffset
        let leading = isSidebarVisible ? documentControllerLeft.constant : 0
        return NSDirectionalEdgeInsets(top: top, leading: leading, bottom: 0, trailing: 0)
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

    func setNavigationBar(hidden: Bool, animated: Bool) {
        navigationController?.setNavigationBarHidden(hidden, animated: animated)
    }

    func setNavigationBar(alpha: CGFloat) {
        navigationController?.navigationBar.alpha = alpha
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

    func hideSidebarIfNeeded(forPosition position: AnnotationToolbarHandler.State.Position, isToolbarSmallerThanMinWidth: Bool, animated: Bool) {
        guard isSidebarVisible && (position == .pinned || (position == .top && isToolbarSmallerThanMinWidth)) else { return }
        toggleSidebar(animated: animated)
    }

    func setDocumentInterface(hidden: Bool) {
        documentController.setInterface(hidden: hidden)
    }

    func updateStatusBar() {
        navigationController?.setNeedsStatusBarAppearanceUpdate()
        setNeedsStatusBarAppearanceUpdate()
    }
}

extension PDFReaderViewController: AnnotationToolbarDelegate {
    func closeAnnotationToolbar() {
        (toolbarButton.customView as? CheckboxButton)?.isSelected = false
        annotationToolbarHandler.set(hidden: true, animated: true)
    }

    var activeAnnotationTool: AnnotationTool? {
        return documentController.pdfController?.annotationStateManager.state?.toolbarTool
    }

    var maxAvailableToolbarSize: CGFloat {
        guard toolbarState.visible, let documentController else { return 0 }

        switch toolbarState.position {
        case .top, .pinned:
            return isCompactWidth ? documentController.view.frame.size.width : (documentController.view.frame.size.width - (2 * AnnotationToolbarHandler.toolbarFullInset))

        case .trailing, .leading:
            let interfaceIsHidden = navigationController?.isNavigationBarHidden ?? false
            var documentAvailableHeight = documentController.view.frame.height - documentController.view.safeAreaInsets.bottom
            if !interfaceIsHidden, let scrubberBarFrame = documentController.pdfController?.userInterfaceView.scrubberBar.frame {
                documentAvailableHeight = min(scrubberBarFrame.minY, documentAvailableHeight)
            }
            if let intraDocumentNavigationHandler {
                if toolbarState.position == .leading, intraDocumentNavigationHandler.showsBackButton {
                    documentAvailableHeight = min(intraDocumentNavigationHandler.backButton.frame.minY, documentAvailableHeight)
                } else if toolbarState.position == .trailing, intraDocumentNavigationHandler.showsForwardButton {
                    documentAvailableHeight = min(intraDocumentNavigationHandler.forwardButton.frame.minY, documentAvailableHeight)
                }
            }
            return documentAvailableHeight - (2 * AnnotationToolbarHandler.toolbarCompactInset)
        }
    }

    func toggle(tool: AnnotationTool, options: AnnotationToolOptions) {
        let pspdfkitTool = tool.pspdfkitTool
        let color = viewModel.state.toolColors[pspdfkitTool]
        documentController.toggle(annotationTool: pspdfkitTool, color: color, tappedWithStylus: (options == .stylus))
    }

    var canUndo: Bool {
        return viewModel.state.document.undoController.undoManager.canUndo
    }

    func performUndo() {
        viewModel.state.document.undoController.undoManager.undo()
    }

    var canRedo: Bool {
        return viewModel.state.document.undoController.undoManager.canRedo
    }

    func performRedo() {
        viewModel.state.document.undoController.undoManager.redo()
    }
}

extension PDFReaderViewController: SidebarDelegate {
    func tableOfContentsSelected(page: UInt) {
        documentController.focus(page: page)
        if UIDevice.current.userInterfaceIdiom == .phone {
            toggleSidebar(animated: true)
        }
    }
}

extension PDFReaderViewController: AnnotationsDelegate {
    func parseAndCacheIfNeededAttributedText(for annotation: any PDFAnnotation, with font: UIFont) -> NSAttributedString? {
        guard let text = annotation.text, !text.isEmpty else { return nil }

        if let attributedText = viewModel.state.texts[annotation.key]?.1[font] {
            return attributedText
        }

        viewModel.process(action: .parseAndCacheText(key: annotation.key, text: text, font: font))
        return viewModel.state.texts[annotation.key]?.1[font]
    }

    func parseAndCacheIfNeededAttributedComment(for annotation: PDFAnnotation) -> NSAttributedString? {
        let comment = annotation.comment
        guard !comment.isEmpty else { return nil }

        if let attributedComment = viewModel.state.comments[annotation.key] {
            return attributedComment
        }

        viewModel.process(action: .parseAndCacheComment(key: annotation.key, comment: comment))
        return viewModel.state.comments[annotation.key]
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
            annotationToolbarController.set(selected: false, to: state, color: nil)
        }

        if let state = newState {
            let color = viewModel.state.toolColors[state]
            if let tool = state.toolbarTool {
                annotationToolbarController.set(selected: true, to: tool, color: color)
            }
        }
    }

    func didChange(undoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        annotationToolbarController.didChange(undoState: undoEnabled, redoState: redoEnabled)
    }

    func interfaceVisibilityDidChange(to isHidden: Bool) {
        let shouldChangeNavigationBarVisibility = !toolbarState.visible || toolbarState.position != .pinned

        if !isHidden && shouldChangeNavigationBarVisibility && navigationController?.navigationBar.isHidden == true {
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.navigationBar.alpha = 0
        }

        statusBarVisible = !isHidden
        annotationToolbarHandler.interfaceVisibilityDidChange()

        UIView.animate(withDuration: 0.15, animations: { [weak self] in
            guard let self else { return }
            updateStatusBar()
            view.layoutIfNeeded()
            if shouldChangeNavigationBarVisibility {
                navigationController?.navigationBar.alpha = isHidden ? 0 : 1
                navigationController?.setNavigationBarHidden(isHidden, animated: false)
            }
            annotationToolbarHandler.interfaceVisibilityDidChange()
        })

        if isHidden && isSidebarVisible {
            toggleSidebar(animated: true)
        }
    }

    func navigationButtonsChanged(backVisible: Bool, forwardVisible: Bool) {
        intraDocumentNavigationHandler?.set(backButtonVisible: backVisible, forwardButtonVisible: forwardVisible)
    }

    func didSelectText(_ text: String) {
        selectedText = text.isEmpty ? nil : text
    }
}

extension PDFReaderViewController: ConflictViewControllerReceiver {
    func shows(object: SyncObject, libraryId: LibraryIdentifier) -> String? {
        guard object == .item && libraryId == viewModel.state.library.identifier else { return nil }
        return viewModel.state.key
    }

    func canDeleteObject(completion: @escaping (Bool) -> Void) {
        coordinatorDelegate?.showDeletedAlertForPdf(completion: completion)
    }
}

extension PDFReaderViewController: AnnotationBoundingBoxConverter {
    func convertFromDb(rect: CGRect, page: PageIndex) -> CGRect? {
        return documentController.convertFromDb(rect: rect, page: page)
    }

    func convertFromDb(point: CGPoint, page: PageIndex) -> CGPoint? {
        return documentController.convertFromDb(point: point, page: page)
    }

    func convertToDb(rect: CGRect, page: PageIndex) -> CGRect? {
        return documentController.convertToDb(rect: rect, page: page)
    }

    func convertToDb(point: CGPoint, page: PageIndex) -> CGPoint? {
        return documentController.convertToDb(point: point, page: page)
    }

    func sortIndexMinY(rect: CGRect, page: PageIndex) -> CGFloat? {
        return documentController.sortIndexMinY(rect: rect, page: page)
    }

    func textOffset(rect: CGRect, page: PageIndex) -> Int? {
        return documentController.textOffset(rect: rect, page: page)
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

extension PDFReaderViewController: IntraDocumentNavigationButtonsHandlerDelegate { }
