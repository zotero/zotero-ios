//
//  PDFReaderViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RxSwift
import RealmSwift

final class PDFReaderViewController: UIViewController {
    private enum NavigationBarButton: Int {
        case redo = 1
        case undo = 2
        case share = 3
    }

    private weak var annotationsController: AnnotationsViewController!
    private weak var pdfController: PDFViewController!
    private weak var annotationsControllerLeft: NSLayoutConstraint!
    private weak var pdfControllerLeft: NSLayoutConstraint!
    // Annotation toolbar
    private weak var createNoteButton: CheckboxButton!
    private weak var createHighlightButton: CheckboxButton!
    private weak var createAreaButton: CheckboxButton!
    private weak var createInkButton: CheckboxButton!
    private weak var colorPickerbutton: UIButton!

    private static let saveDelay: Int = 3
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    private var isCompactSize: Bool
    private var isSidebarTransitioning: Bool
    private var annotationTimerDisposeBag: DisposeBag
    private var pageTimerDisposeBag: DisposeBag
    private var itemToken: NotificationToken?
    private var selectionView: SelectionView?
    /// These 3 keys sets are used to skip unnecessary realm notifications, which are created by user actions and would result in duplicate actions.
    private var insertedKeys: Set<String>
    private var deletedKeys: Set<String>
    private var modifiedKeys: Set<String>

    private lazy var shareButton: UIBarButtonItem = {
        let share = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)
        share.accessibilityLabel = L10n.Accessibility.Pdf.export
        share.tag = NavigationBarButton.share.rawValue
        share.rx.tap
             .subscribe(onNext: { [weak self] _ in
                 self?.viewModel.process(action: .export)
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
                  self?.showSearch(sender: search)
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

    weak var coordinatorDelegate: (DetailPdfCoordinatorDelegate & DetailAnnotationsCoordinatorDelegate)?

    var isSidebarVisible: Bool {
        return self.annotationsControllerLeft.constant == 0
    }

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>, compactSize: Bool) {
        self.viewModel = viewModel
        self.isCompactSize = compactSize
        self.insertedKeys = []
        self.deletedKeys = []
        self.modifiedKeys = []
        self.isSidebarTransitioning = false
        self.disposeBag = DisposeBag()
        self.annotationTimerDisposeBag = DisposeBag()
        self.pageTimerDisposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemGray6
        self.setupViews()
        self.setupNavigationBar()
        self.setupAnnotationControls(forCompactSize: self.isCompactSize)
        self.set(toolColor: self.viewModel.state.activeColor, in: self.pdfController.annotationStateManager)
        self.set(lineWidth: self.viewModel.state.activeLineWidth, in: self.pdfController.annotationStateManager)
        self.setupObserving()
        self.updateInterface(to: self.viewModel.state.settings)

        self.viewModel.process(action: .loadDocumentData)
        self.pdfController.setPageIndex(PageIndex(self.viewModel.state.visiblePage), animated: false)
    }

    deinit {
        self.viewModel.process(action: .changeIdleTimerDisabled(false))
        self.pdfController?.annotationStateManager.remove(self)
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

        if self.isSidebarVisible && sizeDidChange {
            self.pdfControllerLeft.constant = isCompactSize ? 0 : PDFReaderLayout.sidebarWidth
        }

        coordinator.animate(alongsideTransition: { _ in
            if sizeDidChange {
                self.navigationItem.rightBarButtonItems = self.createRightBarButtonItems(forCompactSize: isCompactSize)
                self.setupAnnotationControls(forCompactSize: isCompactSize)
                self.view.layoutIfNeeded()
            }

            // Update highlight selection if needed
            if let annotation = self.viewModel.state.selectedAnnotation,
               let pageView = self.pdfController.pageViewForPage(at: self.pdfController.pageIndex) {
                self.updateSelection(on: pageView, annotation: annotation)
            }
        }, completion: nil)
    }

    // MARK: - Actions

    private func update(state: PDFReaderState) {
        if state.changes.contains(.itemObserving) {
            self.setupItemObserving(items: state.dbItems)
        }

        if state.changes.contains(.interfaceStyle) {
            self.updateInterface(to: state.settings)
        }

        if state.changes.contains(.settings) {
            self.updateInterface(to: state.settings)

            if self.pdfController.configuration.scrollDirection != state.settings.direction ||
               self.pdfController.configuration.pageTransition != state.settings.transition {
                self.pdfController.updateConfiguration { configuration in
                    configuration.scrollDirection = state.settings.direction
                    configuration.pageTransition = state.settings.transition
                }
            }
        }

        if state.changes.contains(.selection) {
            if let annotation = state.selectedAnnotation {
                if let location = state.focusDocumentLocation {
                    // If annotation was selected, focus if needed
                    self.focus(annotation: annotation, at: location, document: state.document)
                } else {
                    // Update selection if needed
                    self.select(annotation: annotation, pageIndex: self.pdfController.pageIndex, document: state.document)
                }
            } else {
                // Otherwise remove selection if needed
                self.select(annotation: nil, pageIndex: self.pdfController.pageIndex, document: state.document)
            }

            self.showPopupAnnotationIfNeeded(state: state)
        }

        if state.changes.contains(.activeColor) {
            self.set(toolColor: state.activeColor, in: self.pdfController.annotationStateManager)
            self.colorPickerbutton.tintColor = state.activeColor
        }

        if state.changes.contains(.activeLineWidth) {
            self.set(lineWidth: state.activeLineWidth, in: self.pdfController.annotationStateManager)
        }

        if state.changes.contains(.save) {
            // If popover with deleted key is presented, dismiss it
            if let controller = (self.presentedViewController as? UINavigationController)?.viewControllers.first as? AnnotationPopover, state.deletedKeys.contains(controller.annotationKey) {
                self.dismiss(animated: true, completion: nil)
            }
            // Store changed keys and enqueue a save
            self.insertedKeys = self.insertedKeys.union(state.insertedKeys)
            self.deletedKeys = self.deletedKeys.union(state.deletedKeys)
            self.modifiedKeys = self.modifiedKeys.union(state.modifiedKeys)
            self.enqueueAnnotationSave()
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

    private func updateInterface(to settings: PDFSettingsState) {
        switch settings.appearanceMode {
        case .automatic:
            self.pdfController.appearanceModeManager.appearanceMode = self.traitCollection.userInterfaceStyle == .dark ? .night : []
            self.navigationController?.overrideUserInterfaceStyle = .unspecified
        case .light:
            self.pdfController.appearanceModeManager.appearanceMode = []
            self.navigationController?.overrideUserInterfaceStyle = .light
        case .dark:
            self.pdfController.appearanceModeManager.appearanceMode = .night
            self.navigationController?.overrideUserInterfaceStyle = .dark
        }
    }

    private func enqueueAnnotationSave() {
        self.annotationTimerDisposeBag = DisposeBag()
        Single<Int>.timer(.seconds(PDFReaderViewController.saveDelay), scheduler: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.viewModel.process(action: .saveChanges)
                   })
                   .disposed(by: self.annotationTimerDisposeBag)
    }

    private func enqueueSave(for page: Int) {
        guard page != self.viewModel.state.visiblePage else { return }
        self.pageTimerDisposeBag = DisposeBag()
        Single<Int>.timer(.seconds(PDFReaderViewController.saveDelay), scheduler: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.viewModel.process(action: .setVisiblePage(page))
                   })
                   .disposed(by: self.pageTimerDisposeBag)
    }

    private func showPopupAnnotationIfNeeded(state: PDFReaderState) {
        guard !self.isSidebarVisible,
              let annotation = state.selectedAnnotation,
              let pageView = self.pdfController.pageViewForPage(at: UInt(annotation.page)) else { return }

        let frame = self.view.convert(annotation.boundingBox, from: pageView.pdfCoordinateSpace)

        self.coordinatorDelegate?.showAnnotationPopover(viewModel: self.viewModel, sourceRect: frame, popoverDelegate: self)
    }

    private func toggle(annotationTool: PSPDFKit.Annotation.Tool) {
        let stateManager = self.pdfController.annotationStateManager

        if stateManager.state == annotationTool {
            stateManager.setState(nil, variant: nil)
            return
        }

        stateManager.setState(annotationTool, variant: nil)
        stateManager.drawColor = AnnotationColorGenerator.color(from: self.viewModel.state.activeColor, isHighlight: (annotationTool == .highlight),
                                                                userInterfaceStyle: self.traitCollection.userInterfaceStyle).color
        if annotationTool == .ink {
            stateManager.lineWidth = self.viewModel.state.activeLineWidth
        }
    }

    private func showColorPicker(sender: UIButton) {
        self.coordinatorDelegate?.showColorPicker(selected: self.viewModel.state.activeColor.hexString, sender: sender, save: { [weak self] color in
            self?.viewModel.process(action: .setActiveColor(color))
        })
    }

    private func toggleSidebar() {
        let shouldShow = !self.isSidebarVisible

        // If the layout is compact, show annotation sidebar above pdf document.
        if !UIDevice.current.isCompactWidth(size: self.view.frame.size) {
            self.pdfControllerLeft.constant = shouldShow ? PDFReaderLayout.sidebarWidth : 0
        }
        self.annotationsControllerLeft.constant = shouldShow ? 0 : -PDFReaderLayout.sidebarWidth

        if shouldShow {
            self.annotationsController.view.isHidden = false
        } else {
            self.view.endEditing(true)
        }

        self.isSidebarTransitioning = true
        self.navigationItem.leftBarButtonItems?.last?.accessibilityLabel = shouldShow ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen

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
                               self.annotationsController.view.isHidden = true
                           }
                           self.isSidebarTransitioning = false
                       })
    }

    private func showSearch(sender: UIBarButtonItem) {
        self.coordinatorDelegate?.showSearch(pdfController: self.pdfController, sender: sender, result: { [weak self] result in
            self?.highlight(result: result)
        })
    }

    private func highlight(result: SearchResult) {
        self.pdfController.searchHighlightViewManager.clearHighlightedSearchResults(animated: (self.pdfController.pageIndex == result.pageIndex))
        self.scrollIfNeeded(to: result.pageIndex, animated: true) {
            self.pdfController.searchHighlightViewManager.addHighlight([result], animated: true)
        }
    }

    /// Scrolls to given page if needed.
    /// - parameter pageIndex: Page index to which the `pdfController` is supposed to scroll.
    /// - parameter animated: `true` if scrolling is animated, `false` otherwise.
    /// - parameter completion: Completion block called after scroll. Block is also called when scroll was not needed.
    private func scrollIfNeeded(to pageIndex: PageIndex, animated: Bool, completion: @escaping () -> Void) {
        guard self.pdfController.pageIndex != pageIndex else {
            completion()
            return
        }

        if !animated {
            self.pdfController.setPageIndex(pageIndex, animated: false)
            completion()
            return
        }

        UIView.animate(withDuration: 0.25, animations: {
            self.pdfController.setPageIndex(pageIndex, animated: false)
        }, completion: { finished in
            guard finished else { return }
            completion()
        })
    }

    private func showSettings(sender: UIBarButtonItem) {
        self.coordinatorDelegate?.showSettings(state: self.viewModel.state.settings, sender: sender, completion: { [weak self] action in
            self?.viewModel.process(action: action)
        })
    }

    private func close() {
        self.viewModel.process(action: .saveChanges)
        self.viewModel.process(action: .clearTmpAnnotationPreviews)
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    private func set(toolColor: UIColor, in stateManager: AnnotationStateManager) {
        let highlightColor = AnnotationColorGenerator.color(from: toolColor, isHighlight: true,
                                                            userInterfaceStyle: self.traitCollection.userInterfaceStyle).color

        stateManager.setLastUsedColor(highlightColor, annotationString: .highlight)
        stateManager.setLastUsedColor(toolColor, annotationString: .note)
        stateManager.setLastUsedColor(toolColor, annotationString: .square)

        if stateManager.state == .highlight {
            stateManager.drawColor = highlightColor
        } else {
            stateManager.drawColor = toolColor
        }
    }

    private func set(lineWidth: CGFloat, in stateManager: AnnotationStateManager) {
        stateManager.lineWidth = lineWidth
    }

    private func add(controller: UIViewController) {
        controller.willMove(toParent: self)
        self.addChild(controller)
        self.view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    private func processAnnotationObserving(notification: Notification) {
        guard self.isNotificationFromDocument(notification) else { return }

        switch notification.name {
        case .PSPDFAnnotationChanged:
            guard let pdfAnnotation = notification.object as? PSPDFKit.Annotation, let key = pdfAnnotation.key else { return }
            if self.viewModel.state.ignoreNotifications[.PSPDFAnnotationChanged]?.contains(key) == true {
                self.viewModel.process(action: .annotationChangeNotificationReceived(key))
            } else {
                self.viewModel.process(action: .annotationChanged(pdfAnnotation))
            }

        case .PSPDFAnnotationsAdded:
            if let annotations = self.annotations(for: notification) {
                // Open annotation popup for note annotation
                let shouldSelect = self.isSidebarVisible || annotations.first is PSPDFKit.NoteAnnotation
                // If Image annotation is active after adding the annotation, deactivate it
                if annotations.first is PSPDFKit.SquareAnnotation && self.pdfController.annotationStateManager.state == .square {
                    self.toggle(annotationTool: .square)
                }
                self.viewModel.process(action: .annotationsAdded(annotations: annotations, selectFirst: shouldSelect))
            } else {
                self.viewModel.process(action: .notificationReceived(notification.name))
            }

        case .PSPDFAnnotationsRemoved:
            if let annotations = self.annotations(for: notification) {
                self.viewModel.process(action: .annotationsRemoved(annotations))
            } else {
                self.viewModel.process(action: .notificationReceived(notification.name))
            }

        default: break
        }
    }

    private func isNotificationFromDocument(_ notification: Notification) -> Bool {
        if let annotation = notification.object as? PSPDFKit.Annotation {
            return annotation.document == self.viewModel.state.document
        }
        if let annotations = notification.object as? [PSPDFKit.Annotation], let annotation = annotations.first {
            return annotation.document == self.viewModel.state.document
        }
        return false
    }

    private func annotations(for notification: Notification) -> [PSPDFKit.Annotation]? {
        guard let annotations = notification.object as? [PSPDFKit.Annotation] else { return nil }
        guard let keys = self.viewModel.state.ignoreNotifications[notification.name], !keys.isEmpty else { return annotations }
        if Set(annotations.compactMap({ $0.key })) == keys {
            return nil
        }
        return annotations
    }

    private func performObservingUpdateIfNeeded(objects: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int]) {
        let (filteredDeletions, filteredInsertions, filteredModifications) = self.filterObservingUpdateIndices(objects: objects, deletions: deletions,
                                                                                                               insertions: insertions, modifications: modifications)
        if !filteredDeletions.isEmpty || !filteredInsertions.isEmpty || !filteredModifications.isEmpty {
            // If there are any changes which need sync between database and memory, process them
            self.viewModel.process(action: .itemsChange(objects: objects, deletions: filteredDeletions, insertions: filteredInsertions, modifications: filteredModifications))
        }
        // Keep `dbPositions` in sync with database
        self.viewModel.process(action: .updateDbPositions(objects: objects, deletions: deletions, insertions: insertions))
    }

    private func filterObservingUpdateIndices(objects: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int]) -> (deletions: [Int], insertions: [Int], modifications: [Int]) {
        let filteredModifications = modifications.compactMap { index -> Int? in
            let key = self.viewModel.state.dbPositions[index].key
            // If this key was modified by user action, ignore it. Otherwise add it to filtered array, so that the action can be processed.
            return self.modifiedKeys.remove(key) == nil ? index : nil
        }
        let filteredDeletions = deletions.compactMap { index -> Int? in
            let key = self.viewModel.state.dbPositions[index].key
            // If this key was deleted by user action, ignore it. Otherwise add it to filtered array, so that the action can be processed.
            return self.deletedKeys.remove(key) == nil ? index : nil
        }
        let filteredInsertions = insertions.compactMap { index -> Int? in
            let key = objects[index].key
            // If this key was inserted by user action, ignore it. Otherwise add it to filtered array, so that the action can be processed.
            return self.insertedKeys.remove(key) == nil ? index : nil
        }
        return (filteredDeletions, filteredInsertions, filteredModifications)
    }

    // MARK: - Selection

    /// (De)Selects given annotation in document.
    /// - parameter annotation: Annotation to select. Existing selection will be deselected if set to `nil`.
    /// - parameter pageIndex: Page index of page where (de)selection should happen.
    /// - parameter document: Active `Document` instance.
    private func select(annotation: Annotation?, pageIndex: PageIndex, document: PSPDFKit.Document) {
        guard let pageView = self.pdfController.pageViewForPage(at: pageIndex) else { return }

        self.updateSelection(on: pageView, annotation: annotation)

        if let annotation = annotation, let pdfAnnotation = document.annotation(on: Int(pageIndex), with: annotation.key) {
            if !pageView.selectedAnnotations.contains(pdfAnnotation) {
                pageView.selectedAnnotations = [pdfAnnotation]
            }
        } else {
            if !pageView.selectedAnnotations.isEmpty {
                pageView.selectedAnnotations = []
            }
        }
    }

    /// Focuses given annotation and selects it if it's not selected yet.
    private func focus(annotation: Annotation, at location: AnnotationDocumentLocation, document: PSPDFKit.Document) {
        let pageIndex = PageIndex(location.page)
        self.scrollIfNeeded(to: pageIndex, animated: true) {
            self.select(annotation: annotation, pageIndex: pageIndex, document: document)
        }
    }

    /// Updates `SelectionView` for `PDFPageView` based on selected annotation.
    /// - parameter pageView: `PDFPageView` instance for given page.
    /// - parameter selectedAnnotation: Selected annotation or `nil` if there is no selection.
    private func updateSelection(on pageView: PDFPageView, annotation: Annotation?) {
        // Delete existing custom highlight selection view
        if let view = self.selectionView {
            view.removeFromSuperview()
        }

        guard let selection = annotation, selection.type == .highlight && selection.page == Int(pageView.pageIndex) else { return }
        // Add custom highlight selection view if needed
        let frame = pageView.convert(selection.boundingBox, from: pageView.pdfCoordinateSpace).insetBy(dx: -SelectionView.inset, dy: -SelectionView.inset)
        let selectionView = SelectionView()
        selectionView.frame = frame
        pageView.annotationContainerView.addSubview(selectionView)
        self.selectionView = selectionView
    }

    // MARK: - Setups

    private func setupViews() {
        let pdfController = self.createPdfController(with: self.viewModel.state.document, settings: self.viewModel.state.settings)
        pdfController.view.translatesAutoresizingMaskIntoConstraints = false

        let sidebarController = AnnotationsViewController(viewModel: self.viewModel)
        sidebarController.sidebarParent = self
        sidebarController.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarController.coordinatorDelegate = self.coordinatorDelegate

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
        self.annotationsController = sidebarController
        self.annotationsControllerLeft = sidebarLeftConstraint
    }

    private func createPdfController(with document: PSPDFKit.Document, settings: PDFSettingsState) -> PDFViewController {
        let pdfConfiguration = PDFConfiguration { builder in
            builder.scrollDirection = settings.direction
            builder.pageTransition = settings.transition
            builder.documentLabelEnabled = .NO
            builder.allowedAppearanceModes = [.night]
            builder.isCreateAnnotationMenuEnabled = true
            builder.createAnnotationMenuGroups = self.createAnnotationCreationMenuGroups()
            builder.allowedMenuActions = [.copy, .search, .speak, .share, .annotationCreation, .define]
            builder.scrubberBarType = .horizontal
            builder.thumbnailBarMode = .scrubberBar
            builder.markupAnnotationMergeBehavior = .never
            builder.overrideClass(PSPDFKit.HighlightAnnotation.self, with: HighlightAnnotation.self)
            builder.overrideClass(PSPDFKit.NoteAnnotation.self, with: NoteAnnotation.self)
            builder.overrideClass(PSPDFKit.SquareAnnotation.self, with: SquareAnnotation.self)
        }

        let controller = PDFViewController(document: document, configuration: pdfConfiguration)
        controller.view.backgroundColor = .systemGray6
        controller.delegate = self
        controller.formSubmissionDelegate = nil
        controller.annotationStateManager.add(self)
        self.setup(scrubberBar: controller.userInterfaceView.scrubberBar)
        self.setup(interactions: controller.interactions)
        return controller
    }

    private func createAnnotationCreationMenuGroups() -> [AnnotationToolConfiguration.ToolGroup] {
        return [AnnotationToolConfiguration.ToolGroup(items: [
                AnnotationToolConfiguration.ToolItem(type: .highlight),
                AnnotationToolConfiguration.ToolItem(type: .note),
                AnnotationToolConfiguration.ToolItem(type: .square),
                AnnotationToolConfiguration.ToolItem(type: .ink, variant: .inkPen)
        ])]
    }

    private func setup(scrubberBar: ScrubberBar) {
        let appearance = UIToolbarAppearance()
        appearance.backgroundColor = Asset.Colors.pdfScrubberBarBackground.color

        scrubberBar.standardAppearance = appearance
        scrubberBar.compactAppearance = appearance
    }

    private func setup(interactions: DocumentViewInteractions) {
        // Only supported annotations can be selected
        interactions.selectAnnotation.addActivationCondition { context, _, _ -> Bool in
            return AnnotationsConfig.supported.contains(context.annotation.type)
        }

        interactions.selectAnnotation.addActivationCallback { [weak self] context, _, _ in
            let key = context.annotation.key ?? context.annotation.uuid
            self?.viewModel.process(action: .selectAnnotationFromDocument(key: key, page: Int(context.pageView.pageIndex)))
        }

        interactions.deselectAnnotation.addActivationCondition { [weak self] _, _, _ -> Bool in
            // `interactions.deselectAnnotation.addActivationCallback` is not always called when highglight annotation tool is enabled.
            self?.viewModel.process(action: .selectAnnotation(nil))
            return true
        }

        // Only Zotero-synced annotations can be edited
        interactions.editAnnotation.addActivationCondition { context, _, _ -> Bool in
            return context.annotation.syncable && context.annotation.isEditable
        }
    }

    private func setupAnnotationControls(forCompactSize isCompact: Bool) {
        let buttons = self.createAnnotationControlButtons()
        self.navigationController?.setToolbarHidden(!isCompact, animated: false)

        if !isCompact {
            self.navigationController?.toolbarItems = nil
            let stackView = UIStackView(arrangedSubviews: buttons)
            stackView.spacing = 14
            self.navigationItem.titleView = stackView
            return
        }

        let flexibleSpacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let fixedSpacer = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpacer.width = 20

        // Create toolbar items from `UIButton`s
        var toolbarItems = buttons.map({ UIBarButtonItem(customView: $0) })
        // Add undo/redo buttons
        toolbarItems += [self.undoButton, self.redoButton]
        // Insert flexible spacers between each item
        toolbarItems = (0..<((2 * toolbarItems.count) - 1)).map({ $0 % 2 == 0 ? toolbarItems[$0/2] : flexibleSpacer })
        // Insert fixed spacer on sides
        toolbarItems.insert(fixedSpacer, at: 0)
        toolbarItems.insert(fixedSpacer, at: toolbarItems.count)

        self.navigationItem.titleView = nil
        self.toolbarItems = toolbarItems
    }

    private func createAnnotationControlButtons() -> [UIButton] {
        switch self.viewModel.state.library.identifier {
        case .group: return []
        case .custom: break
        }
        // TODO: - group editing temporarily disabled
//        guard self.viewModel.state.library.metadataEditable else {
//            return []
//        }

        let symbolConfig = UIImage.SymbolConfiguration(scale: .large)

        let highlight = CheckboxButton(type: .custom)
        highlight.accessibilityLabel = L10n.Accessibility.Pdf.highlightAnnotationTool
        highlight.setImage(Asset.Images.Annotations.highlighterLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        highlight.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        highlight.rx
                 .controlEvent(.touchDown)
                 .subscribe(onNext: { [weak self] _ in
                    self?.toggle(annotationTool: .highlight)
                 })
                 .disposed(by: self.disposeBag)
        self.createHighlightButton = highlight

        let note = CheckboxButton(type: .custom)
        note.accessibilityLabel = L10n.Accessibility.Pdf.noteAnnotationTool
        note.setImage(Asset.Images.Annotations.noteLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        note.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        note.rx
            .controlEvent(.touchDown)
            .subscribe(onNext: { [weak self] _ in
                self?.toggle(annotationTool: .note)
            })
            .disposed(by: self.disposeBag)
        self.createNoteButton = note

        let area = CheckboxButton(type: .custom)
        area.accessibilityLabel = L10n.Accessibility.Pdf.imageAnnotationTool
        area.setImage(Asset.Images.Annotations.areaLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        area.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        area.rx
            .controlEvent(.touchDown)
            .subscribe(onNext: { [weak self] _ in
                self?.toggle(annotationTool: .square)
            })
            .disposed(by: self.disposeBag)
        self.createAreaButton = area

        let inkLongPress = UILongPressGestureRecognizer()
        inkLongPress.rx
                    .event
                    .subscribe(with: self, onNext: { `self`, recognizer in
                        if recognizer.state == .began, let view = recognizer.view {
                            self.coordinatorDelegate?.showInkSettings(sender: view, viewModel: self.viewModel)
                            if self.pdfController.annotationStateManager.state != .ink {
                                self.toggle(annotationTool: .ink)
                            }
                        }
                    })
                    .disposed(by: self.disposeBag)

        let inkTap = UITapGestureRecognizer()
        inkTap.rx
              .event
              .subscribe(with: self, onNext: { `self`, _ in
                  self.toggle(annotationTool: .ink)
              })
              .disposed(by: self.disposeBag)
        inkTap.require(toFail: inkLongPress)

        let ink = CheckboxButton(type: .custom)
        ink.accessibilityLabel = L10n.Accessibility.Pdf.inkAnnotationTool
        ink.setImage(Asset.Images.Annotations.inkLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        ink.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        ink.addGestureRecognizer(inkLongPress)
        ink.addGestureRecognizer(inkTap)
        self.createInkButton = ink

        [highlight, note, area, ink].forEach { button in
            button.adjustsImageWhenHighlighted = false
            button.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
            button.selectedTintColor = .white
            button.layer.cornerRadius = 4
            button.layer.masksToBounds = true
        }

        let picker = UIButton()
        picker.accessibilityLabel = L10n.Accessibility.Pdf.colorPicker
        picker.setImage(UIImage(systemName: "circle.fill", withConfiguration: symbolConfig), for: .normal)
        picker.tintColor = self.viewModel.state.activeColor
        picker.rx.controlEvent(.touchUpInside)
                 .subscribe(onNext: { [weak self] _ in
                    self?.showColorPicker(sender: picker)
                 })
                 .disposed(by: self.disposeBag)
        self.colorPickerbutton = picker

        let size: CGFloat = 36

        NSLayoutConstraint.activate([
            highlight.widthAnchor.constraint(equalToConstant: size),
            highlight.heightAnchor.constraint(equalToConstant: size),
            note.widthAnchor.constraint(equalToConstant: size),
            note.heightAnchor.constraint(equalToConstant: size),
            area.widthAnchor.constraint(equalToConstant: size),
            area.heightAnchor.constraint(equalToConstant: size),
            ink.widthAnchor.constraint(equalToConstant: size),
            ink.heightAnchor.constraint(equalToConstant: size),
            picker.widthAnchor.constraint(equalToConstant: size),
            picker.heightAnchor.constraint(equalToConstant: size),
        ])

        return [highlight, note, area, ink, picker]
    }

    private func setupNavigationBar() {
        let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"), style: .plain, target: nil, action: nil)
        sidebarButton.accessibilityLabel = self.isSidebarVisible ? L10n.Accessibility.Pdf.sidebarClose : L10n.Accessibility.Pdf.sidebarOpen
        sidebarButton.rx.tap
                     .subscribe(with: self, onNext: { `self`, _ in self.toggleSidebar() })
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

        NotificationCenter.default.rx
                                  .notification(.PSPDFAnnotationChanged)
                                  .observe(on: MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      self?.processAnnotationObserving(notification: notification)
                                  })
                                  .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(.PSPDFAnnotationsAdded)
                                  .observe(on: MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in

                                      self?.processAnnotationObserving(notification: notification)
                                  })
                                  .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(.PSPDFAnnotationsRemoved)
                                  .observe(on: MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      self?.processAnnotationObserving(notification: notification)
                                  })
                                  .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(UIApplication.didBecomeActiveNotification)
                                  .observe(on: MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      guard let `self` = self else { return }
                                      self.viewModel.process(action: .updateAnnotationPreviews)
                                  })
                                  .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(UIApplication.willResignActiveNotification)
                                  .observe(on: MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      guard let `self` = self else { return }
                                      self.viewModel.process(action: .saveChanges)
                                      self.viewModel.process(action: .clearTmpAnnotationPreviews)
                                  })
                                  .disposed(by: self.disposeBag)
    }

    private func setupItemObserving(items: Results<RItem>?) {
        guard let items = items else {
            self.itemToken = nil
            return
        }

        self.itemToken = items.observe({ [weak self] changes in
            switch changes {
            case .update(let objects, let deletions, let insertions, let modifications):
                self?.performObservingUpdateIfNeeded(objects: objects, deletions: deletions, insertions: insertions, modifications: modifications)
            case .initial, .error: break
            }
        })
    }
}

extension PDFReaderViewController: PDFViewControllerDelegate {
    func pdfViewController(_ pdfController: PDFViewController, willBeginDisplaying pageView: PDFPageView, forPageAt pageIndex: Int) {
        // This delegate method is called for incorrect page index when sidebar is changing size. So if the sidebar is opened/closed, incorrect page
        // is stored in `pageController` and if the user closes the pdf reader without further scrolling, incorrect page is shown on next opening.
        guard !self.isSidebarTransitioning else { return }
        // Save current page
        self.enqueueSave(for: pageIndex)
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldShow controller: UIViewController, options: [String : Any]? = nil, animated: Bool) -> Bool {
        return false
    }

    func pdfViewController(_ pdfController: PDFViewController,
                           shouldShow menuItems: [MenuItem],
                           atSuggestedTargetRect rect: CGRect,
                           for annotations: [PSPDFKit.Annotation]?,
                           in annotationRect: CGRect,
                           on pageView: PDFPageView) -> [MenuItem] {
        guard annotations == nil else { return [] }

        // TODO: - group editing disabled temporarily
        switch self.viewModel.state.library.identifier {
        case .group: return []
        case .custom: break
        }

        let pageRect = pageView.convert(rect, to: pageView.pdfCoordinateSpace)

        return [MenuItem(title: "Note", block: { [weak self] in
                    self?.viewModel.process(action: .create(annotation: .note, pageIndex: pageView.pageIndex, origin: pageRect.origin))
                }),
                MenuItem(title: "Image", block: { [weak self] in
                    self?.viewModel.process(action: .create(annotation: .image, pageIndex: pageView.pageIndex, origin: pageRect.origin))
                })]
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldShow menuItems: [MenuItem], atSuggestedTargetRect rect: CGRect,
                           forSelectedText selectedText: String, in textRect: CGRect, on pageView: PDFPageView) -> [MenuItem] {
        let identifiers: [String]
        // TODO: - group editing disabled temporarily
        switch self.viewModel.state.library.identifier {
        case .custom: identifiers = [TextMenu.copy.rawValue, TextMenu.annotationMenuHighlight.rawValue, TextMenu.define.rawValue, TextMenu.search.rawValue, TextMenu.speak.rawValue, TextMenu.share.rawValue]
        case .group: identifiers = [TextMenu.copy.rawValue, TextMenu.define.rawValue, TextMenu.search.rawValue, TextMenu.speak.rawValue, TextMenu.share.rawValue]
        }

        // Filter unwanted items
        let filtered = menuItems.filter({ item in
            guard let identifier = item.identifier else { return false }
            if identifier == TextMenu.define.rawValue {
                return UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: selectedText)
            }
            return identifiers.contains(identifier)
        })

        // Overwrite share action, because the original one reports "[ShareSheet] connection invalidated".
        if let idx = filtered.firstIndex(where: { $0.identifier == TextMenu.share.rawValue }) {
            filtered[idx].actionBlock = { [weak self] in
                guard let view = self?.pdfController.view else { return }
                self?.coordinatorDelegate?.share(text: selectedText, rect: rect, view: view)
            }
        }

        // Overwrite define action, because the original one doesn't show anything.
        if let idx = filtered.firstIndex(where: { $0.identifier == TextMenu.define.rawValue }) {
            filtered[idx].title = L10n.lookup
            filtered[idx].actionBlock = { [weak self] in
                guard let view = self?.pdfController.view else { return }
                self?.coordinatorDelegate?.lookup(text: selectedText, rect: rect, view: view)
            }
        }

        return filtered
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldSave document: PSPDFKit.Document, withOptions options: AutoreleasingUnsafeMutablePointer<NSDictionary>) -> Bool {
        return false
    }
}

extension PDFReaderViewController: AnnotationStateManagerDelegate {
    func annotationStateManager(_ manager: AnnotationStateManager,
                                didChangeState oldState: PSPDFKit.Annotation.Tool?,
                                to newState: PSPDFKit.Annotation.Tool?,
                                variant oldVariant: PSPDFKit.Annotation.Variant?,
                                to newVariant: PSPDFKit.Annotation.Variant?) {
        if let state = oldState {
            switch state {
            case .note:
                self.createNoteButton.isSelected = false
            case .highlight:
                self.createHighlightButton.isSelected = false
            case .square:
                self.createAreaButton.isSelected = false
            case .ink:
                self.createInkButton.isSelected = false
            default: break
            }
        }

        if let state = newState {
            switch state {
            case .note:
                self.createNoteButton.isSelected = true
            case .highlight:
                self.createHighlightButton.isSelected = true
            case .square:
                self.createAreaButton.isSelected = true
            case .ink:
                self.createInkButton.isSelected = true
            default: break
            }
        }
    }

    func annotationStateManager(_ manager: AnnotationStateManager, didChangeUndoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        self.redoButton.isEnabled = redoEnabled
        self.undoButton.isEnabled = undoEnabled
    }
}

extension PDFReaderViewController: UIPopoverPresentationControllerDelegate {
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        if self.viewModel.state.selectedAnnotation?.type == .highlight {
            self.viewModel.process(action: .selectAnnotation(nil))
        }
        return true
    }
}

extension PDFReaderViewController: AnnotationBoundingBoxConverter {
    /// Converts from database to PSPDFKit rect. Database stores rects in RAW PDF Coordinate space. PSPDFKit works with Normalized PDF Coordinate Space.
    func convertFromDb(rect: CGRect, page: PageIndex) -> CGRect? {
        guard let pageInfo = self.viewModel.state.document.pageInfoForPage(at: page) else { return nil }
        return rect.applying(pageInfo.transform)
    }

    /// Converts from PSPDFKit to database rect. Database stores rects in RAW PDF Coordinate space. PSPDFKit works with Normalized PDF Coordinate Space.
    func convertToDb(rect: CGRect, page: PageIndex) -> CGRect? {
        guard let pageInfo = self.viewModel.state.document.pageInfoForPage(at: page) else { return nil }
        return rect.applying(pageInfo.transform.inverted())
    }

    /// Converts from PSPDFKit to sort index rect. PSPDFKit works with Normalized PDF Coordinate Space. Sort index stores y coordinate in RAW View Coordinate Space.
    func sortIndexMinY(rect: CGRect, page: PageIndex) -> CGFloat? {
        guard let pageInfo = self.viewModel.state.document.pageInfoForPage(at: page) else { return nil }

        switch pageInfo.savedRotation {
        case .rotation0:
            return pageInfo.size.height - rect.maxY
        case .rotation180:
            return rect.minY
        case .rotation90:
            return pageInfo.size.width - rect.minX
        case .rotation270:
            return rect.minX
        }
    }

    func textOffset(rect: CGRect, page: PageIndex) -> Int? {
        guard let parser = self.viewModel.state.document.textParserForPage(at: page), !parser.glyphs.isEmpty else { return nil }

        var index = 0
        var minDistance: CGFloat = .greatestFiniteMagnitude
        var textOffset = 0

        for glyph in parser.glyphs {
            guard !glyph.isWordOrLineBreaker else { continue }

            let distance = rect.distance(to: glyph.frame)

            if distance < minDistance {
                minDistance = distance
                textOffset = index
            }

            index += 1
        }

        return textOffset
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

extension PDFReaderViewController: SidebarParent {}

final class SelectionView: UIView {
    static let inset: CGFloat = 4.5 // 2.5 for border, 2 for padding

    init() {
        super.init(frame: CGRect())
        self.commonSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonSetup()
    }

    private func commonSetup() {
        self.backgroundColor = .clear
        self.autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin, .flexibleBottomMargin, .flexibleRightMargin, .flexibleWidth, .flexibleHeight]
        self.layer.borderColor = Asset.Colors.annotationHighlightSelection.color.cgColor
        self.layer.borderWidth = 2.5
        self.layer.cornerRadius = 2.5
        self.layer.masksToBounds = true
    }
}

#endif
