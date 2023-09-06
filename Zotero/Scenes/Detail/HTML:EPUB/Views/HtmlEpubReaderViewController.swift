//
//  HtmlEpubReaderViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24.08.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

class HtmlEpubReaderViewController: UIViewController {
    private let url: URL
    private let disposeBag: DisposeBag

    private weak var documentController: HtmlEpubDocumentViewController?
    private weak var annotationToolbarController: AnnotationToolbarViewController!
    private var navigationBarHeight: CGFloat {
        return self.navigationController?.navigationBar.frame.height ?? 0.0
    }

    init(url: URL) {
        self.url = url
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = UIView()
        self.view.backgroundColor = .systemBackground
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()
    }

    private func add(controller: UIViewController) {
        controller.willMove(toParent: self)
        self.addChild(controller)
        controller.didMove(toParent: self)
    }

    private func close() {
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    private func setupNavigationBar() {
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
        closeButton.title = L10n.close
        closeButton.accessibilityLabel = L10n.close
        closeButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.close() }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = closeButton
    }

    private func setupViews() {
        let documentController = HtmlEpubDocumentViewController(url: self.url)
        documentController.view.translatesAutoresizingMaskIntoConstraints = false

        let annotationToolbar = AnnotationToolbarViewController(tools: [.highlight, .note], size: self.navigationBarHeight)
        annotationToolbar.delegate = self
        annotationToolbar.view.translatesAutoresizingMaskIntoConstraints = false
        annotationToolbar.view.setContentHuggingPriority(.required, for: .horizontal)
        annotationToolbar.view.setContentHuggingPriority(.required, for: .vertical)

        self.add(controller: documentController)
        self.add(controller: annotationToolbar)
        self.view.addSubview(documentController.view)
        self.view.addSubview(annotationToolbar.view)

        self.documentController = documentController
        self.annotationToolbarController = annotationToolbar
    }
}

extension HtmlEpubReaderViewController: AnnotationToolbarDelegate {
    var rotation: AnnotationToolbarViewController.Rotation {
        return .horizontal
    }
    
    var activeAnnotationTool: AnnotationToolbarViewController.Tool? {
        return .highlight
    }
    
    var canUndo: Bool {
        return false
    }
    
    var canRedo: Bool {
        return false
    }
    
    var maxAvailableToolbarSize: CGFloat {
        return self.view.frame.width
    }
    
    func isCompactSize(for rotation: AnnotationToolbarViewController.Rotation) -> Bool {
        return false
    }
    
    func toggle(tool: AnnotationToolbarViewController.Tool, options: AnnotationToolOptions) {
    }
    
    func showToolOptions(sender: SourceView) {
    }
    
    func closeAnnotationToolbar() {
    }
    
    func performUndo() {
    }

    func performRedo() {
    }
}
