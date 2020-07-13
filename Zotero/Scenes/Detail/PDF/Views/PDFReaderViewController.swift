//
//  PDFReaderViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit
import PSPDFKitUI
import RxSwift

class PDFReaderViewController: UIViewController {
    private enum NavigationBarButton: Int {
        case redo = 1
        case undo = 2
    }

    private static let colorPreviewSize = CGSize(width: 15, height: 15)
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private unowned let annotationPreviewController: AnnotationPreviewController
    private unowned let pageController: PdfPageController
    private let disposeBag: DisposeBag

    private weak var annotationsController: AnnotationsViewController!
    private weak var pdfController: PDFViewController!
    private weak var annotationsControllerLeft: NSLayoutConstraint!
    private weak var pdfControllerLeft: NSLayoutConstraint!
    // Annotation toolbar
    private weak var createNoteButton: CheckboxButton!
    private weak var createHighlightButton: CheckboxButton!
    private weak var createAreaButton: CheckboxButton!
    private weak var colorPickerbutton: UIButton!

    weak var coordinatorDelegate: DetailPdfCoordinatorDelegate?

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

    init(viewModel: ViewModel<PDFReaderActionHandler>, annotationPreviewController: AnnotationPreviewController,
         pageController: PdfPageController) {
        self.viewModel = viewModel
        self.annotationPreviewController = annotationPreviewController
        self.pageController = pageController
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .secondarySystemBackground
        self.setupAnnotationsSidebar()
        self.setupPdfController(with: self.viewModel.state.document)
        self.setupSidebarBorder()
        self.setupNavigationBar()
        self.navigationItem.titleView = UIStackView(arrangedSubviews: self.createAnnotationToolbarButtons())
        self.setupObserving()

        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .loadAnnotations)
    }

    deinit {
        self.pdfController?.annotationStateManager.remove(self)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        self.viewModel.process(action: .userInterfaceStyleChanged)
    }

    // MARK: - Actions

    private func update(state: PDFReaderState) {
        if state.changes.contains(.darkMode) {
            self.pdfController.appearanceModeManager.appearanceMode = self.traitCollection.userInterfaceStyle == .dark ? .night : .init(rawValue: 0)
        }

        if state.changes.contains(.selection),
           let pageView = self.pdfController.pageViewForPage(at: self.pdfController.pageIndex) {
            self.updateSelection(on: pageView, selectedAnnotation: state.selectedAnnotation, pageIndex: Int(self.pdfController.pageIndex))
        }

        if state.focusSidebarIndexPath != nil {
            self.openSidebarIfClosed()
        }

        if let location = state.focusDocumentLocation,
           let key = state.selectedAnnotation?.key {
            self.focusAnnotation(at: location, key: key, document: state.document)
        }
    }

    private func updateSelection(on pageView: PDFPageView, selectedAnnotation: Annotation?, pageIndex: Int) {
        if let view = pageView.annotationContainerView.subviews.first(where: { $0 is SelectionView }) {
            view.removeFromSuperview()
        }

        if let selection = selectedAnnotation,
           selection.type == .highlight && selection.page == pageIndex {
            let frame = pageView.convert(selection.boundingBox, from: pageView.pdfCoordinateSpace).insetBy(dx: -4, dy: -4)
            let selectionView = SelectionView()
            selectionView.frame = frame
            pageView.annotationContainerView.addSubview(selectionView)
        }
    }

    private func toggle(annotationTool: PSPDFKit.Annotation.Tool) {
        if self.pdfController.annotationStateManager.state == annotationTool {
            self.pdfController.annotationStateManager.setState(nil, variant: nil)
        } else {
            self.pdfController.annotationStateManager.setState(annotationTool, variant: nil)
        }
    }

    private func showColorPicker() {

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

    private func openSidebarIfClosed() {
        guard self.annotationsControllerLeft.constant != 0 else { return }
        self.toggleSidebar()
    }

    @objc private func toggleSidebar() {
        let shouldShow = self.pdfControllerLeft.constant == 0
        self.pdfControllerLeft.constant = shouldShow ? AnnotationsConfig.sidebarWidth : 0
        self.annotationsControllerLeft.constant = shouldShow ? 0 : -AnnotationsConfig.sidebarWidth

        if shouldShow {
            self.annotationsController.view.isHidden = false
        }

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
                       })
    }

    private func showSearch(sender: UIBarButtonItem) {
        let viewController = PDFSearchViewController(controller: self.pdfController, searchSelected: { [weak self] result in
            self?.highlight(result: result)
        })
        viewController.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .popover : .formSheet
        viewController.popoverPresentationController?.barButtonItem = sender
        self.present(viewController, animated: true, completion: nil)
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

    @objc private func close() {
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    private func set(toolColor: UIColor, in stateManager: AnnotationStateManager) {
        stateManager.setLastUsedColor(toolColor, annotationString: .highlight)
        stateManager.setLastUsedColor(toolColor, annotationString: .note)
        stateManager.setLastUsedColor(toolColor, annotationString: .square)
    }

    // MARK: - Setups

    private func setupAnnotationsSidebar() {
        let controller = AnnotationsViewController(viewModel: self.viewModel)
        controller.view.backgroundColor = self.view.backgroundColor
        controller.view.isHidden = true
        controller.coordinatorDelegate = self.coordinatorDelegate
        controller.previewLoader = self

        self.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.frame = self.view.bounds
        self.view.addSubview(controller.view)

        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            controller.view.widthAnchor.constraint(equalToConstant: AnnotationsConfig.sidebarWidth)
        ])
        let leftConstraint = controller.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor,
                                                                      constant: -AnnotationsConfig.sidebarWidth)
        leftConstraint.isActive = true

        controller.didMove(toParent: self)

        self.annotationsController = controller
        self.annotationsControllerLeft = leftConstraint
    }

    private func createAnnotationToolbarButtons() -> [UIButton] {
        let highlight = CheckboxButton(type: .custom)
        highlight.setImage(UIImage(systemName: "pencil.tip"), for: .normal)
        highlight.rx
                 .controlEvent(.touchDown)
                 .subscribe(onNext: { [weak self] _ in
                    self?.toggle(annotationTool: .highlight)
                 })
                 .disposed(by: self.disposeBag)
        self.createHighlightButton = highlight

        let note = CheckboxButton(type: .custom)
        note.setImage(UIImage(systemName: "doc"), for: .normal)
        note.rx
            .controlEvent(.touchDown)
            .subscribe(onNext: { [weak self] _ in
                self?.toggle(annotationTool: .note)
            })
            .disposed(by: self.disposeBag)
        self.createNoteButton = note

        let area = CheckboxButton(type: .custom)
        area.setImage(UIImage(systemName: "plus.square"), for: .normal)
        area.rx
            .controlEvent(.touchDown)
            .subscribe(onNext: { [weak self] _ in
                self?.toggle(annotationTool: .square)
            })
            .disposed(by: self.disposeBag)
        self.createAreaButton = area

        [highlight, note, area].forEach { button in
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
            button.widthAnchor.constraint(equalTo: button.heightAnchor, multiplier: 1, constant: 0).isActive = true
            button.adjustsImageWhenHighlighted = false
            button.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
            button.selectedTintColor = .white
            button.layer.cornerRadius = 6
            button.layer.masksToBounds = true
        }

        let picker = UIButton()
        let color = self.viewModel.state.activeColor
        picker.setImage(color.createImage(size: PDFReaderViewController.colorPreviewSize), for: .normal)
        picker.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        picker.rx.controlEvent(.touchUpInside)
                 .subscribe(onNext: { [weak self] _ in
                    self?.showColorPicker()
                 })
                 .disposed(by: self.disposeBag)
        self.colorPickerbutton = picker

        return [highlight, note, area, picker]
    }

    private func setupPdfController(with document: Document) {
        let pdfConfiguration = PDFConfiguration { builder in
            builder.scrollDirection = .horizontal
            builder.documentLabelEnabled = .NO
            builder.allowedAppearanceModes = [.night]
        }

        let controller = PDFViewController(document: document, configuration: pdfConfiguration)
        controller.delegate = self
        controller.formSubmissionDelegate = nil
        if self.traitCollection.userInterfaceStyle == .dark {
            controller.appearanceModeManager.appearanceMode = .night
        }
        controller.annotationStateManager.add(self)
        controller.setPageIndex(PageIndex(self.pageController.page(for: self.viewModel.state.key)), animated: false)
        self.set(toolColor: self.viewModel.state.activeColor, in: controller.annotationStateManager)

        self.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.frame = self.view.bounds
        self.view.addSubview(controller.view)

        NSLayoutConstraint.activate([
            controller.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        let leftConstraint = controller.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor)
        leftConstraint.isActive = true

        controller.didMove(toParent: self)

        self.pdfController = controller
        self.pdfControllerLeft = leftConstraint
    }

    private func setupSidebarBorder() {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        self.view.addSubview(view)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 1),
            view.leadingAnchor.constraint(equalTo: self.annotationsController.view.trailingAnchor),
            view.topAnchor.constraint(equalTo: self.view.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }

    private func setupNavigationBar() {
        let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "line.horizontal.3"),
                                            style: .plain, target: self,
                                            action: #selector(PDFReaderViewController.toggleSidebar))
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "xmark"),
                                          style: .plain, target: self,
                                          action: #selector(PDFReaderViewController.close))
        self.navigationItem.leftBarButtonItems = [closeButton, sidebarButton]

        let settings = self.pdfController.settingsButtonItem
        settings.rx
                .tap
                .subscribe(onNext: { [weak self] _ in
                    self?.showSettings(sender: settings)
                })
                .disposed(by: self.disposeBag)

        let search = self.pdfController.searchButtonItem
        search.rx
              .tap
              .subscribe(onNext: { [weak self] _ in
                  self?.showSearch(sender: search)
              })
              .disposed(by: self.disposeBag)

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

        self.navigationItem.rightBarButtonItems = [redo, undo, settings, search]
    }

    private func setupObserving() {
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
        guard let selected = self.viewModel.state.selectedAnnotation,
              let annotation = self.viewModel.state.document.annotation(on: pageIndex, with: selected.key) else { return }

        if !pageView.selectedAnnotations.contains(annotation) {
            pageView.selectedAnnotations = [annotation]
        }
    }

    func pdfViewController(_ pdfController: PDFViewController, willBeginDisplaying pageView: PDFPageView, forPageAt pageIndex: Int) {
        // Save current page
        self.pageController.store(page: pageIndex, for: self.viewModel.state.key)
    }

    func pdfViewController(_ pdfController: PDFViewController,
                           shouldSelect annotations: [PSPDFKit.Annotation],
                           on pageView: PDFPageView) -> [PSPDFKit.Annotation] {
        // Only zotero annotations can be selected, except highlight annotation
        return annotations.filter({ $0.isZotero })
    }

    func pdfViewController(_ pdfController: PDFViewController, didSelect annotations: [PSPDFKit.Annotation], on pageView: PDFPageView) {
        guard let annotation = annotations.first,
              let key = annotation.key else { return }
        self.viewModel.process(action: .selectAnnotationFromDocument(key: key, page: Int(pageView.pageIndex)))
    }

    func pdfViewController(_ pdfController: PDFViewController, didDeselect annotations: [PSPDFKit.Annotation], on pageView: PDFPageView) {
        self.viewModel.process(action: .selectAnnotation(nil))
    }

    func pdfViewController(_ pdfController: PDFViewController, didTapOn pageView: PDFPageView, at viewPoint: CGPoint) -> Bool {
        self.viewModel.process(action: .selectAnnotation(nil))
        pdfController.searchHighlightViewManager.clearHighlightedSearchResults(animated: true)
        return true
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
      return []
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
        self.navigationItem.rightBarButtonItems?.first(where: { $0.tag == NavigationBarButton.redo.rawValue })?.isEnabled = redoEnabled
        self.navigationItem.rightBarButtonItems?.first(where: { $0.tag == NavigationBarButton.undo.rawValue })?.isEnabled = undoEnabled
    }
}

extension PDFReaderViewController: PdfPreviewLoader {
    func createPreviewLoader(for annotation: Annotation, parentKey: String, document: Document) -> Single<UIImage>? {
        guard annotation.type != .note else { return nil }

        let boundingBox = annotation.boundingBox
        let previewRect: CGRect

        if let pageView = self.pdfController.pageViewForPage(at: UInt(annotation.page)) {
            var viewCoordinatesBoundingBox = pageView.convert(boundingBox, from: pageView.pdfCoordinateSpace)
            viewCoordinatesBoundingBox = viewCoordinatesBoundingBox.insetBy(dx: -10, dy: -40)
            previewRect = pageView.convert(viewCoordinatesBoundingBox, to: pageView.pdfCoordinateSpace)
        } else {
            previewRect = boundingBox
        }

        return self.annotationPreviewController.render(document: document,
                                                       page: UInt(annotation.page),
                                                       rect: previewRect,
                                                       key: annotation.key,
                                                       parentKey: parentKey)
    }
}

class SelectionView: UIView {
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
        self.layer.borderColor = Asset.Colors.zoteroBlue.color.cgColor
        self.layer.borderWidth = 1
    }
}

#endif
