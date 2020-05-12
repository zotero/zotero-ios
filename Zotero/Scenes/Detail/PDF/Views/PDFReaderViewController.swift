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
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var annotationsController: AnnotationsViewController!
    private weak var pdfController: PDFViewController!
    private weak var annotationsControllerLeft: NSLayoutConstraint!
    private weak var pdfControllerLeft: NSLayoutConstraint!

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
        self.setupObserving()

        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .loadAnnotations)
    }

    // MARK: - Actions

    private func update(state: PDFReaderState) {
        if let location = state.focusDocumentLocation,
           let key = state.selectedAnnotation?.key {
            self.focusAnnotation(at: location, key: key, document: state.document)
        }
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

    private func setupPdfController(with document: Document) {
        let configuration = PDFConfiguration { builder in
            builder.scrollDirection = .vertical
        }
        let controller = PDFViewController(document: document, configuration: configuration)
        controller.delegate = self
        controller.formSubmissionDelegate = nil

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
    }
}

extension PDFReaderViewController: PDFViewControllerDelegate {
    func pdfViewController(_ pdfController: PDFViewController, willScheduleRenderTaskFor pageView: PDFPageView) {
    }

    func pdfViewController(_ pdfController: PDFViewController, didConfigurePageView pageView: PDFPageView, forPageAt pageIndex: Int) {
        guard let selected = self.viewModel.state.selectedAnnotation,
              let annotation = self.viewModel.state.document.annotation(on: pageIndex, with: selected.key) else { return }

        if !pageView.selectedAnnotations.contains(annotation) {
            pageView.selectedAnnotations = [annotation]
        }
    }

    func pdfViewController(_ pdfController: PDFViewController,
                           shouldSelect annotations: [PSPDFKit.Annotation],
                           on pageView: PDFPageView) -> [PSPDFKit.Annotation] {
        // Only zotero annotations can be selected, except highlight annotation
        return annotations.filter({ $0.isZoteroAnnotation })
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

    func pdfViewController(_ pdfController: PDFViewController, shouldShow controller: UIViewController, options: [String : Any]? = nil, animated: Bool) -> Bool {
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

class SelectableHighlightAnnotation: HighlightAnnotation {
    override var wantsSelectionBorder: Bool {
        return true
    }
}

#endif
