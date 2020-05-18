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
    private static let colorPreviewSize = CGSize(width: 15, height: 15)
    private let viewModel: ViewModel<PDFReaderActionHandler>
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

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()
        self.setupAnnotationsSidebar()
        self.setupPdfController(with: self.viewModel.state.document)
        self.setupAnnotationToolbar()
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
        self.pdfController.annotationStateManager.remove(self)
    }

    // MARK: - Actions

    private func update(state: PDFReaderState) {
        if state.changes.contains(.selection),
           let pageView = self.pdfController.pageViewForPage(at: self.pdfController.pageIndex) {
            self.updateSelection(on: pageView, selectedAnnotation: state.selectedAnnotation, pageIndex: Int(self.pdfController.pageIndex))
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
            let selectionView = SelectionView()
            selectionView.frame = pageView.convert(selection.boundingBox, from: pageView.pdfCoordinateSpace).insetBy(dx: -4, dy: -4)
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
        if location.page != self.pdfController.pageIndex {
            // Scroll to page, annotation will be selected by delegate
            self.pdfController.setPageIndex(UInt(location.page), animated: true)
            return
        }

        // Page already visible, select annotation
        guard let pageView = self.pdfController.pageViewForPage(at: UInt(location.page)),
              let annotation = document.annotation(on: location.page, with: key) else { return }

        if !pageView.selectedAnnotations.contains(annotation) {
            pageView.selectedAnnotations = [annotation]
        }
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

    @objc private func close() {
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupAnnotationsSidebar() {
        let controller = AnnotationsViewController(viewModel: self.viewModel)
        controller.view.isHidden = true

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

    private func setupAnnotationToolbar() {
        self.navigationItem.titleView = UIStackView(arrangedSubviews: self.createAnnotationToolbarButtons())
        self.navigationItem.rightBarButtonItems = self.createUndoRedoButtons()
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
            button.selectedBackgroundColor = .systemBlue
            button.selectedTintColor = .white
            button.layer.cornerRadius = 6
            button.layer.masksToBounds = true
        }

        let picker = UIButton()
        if let color = self.pdfController.annotationStateManager.lastUsedColor(forAnnotationString: .highlight) {
            picker.setImage(color.createImage(size: PDFReaderViewController.colorPreviewSize), for: .normal)
        }
        picker.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        picker.rx.controlEvent(.touchUpInside)
                 .subscribe(onNext: { [weak self] _ in
                    self?.showColorPicker()
                 })
                 .disposed(by: self.disposeBag)
        self.colorPickerbutton = picker

        return [highlight, note, area, picker]
    }

    private func createUndoRedoButtons() -> [UIBarButtonItem] {
        let undo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.left"), style: .plain, target: nil, action: nil)
        undo.isEnabled = self.pdfController.undoManager?.canUndo ?? false
        undo.rx
            .tap
            .subscribe(onNext: { [weak self] _ in
                self?.pdfController.undoManager?.undo()
            })
            .disposed(by: self.disposeBag)

        let redo = UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.right"), style: .plain, target: nil, action: nil)
        redo.isEnabled = self.pdfController.undoManager?.canRedo ?? false
        redo.rx
            .tap
            .subscribe(onNext: { [weak self] _ in
                self?.pdfController.undoManager?.redo()
            })
            .disposed(by: self.disposeBag)

        return [redo, undo]
    }

    private func setupPdfController(with document: Document) {
        let pdfConfiguration = PDFConfiguration { builder in
            builder.scrollDirection = .vertical
            builder.documentLabelEnabled = .NO
        }

        let controller = PDFViewController(document: document, configuration: pdfConfiguration)
        controller.delegate = self
        controller.formSubmissionDelegate = nil
        controller.annotationStateManager.add(self)

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

    private func setupNavigationBar() {
        let sidebarButton = UIBarButtonItem(image: UIImage(systemName: "line.horizontal.3"),
                                            style: .plain, target: self,
                                            action: #selector(PDFReaderViewController.toggleSidebar))
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "xmark"),
                                          style: .plain, target: self,
                                          action: #selector(PDFReaderViewController.close))
        self.navigationItem.leftBarButtonItems = [closeButton, sidebarButton]
    }

    private func setupObserving() {
        NotificationCenter.default.rx
                                  .notification(.PSPDFAnnotationChanged)
                                  .observeOn(MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      if let annotation = notification.object as? PSPDFKit.Annotation {
                                          self?.viewModel.process(action: .annotationChanged(annotation))
                                      }
                                  })
                                  .disposed(by: self.disposeBag)

        NotificationCenter.default.rx
                                  .notification(.PSPDFAnnotationsAdded)
                                  .observeOn(MainScheduler.instance)
                                  .subscribe(onNext: { [weak self] notification in
                                      if let annotations = notification.object as? [PSPDFKit.Annotation] {
                                          self?.viewModel.process(action: .annotationsAdded(annotations))
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
        // Dispatch async on main queue used so that the page can finish displaying before selection view is added. Otherwise the selection view
        // doesn't show up.
        DispatchQueue.main.async {
            self.updateSelection(on: pageView, selectedAnnotation: self.viewModel.state.selectedAnnotation, pageIndex: pageIndex)
        }
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
        self.navigationItem.rightBarButtonItems?.first?.isEnabled = redoEnabled
        self.navigationItem.rightBarButtonItems?.last?.isEnabled = undoEnabled
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
        self.layer.borderColor = UIColor.systemBlue.cgColor
        self.layer.borderWidth = 1
    }
}

#endif
