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

class PDFReaderViewController: UIViewController {
    private enum NavigationBarButton: Int {
        case redo = 1
        case undo = 2
    }

    private let viewModel: ViewModel<PDFReaderActionHandler>
    private unowned let annotationPreviewController: AnnotationPreviewController
    private unowned let pageController: PdfPageController
    private let disposeBag: DisposeBag

    private weak var annotationsController: AnnotationsViewController!
    private weak var pdfController: PDFViewController!
    private weak var annotationsControllerLeft: NSLayoutConstraint!
    private weak var pdfControllerLeft: NSLayoutConstraint!
    private var isCompactSize: Bool
    private var isSidebarTransitioning: Bool
    weak var coordinatorDelegate: (DetailPdfCoordinatorDelegate & DetailAnnotationsCoordinatorDelegate)?
    // Annotation toolbar
    private weak var createNoteButton: CheckboxButton!
    private weak var createHighlightButton: CheckboxButton!
    private weak var createAreaButton: CheckboxButton!
    private weak var colorPickerbutton: UIButton!

    private var isSidebarOpened: Bool {
        return self.annotationsControllerLeft.constant == 0
    }

    private var defaultScrollDirection: ScrollDirection {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: "PdfReader.ScrollDirection")
            return ScrollDirection(rawValue: UInt(rawValue)) ?? .horizontal
        }

        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "PdfReader.ScrollDirection")
        }
    }

    private var defaultPageTransition: PageTransition {
        get {
            let rawValue = UserDefaults.standard.integer(forKey: "PdfReader.PageTransition")
            return PageTransition(rawValue: UInt(rawValue)) ?? .scrollPerSpread
        }

        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "PdfReader.PageTransition")
        }
    }

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>, compactSize: Bool, annotationPreviewController: AnnotationPreviewController, pageController: PdfPageController) {
        self.viewModel = viewModel
        self.isCompactSize = compactSize
        self.annotationPreviewController = annotationPreviewController
        self.pageController = pageController
        self.isSidebarTransitioning = false
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .secondarySystemBackground
        self.setupViews()
        self.setupNavigationBar()
        self.setupAnnotationControls(forCompactSize: self.isCompactSize)
        self.set(toolColor: self.viewModel.state.activeColor, in: self.pdfController.annotationStateManager)
        self.setupObserving()

        self.viewModel.process(action: .loadAnnotations(self.traitCollection.userInterfaceStyle))
    }

    deinit {
        self.pdfController?.annotationStateManager.remove(self)
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

        guard self.isCompactSize != isCompactSize else { return }

        self.isCompactSize = isCompactSize

        if self.isSidebarOpened {
            self.pdfControllerLeft.constant = isCompactSize ? 0 : PDFReaderLayout.sidebarWidth
        }

        coordinator.animate(alongsideTransition: { _ in
            self.navigationItem.rightBarButtonItems = self.createRightBarButtonItems(forCompactSize: isCompactSize)
            self.setupAnnotationControls(forCompactSize: isCompactSize)
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

    // MARK: - Actions

    private func update(state: PDFReaderState) {
        if state.changes.contains(.darkMode) {
            self.pdfController.appearanceModeManager.appearanceMode = self.traitCollection.userInterfaceStyle == .dark ? .night : .init(rawValue: 0)
        }

        if state.changes.contains(.selection) {
            if let pageView = self.pdfController.pageViewForPage(at: self.pdfController.pageIndex) {
                self.updateSelection(on: pageView, selectedAnnotation: state.selectedAnnotation, pageIndex: Int(self.pdfController.pageIndex))
            }
            self.showPopupAnnotationIfNeeded(state: state)
        }

        if state.changes.contains(.activeColor) {
            self.set(toolColor: state.activeColor, in: self.pdfController.annotationStateManager)
            self.colorPickerbutton.tintColor = state.activeColor
        }

        if let location = state.focusDocumentLocation,
           let key = state.selectedAnnotation?.key {
            self.focusAnnotation(at: location, key: key, document: state.document)
        }
    }

    private func showPopupAnnotationIfNeeded(state: PDFReaderState) {
        guard UIDevice.current.userInterfaceIdiom == .pad && !self.isSidebarOpened,
              let annotation = state.selectedAnnotation,
              let pageView = self.pdfController.pageViewForPage(at: UInt(annotation.page)) else { return }

        let frame = pageView.convert(annotation.boundingBox, from: pageView.pdfCoordinateSpace)
        self.coordinatorDelegate?.showAnnotationPopover(viewModel: self.viewModel, sourceRect: frame,
                                                        dismissHandler: { [weak self] in
                                                            self?.viewModel.process(action: .selectAnnotation(nil))
                                                        })
    }

    private func updateSelection(on pageView: PDFPageView, selectedAnnotation: Annotation?, pageIndex: Int) {
        // Delete existing custom highlight selection view
        if let view = pageView.annotationContainerView.subviews.first(where: { $0 is SelectionView }) {
            view.removeFromSuperview()
        }

        if let selection = selectedAnnotation,
           selection.type == .highlight && selection.page == pageIndex {
            // Add custom highlight selection view if needed
            let frame = pageView.convert(selection.boundingBox, from: pageView.pdfCoordinateSpace).insetBy(dx: -SelectionView.inset, dy: -SelectionView.inset)
            let selectionView = SelectionView()
            selectionView.frame = frame
            pageView.annotationContainerView.addSubview(selectionView)
        }
    }

    private func toggle(annotationTool: PSPDFKit.Annotation.Tool) {
        let stateManager = self.pdfController.annotationStateManager

        if stateManager.state == annotationTool {
            stateManager.setState(nil, variant: nil)
            return
        }

        stateManager.drawColor = AnnotationColorGenerator.color(from: self.viewModel.state.activeColor, isHighlight: (annotationTool == .highlight),
                                                                userInterfaceStyle: self.traitCollection.userInterfaceStyle).color

        self.pdfController.annotationStateManager.setState(annotationTool, variant: nil)
    }

    private func showColorPicker(sender: UIButton) {
        self.coordinatorDelegate?.showColorPicker(selected: self.viewModel.state.activeColor.hexString, sender: sender, save: { [weak self] color in
            self?.viewModel.process(action: .setActiveColor(color))
        })
    }

    private func focusAnnotation(at location: AnnotationDocumentLocation, key: String, document: Document) {
        let pageIndex = PageIndex(location.page)
        self.scrollIfNeeded(to: pageIndex, animated: true) {
            guard let pageView = self.pdfController.pageViewForPage(at: pageIndex),
                  let annotation = document.annotation(on: location.page, with: key) else { return }

            if !pageView.selectedAnnotations.contains(annotation) {
                pageView.selectedAnnotations = [annotation]
            }

            if annotation is HighlightAnnotation {
                self.updateSelection(on: pageView, selectedAnnotation: self.viewModel.state.selectedAnnotation, pageIndex: location.page)
            }
        }
    }

    private func toggleSidebar() {
        let shouldShow = !self.isSidebarOpened

        // If the layout is compact, show annotation sidebar above pdf document.
        if !UIDevice.current.isCompactWidth(size: self.view.frame.size) {
            self.pdfControllerLeft.constant = shouldShow ? PDFReaderLayout.sidebarWidth : 0
        }
        self.annotationsControllerLeft.constant = shouldShow ? 0 : -PDFReaderLayout.sidebarWidth

        if shouldShow {
            self.annotationsController.view.isHidden = false
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
        let direction = self.pdfController.configuration.scrollDirection
        let directionTitle = direction == .horizontal ? L10n.Pdf.ScrollDirection.horizontal : L10n.Pdf.ScrollDirection.vertical
        let transition = self.pdfController.configuration.pageTransition
        let transitionTitle = transition == .scrollContinuous ? L10n.Pdf.PageTransition.continuous : L10n.Pdf.PageTransition.jump

        let controller = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        controller.popoverPresentationController?.barButtonItem = sender
        controller.addAction(UIAlertAction(title: L10n.Pdf.scrollDirection(directionTitle), style: .default, handler: { [weak self] _ in
            self?.toggleScrollDirection(from: direction)
        }))
        controller.addAction(UIAlertAction(title: L10n.Pdf.pageTransition(transitionTitle), style: .default, handler: { [weak self] _ in
            self?.togglePageTransition(from: transition)
        }))
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        self.present(controller, animated: true, completion: nil)
    }

    private func toggleScrollDirection(from direction: ScrollDirection) {
        let newDirection: ScrollDirection = direction == .horizontal ? .vertical : .horizontal
        self.defaultScrollDirection = newDirection
        self.pdfController.updateConfiguration { builder in
            builder.scrollDirection = newDirection
        }
    }

    private func togglePageTransition(from transition: PageTransition) {
        let newTransition: PageTransition = transition == .scrollPerSpread ? .scrollContinuous : .scrollPerSpread
        self.defaultPageTransition = newTransition
        self.pdfController.updateConfiguration { builder in
            builder.pageTransition = newTransition
        }
    }

    private func close() {
        self.viewModel.process(action: .saveChanges)
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

    private func add(controller: UIViewController) {
        controller.willMove(toParent: self)
        self.addChild(controller)
        self.view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    // MARK: - Setups

    private func setupViews() {
        let pdfController = self.createPdfController(with: self.viewModel.state.document)
        pdfController.view.translatesAutoresizingMaskIntoConstraints = false

        let sidebarController = AnnotationsViewController(viewModel: self.viewModel)
        sidebarController.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarController.coordinatorDelegate = self.coordinatorDelegate

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
            return traitCollection.userInterfaceStyle == .light ? UIColor(hex: "#C6C6C8") : .systemGray4
        })

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
            pdfController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            pdfController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            pdfLeftConstraint
        ])

        self.pdfController = pdfController
        self.pdfControllerLeft = pdfLeftConstraint
        self.annotationsController = sidebarController
        self.annotationsControllerLeft = sidebarLeftConstraint
    }

    private func createPdfController(with document: Document) -> PDFViewController {
        let pdfConfiguration = PDFConfiguration { builder in
            builder.scrollDirection = .horizontal
            builder.documentLabelEnabled = .NO
            builder.allowedAppearanceModes = [.night]
            builder.isCreateAnnotationMenuEnabled = true
            builder.createAnnotationMenuGroups = self.createAnnotationCreationMenuGroups()
            builder.allowedMenuActions = [.copy, .search, .speak, .share, .annotationCreation]
            builder.scrubberBarType = .horizontal
            builder.thumbnailBarMode = .scrubberBar
        }

        let controller = PDFViewController(document: document, configuration: pdfConfiguration)
        controller.view.backgroundColor = .systemGray6
        controller.delegate = self
        controller.formSubmissionDelegate = nil
        if self.traitCollection.userInterfaceStyle == .dark {
            controller.appearanceModeManager.appearanceMode = .night
        }
        controller.setPageIndex(PageIndex(self.pageController.page(for: self.viewModel.state.key)), animated: false)
        controller.annotationStateManager.add(self)
        self.setup(scrubberBar: controller.userInterfaceView.scrubberBar)
        self.setup(interactions: controller.interactions)
        return controller
    }

    private func createAnnotationCreationMenuGroups() -> [AnnotationToolConfiguration.ToolGroup] {
        return [AnnotationToolConfiguration.ToolGroup(items: [
            AnnotationToolConfiguration.ToolItem(type: .highlight),
            AnnotationToolConfiguration.ToolItem(type: .note),
            AnnotationToolConfiguration.ToolItem(type: .square)
        ])]
    }

    private func setup(scrubberBar: ScrubberBar) {
        let appearance = UIToolbarAppearance()
        appearance.backgroundColor = Asset.Colors.pdfScrubberBarBackground.color

        scrubberBar.standardAppearance = appearance
        scrubberBar.compactAppearance = appearance
    }

    private func setup(interactions: DocumentViewInteractions) {
        interactions.selectAnnotation.addActivationCondition { context, _, _ -> Bool in
            return context.annotation.isZotero
        }

        interactions.selectAnnotation.addActivationCallback { [weak self] context, _, _ in
            guard let key = context.annotation.key else { return }
            self?.viewModel.process(action: .selectAnnotationFromDocument(key: key, page: Int(context.pageView.pageIndex)))
        }

        interactions.deselectAnnotation.addActivationCallback { [weak self] _, _, _ in
            self?.viewModel.process(action: .selectAnnotation(nil))
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
        let (undo, redo) = self.createUndoRedoButtons()
        toolbarItems += [undo, redo]
        // Insert flexible spacers between each item
        toolbarItems = (0..<((2 * toolbarItems.count) - 1)).map({ $0 % 2 == 0 ? toolbarItems[$0/2] : flexibleSpacer })
        // Insert fixed spacer on sides
        toolbarItems.insert(fixedSpacer, at: 0)
        toolbarItems.insert(fixedSpacer, at: toolbarItems.count)

        self.navigationItem.titleView = nil
        self.toolbarItems = toolbarItems
    }

    private func createAnnotationControlButtons() -> [UIButton] {
        guard self.viewModel.state.library.metadataEditable else {
            return []
        }

        let symbolConfig = UIImage.SymbolConfiguration(scale: .large)

        let highlight = CheckboxButton(type: .custom)
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
        area.setImage(Asset.Images.Annotations.areaLarge.image.withRenderingMode(.alwaysTemplate), for: .normal)
        area.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        area.rx
            .controlEvent(.touchDown)
            .subscribe(onNext: { [weak self] _ in
                self?.toggle(annotationTool: .square)
            })
            .disposed(by: self.disposeBag)
        self.createAreaButton = area


        [highlight, note, area].forEach { button in
            button.adjustsImageWhenHighlighted = false
            button.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
            button.selectedTintColor = .white
            button.layer.cornerRadius = 6
            button.layer.masksToBounds = true
        }

        let picker = UIButton()
        picker.setImage(UIImage(systemName: "circle.fill", withConfiguration: symbolConfig), for: .normal)
        picker.tintColor = self.viewModel.state.activeColor
        picker.rx.controlEvent(.touchUpInside)
                 .subscribe(onNext: { [weak self] _ in
                    self?.showColorPicker(sender: picker)
                 })
                 .disposed(by: self.disposeBag)
        self.colorPickerbutton = picker

        NSLayoutConstraint.activate([
            highlight.widthAnchor.constraint(equalToConstant: 44),
            highlight.heightAnchor.constraint(equalToConstant: 44),
            note.widthAnchor.constraint(equalToConstant: 44),
            note.heightAnchor.constraint(equalToConstant: 44),
            area.widthAnchor.constraint(equalToConstant: 44),
            area.heightAnchor.constraint(equalToConstant: 44),
            picker.widthAnchor.constraint(equalToConstant: 44),
            picker.heightAnchor.constraint(equalToConstant: 44),
        ])

        return [highlight, note, area, picker]
    }

    private func setupNavigationBar() {
        let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"),
                                            style: .plain, target: nil, action: nil)
        sidebarButton.rx.tap
                     .subscribe(onNext: { [weak self] in self?.toggleSidebar() })
                     .disposed(by: self.disposeBag)
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"),
                                          style: .plain, target: nil, action: nil)
        closeButton.rx.tap
                   .subscribe(onNext: { [weak self] in self?.close() })
                   .disposed(by: self.disposeBag)

        self.navigationItem.leftBarButtonItems = [closeButton, sidebarButton]
        self.navigationItem.rightBarButtonItems = self.createRightBarButtonItems(forCompactSize: self.isCompactSize)
    }

    private func createRightBarButtonItems(forCompactSize isCompact: Bool) -> [UIBarButtonItem] {
        let settings = self.pdfController.settingsButtonItem
        settings.rx
                .tap
                .subscribe(onNext: { [weak self] _ in
                    self?.showSettings(sender: settings)
                })
                .disposed(by: self.disposeBag)

        let search = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: nil, action: nil)
        search.rx.tap
              .subscribe(onNext: { [weak self] _ in
                  self?.showSearch(sender: search)
              })
              .disposed(by: self.disposeBag)

        if isCompact {
            return [settings, search]
        }

        let (undo, redo) = self.createUndoRedoButtons()

        return [settings, redo, undo, search]
    }

    private func createUndoRedoButtons() -> (undo: UIBarButtonItem, redo: UIBarButtonItem) {
        let undo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.left"), style: .plain, target: nil, action: nil)
        undo.isEnabled = self.pdfController.undoManager?.canUndo ?? false
        undo.tag = NavigationBarButton.undo.rawValue
        undo.rx
            .tap
            .subscribe(onNext: { [weak self] _ in
                self?.pdfController.undoManager?.undo()
            })
            .disposed(by: self.disposeBag)

        let redo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.right"), style: .plain, target: nil, action: nil)
        redo.isEnabled = self.pdfController.undoManager?.canRedo ?? false
        redo.tag = NavigationBarButton.redo.rawValue
        redo.rx
            .tap
            .subscribe(onNext: { [weak self] _ in
                self?.pdfController.undoManager?.redo()
            })
            .disposed(by: self.disposeBag)

        return (undo, redo)
    }

    private func setupObserving() {
        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(.PSPDFAnnotationChanged)
                                  .observeOn(MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      guard let `self` = self else { return }
                                      let isDark = self.traitCollection.userInterfaceStyle == .dark
                                      if let annotation = notification.object as? PSPDFKit.Annotation {
                                          self.viewModel.process(action: .annotationChanged(annotation, isDark: isDark))
                                      }
                                  })
                                  .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(.PSPDFAnnotationsAdded)
                                  .observeOn(MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      guard let `self` = self else { return }
                                      let isDark = self.traitCollection.userInterfaceStyle == .dark
                                      if let annotations = notification.object as? [PSPDFKit.Annotation] {
                                          self.viewModel.process(action: .annotationsAdded(annotations, isDark: isDark))
                                      }
                                  })
                                  .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(.PSPDFAnnotationsRemoved)
                                  .observeOn(MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      if let annotations = notification.object as? [PSPDFKit.Annotation] {
                                          self?.viewModel.process(action: .annotationsRemoved(annotations))
                                      }
                                  })
                                  .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(UIApplication.didBecomeActiveNotification)
                                  .observeOn(MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      guard let `self` = self else { return }
                                      let isDark = self.traitCollection.userInterfaceStyle == .dark
                                      self.viewModel.process(action: .updateAnnotationPreviews(userInterfaceIsDark: isDark))
                                  })
                                  .disposed(by: self.disposeBag)
    }
}

extension PDFReaderViewController: PDFViewControllerDelegate {
    func pdfViewController(_ pdfController: PDFViewController, didConfigurePageView pageView: PDFPageView, forPageAt pageIndex: Int) {
        guard !self.isSidebarTransitioning,
              let selected = self.viewModel.state.selectedAnnotation,
              let annotation = self.viewModel.state.document.annotation(on: pageIndex, with: selected.key) else { return }

        if !pageView.selectedAnnotations.contains(annotation) {
            pageView.selectedAnnotations = [annotation]
        }
    }

    func pdfViewController(_ pdfController: PDFViewController, willBeginDisplaying pageView: PDFPageView, forPageAt pageIndex: Int) {
        // This delegate method is called for incorrect page index when sidebar is changing size. So if the sidebar is opened/closed, incorrect page
        // is stored in `pageController` and if the user closes the pdf reader without further scrolling, incorrect page is shown on next opening.
        guard !self.isSidebarTransitioning else { return }
        // Save current page
        self.pageController.store(page: pageIndex, for: self.viewModel.state.key)
    }

    func pdfViewController(_ pdfController: PDFViewController,
                           shouldShow controller: UIViewController,
                           options: [String : Any]? = nil,
                           animated: Bool) -> Bool {
        return false
    }

    func pdfViewController(_ pdfController: PDFViewController,
                           shouldShow menuItems: [MenuItem],
                           atSuggestedTargetRect rect: CGRect,
                           for annotations: [PSPDFKit.Annotation]?,
                           in annotationRect: CGRect,
                           on pageView: PDFPageView) -> [MenuItem] {
        guard annotations == nil else { return [] }

        let interfaceStyle = self.traitCollection.userInterfaceStyle
        let pageRect = pageView.convert(rect, to: pageView.pdfCoordinateSpace)

        return [MenuItem(title: "Note", block: { [weak self] in
                    self?.viewModel.process(action: .create(annotation: .note, pageIndex: pageView.pageIndex, origin: pageRect.origin, interfaceStyle: interfaceStyle))
                }),
                MenuItem(title: "Image", block: { [weak self] in
                    self?.viewModel.process(action: .create(annotation: .image, pageIndex: pageView.pageIndex, origin: pageRect.origin, interfaceStyle: interfaceStyle))
                })]
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldShow menuItems: [MenuItem], atSuggestedTargetRect rect: CGRect,
                           forSelectedText selectedText: String, in textRect: CGRect, on pageView: PDFPageView) -> [MenuItem] {
        return menuItems.filter({ $0.identifier != TextMenu.annotationMenuUnderline.rawValue && $0.identifier != TextMenu.annotationMenuSquiggle.rawValue &&
                                  $0.identifier != TextMenu.annotationMenuStrikeout.rawValue && $0.identifier != TextMenu.createLink.rawValue })
    }

    func pdfViewController(_ pdfController: PDFViewController,
                           shouldSave document: Document,
                           withOptions options: AutoreleasingUnsafeMutablePointer<NSDictionary>) -> Bool {
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
            default: break
            }
        }
    }

    func annotationStateManager(_ manager: AnnotationStateManager, didChangeUndoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        let redoItem: UIBarButtonItem?
        let undoItem: UIBarButtonItem?

        if let items = self.toolbarItems {
            redoItem = items.first(where: { $0.tag == NavigationBarButton.redo.rawValue })
            undoItem = items.first(where: { $0.tag == NavigationBarButton.undo.rawValue })
        } else {
            redoItem = self.navigationItem.rightBarButtonItems?.first(where: { $0.tag == NavigationBarButton.redo.rawValue })
            undoItem = self.navigationItem.rightBarButtonItems?.first(where: { $0.tag == NavigationBarButton.undo.rawValue })
        }

        redoItem?.isEnabled = redoEnabled
        undoItem?.isEnabled = undoEnabled
    }
}

class SelectionView: UIView {
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
