//
//  PDFDocumentViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import Combine

import CocoaLumberjackSwift
import PSPDFKit
import PSPDFKitUI
import RealmSwift
import RxSwift

protocol PDFDocumentDelegate: AnyObject {
    func annotationTool(
        didChangeStateFrom oldState: PSPDFKit.Annotation.Tool?,
        to newState: PSPDFKit.Annotation.Tool?,
        variantFrom oldVariant: PSPDFKit.Annotation.Variant?,
        to newVariant: PSPDFKit.Annotation.Variant?
    )
    func didChange(undoState undoEnabled: Bool, redoState redoEnabled: Bool)
    func interfaceVisibilityDidChange(to isHidden: Bool)
    func showToolOptions()
    func backNavigationButtonChanged(visible: Bool)
    func didSelectText(_ text: String)
}

final class PDFDocumentViewController: UIViewController {
    private(set) weak var pdfController: PDFViewController?
    private weak var unlockController: UnlockPDFViewController?

    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag
    private let initialUIHidden: Bool

    private static var toolHistory: [PSPDFKit.Annotation.Tool?] = []
    
    private var selectionView: SelectionView?
    // Used to decide whether text annotation should start editing on tap
    private var selectedAnnotationWasSelectedBefore: Bool
    var scrubberBarHeight: CGFloat {
        return self.pdfController?.userInterfaceView.scrubberBar.frame.height ?? 0
    }
    private var searchResults: [SearchResult] = []
    private var pageIndexCancellable: AnyCancellable?

    weak var parentDelegate: (PDFReaderContainerDelegate & PDFDocumentDelegate)?
    weak var coordinatorDelegate: PdfReaderCoordinatorDelegate?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>, compactSize: Bool, initialUIHidden: Bool) {
        self.viewModel = viewModel
        self.initialUIHidden = initialUIHidden
        self.selectedAnnotationWasSelectedBefore = false
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemGray6
        self.setupViews()
        self.setupObserving()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        self.setInterface(hidden: self.initialUIHidden)
        updateInterface(to: viewModel.state.settings.appearanceMode, userInterfaceStyle: traitCollection.userInterfaceStyle)
        if let (page, _) = self.viewModel.state.focusDocumentLocation, let annotation = self.viewModel.state.selectedAnnotation {
            self.select(annotation: annotation, pageIndex: PageIndex(page), document: self.viewModel.state.document)
        }
    }

    deinit {
        disableAnnotationTools()
        self.pdfController?.annotationStateManager.remove(self)
        DDLogInfo("PDFDocumentViewController deinitialized")
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard self.viewIfLoaded != nil else { return }

        coordinator.animate(alongsideTransition: { _ in
            // Update highlight selection if needed
            if let annotation = self.viewModel.state.selectedAnnotation, let pageIndex = self.pdfController?.pageIndex, let pageView = self.pdfController?.pageViewForPage(at: pageIndex) {
                self.updateSelection(on: pageView, annotation: annotation)
            }
        }, completion: nil)
    }

    func didBecomeActive() {
        self.updatePencilSettingsIfNeeded()
    }

    // MARK: - Actions

    func performBackAction() {
        pdfController?.backForwardList.requestBack(animated: true)
    }

    func focus(page: UInt) {
        self.scrollIfNeeded(to: page, animated: true, completion: {})
    }

    func highlightSearchResults(_ results: [SearchResult]) {
        searchResults = results
        guard let searchHighlightViewManager = pdfController?.searchHighlightViewManager else { return }
        searchHighlightViewManager.clearHighlightedSearchResults(animated: true)
        searchHighlightViewManager.addHighlight(results, animated: true)
    }

    func highlightSelectedSearchResult(_ result: SearchResult) {
        let searchHighlightViewManager = pdfController?.searchHighlightViewManager
        scrollIfNeeded(to: result.pageIndex, animated: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                searchHighlightViewManager?.animateSearchHighlight(result)
            }
        }
    }

    func disableAnnotationTools() {
        guard let tool = self.pdfController?.annotationStateManager.state else { return }
        self.toggle(annotationTool: tool, color: nil, tappedWithStylus: false)
    }

    func toggle(annotationTool: PSPDFKit.Annotation.Tool, color: UIColor?, tappedWithStylus: Bool, resetPencilManager: Bool = true) {
        guard let stateManager = self.pdfController?.annotationStateManager else { return }

        stateManager.stylusMode = .fromStylusManager

        let toolToAdd = stateManager.state == annotationTool ? nil : annotationTool
        if PDFDocumentViewController.toolHistory.last != toolToAdd {
            PDFDocumentViewController.toolHistory.append(toolToAdd)
            if PDFDocumentViewController.toolHistory.count > 2 {
                PDFDocumentViewController.toolHistory.remove(at: 0)
            }
        }
        if stateManager.state == annotationTool {
            stateManager.setState(nil, variant: nil)
            if resetPencilManager {
                PSPDFKit.SDK.shared.applePencilManager.detected = false
                PSPDFKit.SDK.shared.applePencilManager.enabled = false
            }
            return
        } else if tappedWithStylus {
            PSPDFKit.SDK.shared.applePencilManager.detected = true
            PSPDFKit.SDK.shared.applePencilManager.enabled = true
        }

        stateManager.setState(annotationTool, variant: nil)

        if let color = color {
            let (_color, _, blendMode) = AnnotationColorGenerator.color(from: color, isHighlight: (annotationTool == .highlight), userInterfaceStyle: self.viewModel.state.interfaceStyle)
            stateManager.drawColor = _color
            stateManager.blendMode = blendMode ?? .normal
        }

        switch annotationTool {
        case .ink:
            stateManager.lineWidth = self.viewModel.state.activeLineWidth
            if UIPencilInteraction.prefersPencilOnlyDrawing {
                stateManager.stylusMode = .stylus
            }

        case .eraser:
            stateManager.lineWidth = self.viewModel.state.activeEraserSize

        case .freeText:
            stateManager.fontSize = self.viewModel.state.activeFontSize

        default: break
        }
    }

    private func update(state: PDFReaderState) {
        if let controller = self.pdfController {
            self.update(state: state, pdfController: controller)
        } else if let controller = self.unlockController {
            self.update(state: state, unlockController: controller)
        }
    }

    private func update(state: PDFReaderState, unlockController: UnlockPDFViewController) {
        guard let success = state.unlockSuccessful, success, let controller = self.unlockController else { return }
        // Remove unlock controller
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        controller.didMove(toParent: nil)
        // Setup PDF controller to show unlocked PDF
        self.setupPdfController()
    }

    private func update(state: PDFReaderState, pdfController: PDFViewController) {
        if state.changes.contains(.interfaceStyle) {
            updateInterface(to: state.settings.appearanceMode, userInterfaceStyle: state.interfaceStyle)
        }

        if state.changes.contains(.settings) {
            if pdfController.configuration.scrollDirection != state.settings.direction ||
               pdfController.configuration.pageTransition != state.settings.transition ||
               pdfController.configuration.pageMode != state.settings.pageMode ||
               pdfController.configuration.spreadFitting != state.settings.pageFitting ||
                pdfController.configuration.isFirstPageAlwaysSingle != state.settings.isFirstPageAlwaysSingle {
                pdfController.updateConfiguration { configuration in
                    configuration.scrollDirection = state.settings.direction
                    configuration.pageTransition = state.settings.transition
                    configuration.pageMode = state.settings.pageMode
                    configuration.spreadFitting = state.settings.pageFitting
                    configuration.isFirstPageAlwaysSingle = state.settings.isFirstPageAlwaysSingle
                }
            }
        }

        if state.changes.contains(.selection) {
            if let annotation = state.selectedAnnotation {
                if let location = state.focusDocumentLocation {
                    // If annotation was selected, focus if needed
                    self.focus(annotation: annotation, at: location, document: state.document)
                } else if annotation.type != .ink || pdfController.annotationStateManager.state != .ink {
                    // Update selection if needed.
                    // Never select ink annotation if inking is active in case the user needs to continue typing.
                    self.select(annotation: annotation, pageIndex: pdfController.pageIndex, document: state.document)
                }
            } else {
                // Otherwise remove selection if needed
                self.select(annotation: nil, pageIndex: pdfController.pageIndex, document: state.document)
            }

            self.showPopupAnnotationIfNeeded(state: state)
        }

        if state.changes.contains(.visiblePageFromThumbnailList) {
            pdfController.setPageIndex(PageIndex(state.visiblePage), animated: false)
        }

        if let tool = state.changedColorForTool, let color = state.toolColors[tool] {
            self.set(color: color, for: tool, in: pdfController.annotationStateManager)
        }

        if state.changes.contains(.activeLineWidth) {
            pdfController.annotationStateManager.lineWidth = state.activeLineWidth
        }

        if state.changes.contains(.activeEraserSize) {
            pdfController.annotationStateManager.lineWidth = state.activeEraserSize
        }

        if state.changes.contains(.activeFontSize) {
            pdfController.annotationStateManager.fontSize = state.activeFontSize
        }

        if let notification = state.pdfNotification {
            self.updatePdf(notification: notification)
        }

        if state.changes.contains(.initialDataLoaded) {
            pdfController.setPageIndex(PageIndex(state.visiblePage), animated: false)
            self.select(annotation: state.selectedAnnotation, pageIndex: pdfController.pageIndex, document: state.document)
        }
    }

    private func tool(from annotation: PSPDFKit.Annotation) -> PSPDFKit.Annotation.Tool? {
        switch annotation.type {
        case .highlight:
            return .highlight

        case .note:
            return .note

        case .square:
            return .square

        case .ink:
            return .ink

        default:
            return nil
        }
    }

    private func updatePdf(notification: Notification) {
        guard let pdfController = self.pdfController else { return }

        switch notification.name {
        case .PSPDFAnnotationChanged:
            guard let changes = notification.userInfo?[PSPDFAnnotationChangedNotificationKeyPathKey] as? [String] else { return }
            // Changing annotation color changes the `lastUsed` color in `annotationStateManager` (#487), so we have to re-set it.
            if changes.contains("color"), let annotation = notification.object as? PSPDFKit.Annotation, let tool = self.tool(from: annotation), let color = self.viewModel.state.toolColors[tool] {
                self.set(color: color, for: tool, in: pdfController.annotationStateManager)
            }

        case .PSPDFAnnotationsAdded:
            guard let annotations = notification.object as? [PSPDFKit.Annotation] else { return }
            // If Image annotation is active after adding the annotation, deactivate it
            if annotations.first is PSPDFKit.SquareAnnotation && pdfController.annotationStateManager.state == .square, let color = self.viewModel.state.toolColors[.square] {
                // Don't reset apple pencil detection here, this is automatic action, not performed by user.
                self.toggle(annotationTool: .square, color: color, tappedWithStylus: false, resetPencilManager: false)
            }

        default: break
        }
    }

    private func updateInterface(to appearanceMode: ReaderSettingsState.Appearance, userInterfaceStyle: UIUserInterfaceStyle) {
        switch appearanceMode {
        case .automatic:
            self.pdfController?.appearanceModeManager.appearanceMode = userInterfaceStyle == .dark ? .night : []
            self.pdfController?.overrideUserInterfaceStyle = .unspecified
            self.unlockController?.overrideUserInterfaceStyle = .unspecified

        case .light:
            self.pdfController?.appearanceModeManager.appearanceMode = []
            self.pdfController?.overrideUserInterfaceStyle = .light
            self.unlockController?.overrideUserInterfaceStyle = .light

        case .dark:
            self.pdfController?.appearanceModeManager.appearanceMode = .night
            self.pdfController?.overrideUserInterfaceStyle = .dark
            self.unlockController?.overrideUserInterfaceStyle = .dark
        }
    }

    private func showPopupAnnotationIfNeeded(state: PDFReaderState) {
        guard !(parentDelegate?.isSidebarVisible ?? false),
              let annotation = state.selectedAnnotation,
              annotation.type != .freeText,
              let pageView = pdfController?.pageViewForPage(at: UInt(annotation.page)) else { return }

        let key = annotation.readerKey
        var frame = view.convert(annotation.boundingBox(boundingBoxConverter: self), from: pageView.pdfCoordinateSpace)
        frame.origin.y += parentDelegate?.documentTopOffset ?? 0
        let observable = coordinatorDelegate?.showAnnotationPopover(
            viewModel: viewModel,
            sourceRect: frame,
            popoverDelegate: self,
            userInterfaceStyle: viewModel.state.settings.appearanceMode.userInterfaceStyle
        )

        guard let observable else { return }
        observable.subscribe(onNext: { [weak viewModel] state in
            guard let viewModel else { return }
            if state.changes.contains(.color) {
                viewModel.process(action: .setColor(key: key.key, color: state.color))
            }
            if state.changes.contains(.comment) {
                viewModel.process(action: .setComment(key: key.key, comment: state.comment))
            }
            if state.changes.contains(.deletion) {
                viewModel.process(action: .removeAnnotation(key))
            }
            if state.changes.contains(.lineWidth) {
                viewModel.process(action: .setLineWidth(key: key.key, width: state.lineWidth))
            }
            if state.changes.contains(.tags) {
                viewModel.process(action: .setTags(key: key.key, tags: state.tags))
            }
            if state.changes.contains(.pageLabel) || state.changes.contains(.highlight) {
                // TODO: - fix font size
                viewModel.process(action: .updateAnnotationProperties(
                    key: key.key,
                    color: state.color,
                    lineWidth: state.lineWidth,
                    fontSize: 0,
                    pageLabel: state.pageLabel,
                    updateSubsequentLabels: state.updateSubsequentLabels,
                    highlightText: state.highlightText,
                    higlightFont: state.highlightFont
                ))
            }
        })
        .disposed(by: disposeBag)
    }

    private func updatePencilSettingsIfNeeded() {
        guard self.pdfController?.annotationStateManager.state == .ink else { return }
        self.pdfController?.annotationStateManager.stylusMode = UIPencilInteraction.prefersPencilOnlyDrawing ? .stylus : .fromStylusManager
    }

    /// Scrolls to given page if needed.
    /// - parameter pageIndex: Page index to which the `pdfController` is supposed to scroll.
    /// - parameter animated: `true` if scrolling is animated, `false` otherwise.
    /// - parameter completion: Completion block called after scroll. Block is also called when scroll was not needed.
    private func scrollIfNeeded(to pageIndex: PageIndex, animated: Bool, completion: @escaping () -> Void) {
        guard self.pdfController?.pageIndex != pageIndex else {
            completion()
            return
        }

        if !animated {
            self.pdfController?.setPageIndex(pageIndex, animated: false)
            completion()
            return
        }

        UIView.animate(withDuration: 0.25, animations: {
            self.pdfController?.setPageIndex(pageIndex, animated: false)
        }, completion: { finished in
            guard finished else { return }
            completion()
        })
    }

    private func set(color: UIColor, for tool: PSPDFKit.Annotation.Tool, in stateManager: AnnotationStateManager) {
        let toolColor = tool == .highlight ? AnnotationColorGenerator.color(from: color, isHighlight: true, userInterfaceStyle: self.viewModel.state.interfaceStyle).color : color
        stateManager.setLastUsedColor(toolColor, annotationString: tool)
        if stateManager.state == tool {
            stateManager.drawColor = toolColor
        }
    }

    func setInterface(hidden: Bool) {
        self.pdfController?.userInterfaceView.alpha = hidden ? 0 : 1
    }

    // MARK: - Selection

    /// (De)Selects given annotation in document.
    /// - parameter annotation: Annotation to select. Existing selection will be deselected if set to `nil`.
    /// - parameter pageIndex: Page index of page where (de)selection should happen.
    /// - parameter document: Active `Document` instance.
    private func select(annotation: PDFAnnotation?, pageIndex: PageIndex, document: PSPDFKit.Document) {
        guard let pageView = self.pdfController?.pageViewForPage(at: pageIndex) else { return }

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
    private func focus(annotation: PDFAnnotation, at location: AnnotationDocumentLocation, document: PSPDFKit.Document) {
        let pageIndex = PageIndex(location.page)
        self.scrollIfNeeded(to: pageIndex, animated: true) {
            self.select(annotation: annotation, pageIndex: pageIndex, document: document)
        }
    }

    /// Updates `SelectionView` for `PDFPageView` based on selected annotation.
    /// - parameter pageView: `PDFPageView` instance for given page.
    /// - parameter selectedAnnotation: Selected annotation or `nil` if there is no selection.
    private func updateSelection(on pageView: PDFPageView, annotation: PDFAnnotation?) {
        // Delete existing custom highlight selection view
        if let view = self.selectionView {
            view.removeFromSuperview()
        }

        guard let selection = annotation, (selection.type == .highlight || selection.type == .underline) && selection.page == Int(pageView.pageIndex) else { return }
        // Add custom highlight selection view if needed
        let frame = pageView.convert(selection.boundingBox(boundingBoxConverter: self), from: pageView.pdfCoordinateSpace).insetBy(dx: -SelectionView.inset, dy: -SelectionView.inset)
        let selectionView = SelectionView()
        selectionView.frame = frame
        pageView.annotationContainerView.addSubview(selectionView)
        self.selectionView = selectionView
    }

    // MARK: - Setups

    private func setupViews() {
        if self.viewModel.state.document.isLocked {
            self.setupLockedView()
        } else {
            self.setupPdfController()
        }
    }

    private func setupLockedView() {
        let unlockController = UnlockPDFViewController(viewModel: self.viewModel)
        unlockController.view.translatesAutoresizingMaskIntoConstraints = false

        unlockController.willMove(toParent: self)
        self.addChild(unlockController)
        self.view.addSubview(unlockController.view)
        unlockController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            unlockController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            unlockController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            unlockController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            unlockController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
        ])

        self.unlockController = unlockController
    }

    private func setupPdfController() {
        let pdfController = self.createPdfController(with: self.viewModel.state.document, settings: self.viewModel.state.settings)
        pdfController.view.translatesAutoresizingMaskIntoConstraints = false

        pdfController.willMove(toParent: self)
        self.addChild(pdfController)
        self.view.addSubview(pdfController.view)
        pdfController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            pdfController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            pdfController.view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            pdfController.view.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            pdfController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
        ])

        self.pdfController = pdfController
    }

    private func createPdfController(with document: PSPDFKit.Document, settings: PDFSettings) -> PDFViewController {
        let pdfConfiguration = PDFConfiguration { builder in
            builder.scrollDirection = settings.direction
            builder.pageTransition = settings.transition
            builder.pageMode = settings.pageMode
            builder.spreadFitting = settings.pageFitting
            builder.isFirstPageAlwaysSingle = settings.isFirstPageAlwaysSingle
            builder.documentLabelEnabled = .NO
            builder.allowedAppearanceModes = [.night]
            builder.isCreateAnnotationMenuEnabled = self.viewModel.state.library.metadataEditable
            builder.createAnnotationMenuGroups = self.createAnnotationCreationMenuGroups()
            builder.isTextSelectionEnabled = true
            builder.isImageSelectionEnabled = true
            builder.showBackActionButton = false
            builder.showForwardActionButton = false
            builder.contentMenuConfiguration = ContentMenuConfiguration {
                $0.annotationToolChoices = { _, _, _, _ in
                    return [.highlight]
                }
            }
            builder.freeTextAccessoryViewEnabled = false
            builder.scrubberBarType = .horizontal
//            builder.thumbnailBarMode = .scrubberBar
            builder.markupAnnotationMergeBehavior = .never
            builder.freeTextAccessoryViewEnabled = false
            builder.overrideClass(PSPDFKit.HighlightAnnotation.self, with: HighlightAnnotation.self)
            builder.overrideClass(PSPDFKit.NoteAnnotation.self, with: NoteAnnotation.self)
            builder.overrideClass(PSPDFKit.SquareAnnotation.self, with: SquareAnnotation.self)
            builder.overrideClass(PSPDFKit.UnderlineAnnotation.self, with: UnderlineAnnotation.self)
            builder.overrideClass(FreeTextAnnotationView.self, with: CustomFreeTextAnnotationView.self)
            builder.overrideClass(PSPDFKit.AnnotationManager.self, with: AnnotationManager.self)
        }

        let controller = PDFViewController(document: document, configuration: pdfConfiguration)
        controller.view.backgroundColor = .systemGray6
        controller.delegate = self
        controller.backForwardList.delegate = self
        controller.formSubmissionDelegate = nil
        controller.annotationStateManager.add(self)
        controller.annotationStateManager.pencilInteraction.delegate = self
        controller.annotationStateManager.pencilInteraction.isEnabled = true
        pageIndexCancellable = controller.pageIndexPublisher.sink { [weak self] event in
            guard let self else { return }
            self.viewModel.process(action: .setVisiblePage(page: Int(event.pageIndex), userActionFromDocument: event.reason == .userInterface, fromThumbnailList: false))
        }
        self.setup(scrubberBar: controller.userInterfaceView.scrubberBar)
        self.setup(interactions: controller.interactions)
        controller.shouldResetAppearanceModeWhenViewDisappears = false

        return controller
    }

    private func createAnnotationCreationMenuGroups() -> [AnnotationToolConfiguration.ToolGroup] {
        return [AnnotationToolConfiguration.ToolGroup(items: [
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
        // Only supported annotations can be selected
        interactions.selectAnnotation.addActivationCondition { context, _, _ -> Bool in
            return AnnotationsConfig.supported.contains(context.annotation.type)
        }

        interactions.selectAnnotation.addActivationCallback { [weak self] context, _, _ in
            let key = context.annotation.key ?? context.annotation.uuid
            let type: PDFReaderState.AnnotationKey.Kind = context.annotation.isZoteroAnnotation ? .database : .document
            self?.viewModel.process(action: .selectAnnotationFromDocument(PDFReaderState.AnnotationKey(key: key, type: type)))
        }

        interactions.toggleUserInterface.addActivationCallback { [weak self] _, _, _ in
            guard let interfaceView = self?.pdfController?.userInterfaceView else { return }
            self?.parentDelegate?.interfaceVisibilityDidChange(to: interfaceView.alpha != 0)
        }

        interactions.deselectAnnotation.addActivationCondition { [weak self] _, _, _ -> Bool in
            // `interactions.deselectAnnotation.addActivationCallback` is not always called when highglight annotation tool is enabled.
            self?.viewModel.process(action: .deselectSelectedAnnotation)
            return true
        }

        // Only Zotero-synced annotations can be edited
        interactions.editAnnotation.addActivationCondition { context, _, _ -> Bool in
            return context.annotation.key != nil && context.annotation.isEditable
        }
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

extension PDFDocumentViewController: PDFViewControllerDelegate {
    func pdfViewController(_ pdfController: PDFViewController, willBeginDisplaying pageView: PDFPageView, forPageAt pageIndex: Int) {
        if !searchResults.isEmpty {
            pdfController.searchHighlightViewManager.addHighlight(searchResults, animated: false)
        }
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldShow controller: UIViewController, options: [String: Any]? = nil, animated: Bool) -> Bool {
        return false
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldSave document: PSPDFKit.Document, withOptions options: AutoreleasingUnsafeMutablePointer<NSDictionary>) -> Bool {
        return false
    }

    func pdfViewController(_ pdfController: PDFViewController, shouldSelect annotations: [PSPDFKit.Annotation], on pageView: PDFPageView) -> [PSPDFKit.Annotation] {
        guard let annotation = annotations.first, annotation.type == .freeText else { return annotations }
        self.selectedAnnotationWasSelectedBefore = pageView.selectedAnnotations.contains(annotation)
        return annotations
    }

    func pdfViewController(
        _ sender: PDFViewController,
        menuForAnnotations annotations: [PSPDFKit.Annotation],
        onPageView pageView: PDFPageView,
        appearance: EditMenuAppearance,
        suggestedMenu: UIMenu
    ) -> UIMenu {
        guard let annotation = annotations.first,
              annotation.type == .freeText,
              let annotationView = pageView.visibleAnnotationViews.first(where: { $0.annotation == annotation }) as? CustomFreeTextAnnotationView
        else { return UIMenu(children: []) }

        annotationView.delegate = self
        annotationView.annotationKey = annotation.key.flatMap({ .init(key: $0, type: .database) })

        if annotation.key != nil && self.selectedAnnotationWasSelectedBefore {
            // Focus only if Zotero annotation is selected, if annotation popup is dismissed and this annotation has been already selected
            annotationView.beginEditing()
        }

        self.selectedAnnotationWasSelectedBefore = false

        return UIMenu(children: [])
    }

    func pdfViewController(_ sender: PDFViewController, menuForCreatingAnnotationAt point: CGPoint, onPageView pageView: PDFPageView, appearance: EditMenuAppearance, suggestedMenu: UIMenu) -> UIMenu {
        let origin = pageView.convert(point, to: pageView.pdfCoordinateSpace)
        let children: [UIMenuElement] = [
            UIAction(title: L10n.Pdf.AnnotationToolbar.note, handler: { [weak self] _ in
                self?.viewModel.process(action: .createNote(pageIndex: pageView.pageIndex, origin: origin))
            }),
            UIAction(title: L10n.Pdf.AnnotationToolbar.image, handler: { [weak self] _ in
                self?.viewModel.process(action: .createImage(pageIndex: pageView.pageIndex, origin: origin))
            })
        ]
        return UIMenu(children: children)
    }

    func pdfViewController(_ sender: PDFViewController, menuForText glyphs: GlyphSequence, onPageView pageView: PDFPageView, appearance: EditMenuAppearance, suggestedMenu: UIMenu) -> UIMenu {
        return filterActions(
            forMenu: suggestedMenu,
            predicate: { menuId, action -> UIMenuElement? in
                switch menuId {
                case .standardEdit:
                    switch action.identifier {
                    case .PSPDFKit.copy:
                        return action.replacing(title: L10n.copy, handler: { _ in
                            UIPasteboard.general.string = TextConverter.convertTextForCopying(from: glyphs.text)
                        })

                    default:
                        return action
                    }

                case .PSPDFKit.accessibility:
                    return action

                case .share:
                    guard action.identifier == .PSPDFKit.share else { return nil }
                    return action.replacing(handler: { [weak self] _ in
                        self?.coordinatorDelegate?.share(text: glyphs.text, rect: pageView.convert(glyphs.boundingBox, from: pageView.pdfCoordinateSpace), view: pageView)
                    })

                case .pspdfkitActions:
                    switch action.identifier {
                    case .PSPDFKit.define:
                        return action.replacing(title: L10n.lookUp, handler: { [weak self] _ in
                            guard let self else { return }
                            coordinatorDelegate?.lookup(
                                text: glyphs.text,
                                rect: pageView.convert(glyphs.boundingBox, from: pageView.pdfCoordinateSpace),
                                view: pageView,
                                userInterfaceStyle: viewModel.state.settings.appearanceMode.userInterfaceStyle
                            )
                        })

                    case .PSPDFKit.searchDocument:
                        return action.replacing(handler: { [weak self] _ in
                            guard let self, let pdfController else { return }
                            parentDelegate?.showSearch(pdfController: pdfController, text: glyphs.text)
                        })

                    default:
                        return action
                    }

                case .PSPDFKit.annotate:
                    let actions = [
                        action.replacing(title: L10n.Pdf.highlight, handler: createHighlightActionHandler(for: pageView, in: viewModel)),
                        UIAction(title: L10n.Pdf.underline, identifier: .underline, handler: createUnderlineActionHandler(for: pageView, in: viewModel))
                    ]
                    return UIMenu(options: [.displayInline], children: actions)

                default:
                    return action
                }
            },
            populatingEmptyMenu: { menu -> [UIAction]? in
                switch menu.identifier {
                case .PSPDFKit.annotate:
                    return [
                        UIAction(title: L10n.Pdf.highlight, handler: createHighlightActionHandler(for: pageView, in: viewModel)),
                        UIAction(title: L10n.Pdf.underline, identifier: .underline, handler: createUnderlineActionHandler(for: pageView, in: viewModel))
                    ]

                default:
                    return nil
                }
            }
        )

        func filterActions(forMenu menu: UIMenu, predicate: (UIMenu.Identifier, UIAction) -> UIMenuElement?, populatingEmptyMenu: (UIMenu) -> [UIAction]?) -> UIMenu {
            return menu.replacingChildren(menu.children.compactMap { element -> UIMenuElement? in
                if let action = element as? UIAction {
                    if let element = predicate(menu.identifier, action) {
                        return element
                    } else {
                        return nil
                    }
                } else if let menu = element as? UIMenu {
                    if menu.children.isEmpty {
                        return populatingEmptyMenu(menu).flatMap({ menu.replacingChildren($0) }) ?? menu
                    } else {
                        // Filter children of submenus recursively.
                        return filterActions(forMenu: menu, predicate: predicate, populatingEmptyMenu: populatingEmptyMenu)
                    }
                } else {
                    return element
                }
            })
        }

        func createHighlightActionHandler(for pageView: PDFPageView, in viewModel: ViewModel<PDFReaderActionHandler>) -> UIActionHandler {
            let rects = pageView.selectionView.selectionRects.map({ pageView.convert($0.cgRectValue, to: pageView.pdfCoordinateSpace) })
            return { [weak viewModel] _ in
                guard let viewModel else { return }
                viewModel.process(action: .createHighlight(pageIndex: pageView.pageIndex, rects: rects))
                pageView.selectionView.selectedGlyphs = nil
            }
        }

        func createUnderlineActionHandler(for pageView: PDFPageView, in viewModel: ViewModel<PDFReaderActionHandler>) -> UIActionHandler {
            let rects = pageView.selectionView.selectionRects.map({ pageView.convert($0.cgRectValue, to: pageView.pdfCoordinateSpace) })
            return { [weak viewModel] _ in
                guard let viewModel else { return }
                viewModel.process(action: .createUnderline(pageIndex: pageView.pageIndex, rects: rects))
                pageView.selectionView.selectedGlyphs = nil
            }
        }
    }

    func pdfViewController(_ pdfController: PDFViewController, didSelectText text: String, with glyphs: [Glyph], at rect: CGRect, on pageView: PDFPageView) {
        parentDelegate?.didSelectText(text)
    }

    func pdfViewController(_ pdfController: PDFViewController, didFinishRenderTaskFor pageView: PDFPageView, error: (any Error)?) {
        if let error {
            DDLogError("PDFDocumentViewController: PDFViewController didFinishRenderTaskFor \(pageView) with error - \(error)")
        }
    }
}

extension PDFDocumentViewController: BackForwardActionListDelegate {
    func backForwardList(_ list: BackForwardActionList, requestedBackActionExecution actions: [Action], animated: Bool) {
        pdfController?.backForwardList(list, requestedBackActionExecution: actions, animated: animated)
    }

    func backForwardList(_ list: BackForwardActionList, requestedForwardActionExecution actions: [Action], animated: Bool) {
        pdfController?.backForwardList(list, requestedForwardActionExecution: actions, animated: animated)
    }

    func backForwardListDidUpdate(_ list: BackForwardActionList) {
        pdfController?.backForwardListDidUpdate(list)
        parentDelegate?.backNavigationButtonChanged(visible: list.backAction != nil)
    }
}

extension PDFDocumentViewController: AnnotationStateManagerDelegate {
    func annotationStateManager(
        _ manager: AnnotationStateManager,
        didChangeState oldState: PSPDFKit.Annotation.Tool?,
        to newState: PSPDFKit.Annotation.Tool?,
        variant oldVariant: PSPDFKit.Annotation.Variant?,
        to newVariant: PSPDFKit.Annotation.Variant?
    ) {
        self.parentDelegate?.annotationTool(didChangeStateFrom: oldState, to: newState, variantFrom: oldVariant, to: newVariant)
    }

    func annotationStateManager(_ manager: AnnotationStateManager, didChangeUndoState undoEnabled: Bool, redoState redoEnabled: Bool) {
        self.parentDelegate?.didChange(undoState: undoEnabled, redoState: redoEnabled)
    }
}

extension PDFDocumentViewController: UIPencilInteractionDelegate {
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        guard self.parentDelegate?.isToolbarVisible == true else { return }
    
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser:
            if let tool = self.pdfController?.annotationStateManager.state {
                if tool != .eraser {
                    self.toggle(annotationTool: .eraser, color: nil, tappedWithStylus: true)
                } else {
                    let previous = (PDFDocumentViewController.toolHistory.last(where: { $0 != .eraser }) ?? nil) ?? .ink
                    let color = self.viewModel.state.toolColors[previous]
                    self.toggle(annotationTool: previous, color: color, tappedWithStylus: true)
                }
            }

        case .switchPrevious:
            let previous: Annotation.Tool
            if let tool = pdfController?.annotationStateManager.state {
                // Find the most recent different tool – if it's the "nil tool", default to `tool` to unset current tool
                previous = (PDFDocumentViewController.toolHistory.last(where: { $0 != tool }) ?? nil) ?? tool
            } else {
                // Since we can't switch from nil to nil, find the most recent non-nil tool, default to .ink
                previous = (PDFDocumentViewController.toolHistory.last(where: { $0 != nil }) ?? nil) ?? .ink
            }
            let color = viewModel.state.toolColors[previous]
            toggle(annotationTool: previous, color: color, tappedWithStylus: true)

        case .showColorPalette, .showInkAttributes:
            self.parentDelegate?.showToolOptions()

        case .ignore: break

        @unknown default: break
        }
    }
}

extension PDFDocumentViewController: UIPopoverPresentationControllerDelegate {
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        if self.viewModel.state.selectedAnnotation?.type == .highlight {
            self.viewModel.process(action: .deselectSelectedAnnotation)
        }
    }
}

extension PDFDocumentViewController: AnnotationBoundingBoxConverter {
    /// Converts from database to PSPDFKit rect. Database stores rects in RAW PDF Coordinate space. PSPDFKit works with Normalized PDF Coordinate Space.
    func convertFromDb(rect: CGRect, page: PageIndex) -> CGRect? {
        guard let pageInfo = self.viewModel.state.document.pageInfoForPage(at: page) else { return nil }
        return rect.applying(pageInfo.transform)
    }

    func convertFromDb(point: CGPoint, page: PageIndex) -> CGPoint? {
        let tmpRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        return self.convertFromDb(rect: tmpRect, page: page)?.origin
    }

    /// Converts from PSPDFKit to database rect. Database stores rects in RAW PDF Coordinate space. PSPDFKit works with Normalized PDF Coordinate Space.
    func convertToDb(rect: CGRect, page: PageIndex) -> CGRect? {
        guard let pageInfo = self.viewModel.state.document.pageInfoForPage(at: page) else { return nil }
        return rect.applying(pageInfo.transform.inverted())
    }

    func convertToDb(point: CGPoint, page: PageIndex) -> CGPoint? {
        let tmpRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        return self.convertToDb(rect: tmpRect, page: page)?.origin
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

extension PDFDocumentViewController: FreeTextInputDelegate {
    func showColorPicker(sender: UIView, key: PDFReaderState.AnnotationKey, updated: @escaping (String) -> Void) {
        let color = self.viewModel.state.annotation(for: key)?.color
        self.coordinatorDelegate?.showToolSettings(
            tool: .freeText,
            colorHex: color,
            sizeValue: nil,
            sender: .view(sender, nil),
            userInterfaceStyle: self.overrideUserInterfaceStyle,
            valueChanged: { newColor, _ in
                guard let newColor else { return }
                self.viewModel.process(action: .setColor(key: key.key, color: newColor))
                updated(newColor)
            }
        )
    }
    
    func showFontSizePicker(sender: UIView, key: PDFReaderState.AnnotationKey, updated: @escaping (CGFloat) -> Void) {
        self.coordinatorDelegate?.showFontSizePicker(sender: sender, picked: { [weak self] size in
            self?.viewModel.process(action: .setFontSize(key: key.key, size: size))
            updated(size)
        })
    }

    func showTagPicker(sender: UIView, key: PDFReaderState.AnnotationKey, updated: @escaping ([Tag]) -> Void) {
        let tags = Set((self.getTags(for: key) ?? []).compactMap({ $0.name }))
        self.coordinatorDelegate?.showTagPicker(libraryId: self.viewModel.state.library.identifier, selected: tags, userInterfaceStyle: self.viewModel.state.interfaceStyle, picked: { tags in
            self.viewModel.process(action: .setTags(key: key.key, tags: tags))
            updated(tags)
        })
    }

    func deleteAnnotation(sender: UIView, key: PDFReaderState.AnnotationKey) {
        self.coordinatorDelegate?.showDeleteAlertForAnnotation(sender: sender, delete: {
            self.viewModel.process(action: .removeAnnotation(key))
        })
    }

    func change(fontSize: CGFloat, for key: PDFReaderState.AnnotationKey) {
        self.viewModel.process(action: .setFontSize(key: key.key, size: fontSize))
    }
    
    func getFontSize(for key: PDFReaderState.AnnotationKey) -> CGFloat? {
        return self.viewModel.state.annotation(for: key)?.fontSize
    }

    func getColor(for key: PDFReaderState.AnnotationKey) -> UIColor? {
        return (self.viewModel.state.annotation(for: key)?.color).flatMap({ UIColor(hex: $0) })
    }

    func getTags(for key: PDFReaderState.AnnotationKey) -> [Tag]? {
        return self.viewModel.state.annotation(for: key)?.tags
    }
}

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

extension UIMenu.Identifier {
    fileprivate static let pspdfkitActions = UIMenu.Identifier(rawValue: "com.pspdfkit.menu.actions")
}

extension UIAction {
    fileprivate func replacing(title: String? = nil, handler: @escaping UIActionHandler) -> UIAction {
        UIAction(
            title: title ?? self.title,
            subtitle: self.subtitle,
            image: title != nil ? nil : self.image,
            identifier: self.identifier,
            discoverabilityTitle: self.discoverabilityTitle,
            attributes: self.attributes,
            state: self.state,
            handler: handler
        )
    }
}

extension UIAction.Identifier {
    fileprivate static let underline = UIAction.Identifier(rawValue: "org.zotero.menu")
}
