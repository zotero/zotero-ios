//
//  ZPDFViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit
import PSPDFKitUI

class ZPDFViewController: UIViewController {
    private static let supportedAnnotations: Annotation.Kind = [.note, .highlight, .square]
    private static let sidebarWidth: CGFloat = 250
    private let url: URL

    private weak var annotationsController: AnnotationsViewController!
    private weak var pdfController: PDFViewController!
    private weak var annotationsControllerLeft: NSLayoutConstraint!
    private weak var pdfControllerLeft: NSLayoutConstraint!

//    private weak var imgTest: UIImageView!

    // MARK: - Lifecycle

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()

        let document = Document(url: self.url)

        let annotation = NoteAnnotation(contents: "Custom Annotation")
        annotation.boundingBox = CGRect(x: 30, y: 100, width: 32, height: 32)
        annotation.pageIndex = 3
        document.add(annotations: [annotation], options: nil)

        self.setupAnnotations(with: document)
        self.setupPdfController(with: document)


//        let imageView = UIImageView()
//        imageView.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
//        imageView.contentMode = .scaleAspectFit
//        imageView.backgroundColor = .red
//        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//        self.view.addSubview(imageView)
//        self.imgTest = imageView
//
//        if let (_, annotations) = document.allAnnotations(of: .square).first,
//           let annotation = annotations.first {
//            let image = annotation.image(size: CGSize(width: 200, height: 200), options: nil)
//            self.imgTest.image = image
//        }
    }

    // MARK: - Actions

    @objc private func toggleSidebar() {
        let shouldShow = self.pdfControllerLeft.constant == 0
        self.pdfControllerLeft.constant = shouldShow ? ZPDFViewController.sidebarWidth : 0
        self.annotationsControllerLeft.constant = shouldShow ? 0 : -ZPDFViewController.sidebarWidth

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

    private func setupAnnotations(with document: Document) {
        let controller = AnnotationsViewController(document: document, supportedAnnotations: ZPDFViewController.supportedAnnotations)
        controller.view.isHidden = true

        self.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.frame = self.view.bounds
        self.view.addSubview(controller.view)

        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            controller.view.widthAnchor.constraint(equalToConstant: ZPDFViewController.sidebarWidth)
        ])
        let leftConstraint = controller.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor,
                                                                constant: -ZPDFViewController.sidebarWidth)
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
                                            action: #selector(ZPDFViewController.toggleSidebar))
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "xmark"),
                                          style: .plain, target: self,
                                          action: #selector(ZPDFViewController.close))
        self.navigationItem.leftBarButtonItems = [closeButton, sidebarButton]
    }
}

extension ZPDFViewController: PDFViewControllerDelegate {
    func pdfViewController(_ pdfController: PDFViewController, shouldSelect annotations: [Annotation], on pageView: PDFPageView) -> [Annotation] {
        return annotations.filter({ ZPDFViewController.supportedAnnotations.contains($0.type) })
    }
}

#endif
