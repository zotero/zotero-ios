//
//  PDFReaderContainerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 31.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

protocol PDFReaderContainerDelegate: AnyObject {
    var isSidebarVisible: Bool { get }
    var isSidebarTransitioning: Bool { get }

    func showSearch(sender: UIBarButtonItem, text: String?)
}

class PDFReaderContainerViewController: UIViewController {
    private enum NavigationBarButton: Int {
        case redo = 1
        case undo = 2
        case share = 3
    }

    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var sidebarController: PDFSidebarViewController!
    private weak var pdfController: PDFDocumentViewController!
    private weak var sidebarControllerLeft: NSLayoutConstraint!
    private weak var pdfControllerLeft: NSLayoutConstraint!
    private(set) var isSidebarTransitioning: Bool
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
        let settings = self.pdfController.settingsButtonItem
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
                  self?.showSearch(sender: search, text: nil)
              })
              .disposed(by: self.disposeBag)
        return search
    }()
    private lazy var undoButton: UIBarButtonItem = {
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
        return undo
    }()
    private lazy var redoButton: UIBarButtonItem = {
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
        return redo
    }()

    init(viewModel: ViewModel<PDFReaderActionHandler>, compactSize: Bool) {
        self.viewModel = viewModel
        self.isCompactSize = compactSize
        self.isSidebarTransitioning = false
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemGray6
        self.set(userActivity: .pdfActivity(for: self.viewModel.state.key, libraryId: self.viewModel.state.library.identifier))
        self.setupViews()
        self.setupNavigationBar()
        self.setupObserving()
        self.updateInterface(to: self.viewModel.state.settings)

        self.viewModel.process(action: .loadDocumentData(boundingBoxConverter: self.pdfController))

        if let annotation = self.viewModel.state.selectedAnnotation {
            self.toggleSidebar(animated: false)
        }
    }

    deinit {
        self.viewModel.process(action: .changeIdleTimerDisabled(false))
        self.coordinatorDelegate?.pdfDidDeinitialize()
        DDLogInfo("PDFReaderContainerViewController deinitialized")
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
            self.pdfControllerLeft.constant = isCompactSize ? 0 : PDFReaderLayout.sidebarWidth
        }

        coordinator.animate(alongsideTransition: { _ in
            if sizeDidChange {
                self.navigationItem.rightBarButtonItems = self.createRightBarButtonItems(forCompactSize: isCompactSize)
                self.view.layoutIfNeeded()
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

        if state.changes.contains(.activeColor) {
            self.colorPickerbutton.tintColor = state.activeColor
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
            DDLogInfo("PDFReaderContainerViewController: share pdf file - \(file.createUrl().absoluteString)")
            items[shareId] = self.shareButton
            self.coordinatorDelegate?.share(url: file.createUrl(), barButton: self.shareButton)

        case .failed(let error):
            DDLogError("PDFReaderContainerViewController: could not export pdf - \(error)")
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

    private func showColorPicker(sender: UIButton) {
        self.coordinatorDelegate?.showColorPicker(selected: self.viewModel.state.activeColor.hexString, sender: sender, save: { [weak self] color in
            self?.viewModel.process(action: .setActiveColor(color))
        })
    }

    private func toggleSidebar(animated: Bool) {
        let shouldShow = !self.isSidebarVisible

        // If the layout is compact, show annotation sidebar above pdf document.
        if !UIDevice.current.isCompactWidth(size: self.view.frame.size) {
            self.pdfControllerLeft.constant = shouldShow ? PDFReaderLayout.sidebarWidth : 0
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

    func showSearch(sender: UIBarButtonItem, text: String?) {
        self.coordinatorDelegate?.showSearch(pdfController: self.pdfController, text: text, sender: sender, result: { [weak self] result in
            self?.pdfController.highlight(result: result)
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

    @objc private func annotationControlTapped(sender: UIButton, event: UIEvent) {
        let tool: PSPDFKit.Annotation.Tool
        if sender == self.createNoteButton {
            tool = .note
        } else if sender == self.createAreaButton {
            tool = .square
        } else if sender == self.createHighlightButton {
            tool = .highlight
        } else if sender == self.createEraserButton {
            tool = .eraser
        } else {
            fatalError()
        }

        let isStylus = event.allTouches?.first?.type == .stylus

        self.pdfController.toggle(annotationTool: tool, tappedWithStylus: isStylus)
    }

    // MARK: - Setups

    private func add(controller: UIViewController) {
        controller.willMove(toParent: self)
        self.addChild(controller)
        self.view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    private func setupViews() {
        let pdfController = PDFDocumentViewController(viewModel: self.viewModel, compactSize: self.isCompactSize)
        pdfController.parent = self
        pdfController.coordinatorDelegate = self.coordinatorDelegate
        pdfController.view.translatesAutoresizingMaskIntoConstraints = false

        let sidebarController = PDFSidebarViewController(viewModel: self.viewModel)
        sidebarController.parent = self
        sidebarController.coordinatorDelegate = self.coordinatorDelegate
        sidebarController.boundingBoxConverter = self.pdfController
        sidebarController.view.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = Asset.Colors.annotationSidebarBorderColor.color

        self.add(controller: pdfController)
        self.add(controller: sidebarController)
        self.view.addSubview(separator)

        let pdfLeftConstraint = pdfController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
        let sidebarLeftConstraint = sidebarController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: -PDFReaderLayout.sidebarWidth)

        NSLayoutConstraint.activate([
            sidebarController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            sidebarController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            sidebarController.view.widthAnchor.constraint(equalToConstant: PDFReaderLayout.sidebarWidth),
            sidebarLeftConstraint,
            separator.widthAnchor.constraint(equalToConstant: PDFReaderLayout.separatorWidth),
            separator.leadingAnchor.constraint(equalTo: sidebarController.view.trailingAnchor),
            separator.topAnchor.constraint(equalTo: self.view.topAnchor),
            separator.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            pdfController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            pdfController.view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            pdfController.view.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            pdfLeftConstraint
        ])

        self.pdfController = pdfController
        self.pdfControllerLeft = pdfLeftConstraint
        self.sidebarController = sidebarController
        self.sidebarControllerLeft = sidebarLeftConstraint
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
        let readerButton = UIBarButtonItem(image: self.pdfController.readerViewButtonItem.image, style: .plain, target: nil, action: nil)
        readerButton.accessibilityLabel = self.isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
        readerButton.rx.tap
                    .subscribe(with: self, onNext: { `self`, _ in self.coordinatorDelegate?.showReader(document: self.viewModel.state.document) })
                    .disposed(by: self.disposeBag)

        self.navigationItem.leftBarButtonItems = [closeButton, sidebarButton, readerButton]
        self.navigationItem.rightBarButtonItems = self.createRightBarButtonItems(forCompactSize: self.isCompactSize)
    }

    private func createRightBarButtonItems(forCompactSize isCompact: Bool) -> [UIBarButtonItem] {
        if isCompact {
            return [self.settingsButton, self.shareButton, self.searchButton]
        }
        return [self.settingsButton, self.shareButton, self.redoButton, self.undoButton, self.searchButton]
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

extension PDFReaderContainerViewController: PDFReaderContainerDelegate {}

extension PDFReaderContainerViewController: SidebarDelegate {
    func tableOfContentsSelected(page: UInt) {
        self.pdfController.focus(page: page)
        if UIDevice.current.userInterfaceIdiom == .phone {
            self.toggleSidebar(animated: true)
        }
    }
}

extension PDFReaderContainerViewController: ConflictViewControllerReceiver {
    func shows(object: SyncObject, libraryId: LibraryIdentifier) -> String? {
        guard object == .item && libraryId == self.viewModel.state.library.identifier else { return nil }
        return self.viewModel.state.key
    }

    func canDeleteObject(completion: @escaping (Bool) -> Void) {
        self.coordinatorDelegate?.showDeletedAlertForPdf(completion: completion)
    }
}

#endif
