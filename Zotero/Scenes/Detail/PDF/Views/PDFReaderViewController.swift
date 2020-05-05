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
    private static let sidebarWidth: CGFloat = 250
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
    }

    @objc private func toggleSidebar() {
        let shouldShow = self.pdfControllerLeft.constant == 0
        self.pdfControllerLeft.constant = shouldShow ? PDFReaderViewController.sidebarWidth : 0
        self.annotationsControllerLeft.constant = shouldShow ? 0 : -PDFReaderViewController.sidebarWidth

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
            controller.view.widthAnchor.constraint(equalToConstant: PDFReaderViewController.sidebarWidth)
        ])
        let leftConstraint = controller.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor,
                                                                constant: -PDFReaderViewController.sidebarWidth)
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
}

extension PDFReaderViewController: PDFViewControllerDelegate {
    func pdfViewController(_ pdfController: PDFViewController,
                           shouldSelect annotations: [PSPDFKit.Annotation],
                           on pageView: PDFPageView) -> [PSPDFKit.Annotation] {
        // Only zotero annotations can be selected
        return annotations.filter({ ($0.customData?[PDFReaderState.zoteroAnnotationKey] as? Bool) == true })
    }

    func pdfViewController(_ pdfController: PDFViewController,
                           shouldSave document: Document,
                           withOptions options: AutoreleasingUnsafeMutablePointer<NSDictionary>) -> Bool {
        return false
    }

    func pdfViewController(_ pdfController: PDFViewController, didTapOn pageView: PDFPageView, at viewPoint: CGPoint) -> Bool {
        self.viewModel.process(action: .selectAnnotation(nil))
        return true
    }

    func pdfViewController(_ pdfController: PDFViewController, didSelect annotations: [PSPDFKit.Annotation], on pageView: PDFPageView) {
        guard let annotation = annotations.first,
              let key = annotation.customData?[PDFReaderState.zoteroKeyKey] as? String else { return }
        self.viewModel.process(action: .selectAnnotationFromDocument(key: key, page: Int(pageView.pageIndex)))
    }
}

#endif
