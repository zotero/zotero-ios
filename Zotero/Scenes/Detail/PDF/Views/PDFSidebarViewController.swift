//
//  PDFSidebarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 18.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit
import PSPDFKitUI
import RxSwift

protocol SidebarDelegate: AnyObject {
    func tableOfContentsSelected(page: UInt)
}

class PDFSidebarViewController: UIViewController {
    enum Tab {
        case annotations
        case outline

        var title: String {
            switch self {
            case .annotations: return "Annotations"
            case .outline: return "Outline"
            }
        }

        static var sortedTabs: [Tab] {
            return [.annotations, .outline]
        }
    }

    private unowned let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var picker: UISegmentedControl!
    private weak var annotationsController: AnnotationsViewController!
    private weak var outlineController: TableOfContentsViewController!
    weak var parentDelegate: (PDFReaderContainerDelegate & SidebarDelegate)?
    weak var coordinatorDelegate: DetailAnnotationsCoordinatorDelegate?
    weak var boundingBoxConverter: AnnotationBoundingBoxConverter?

    required init?(coder: NSCoder) {
        fatalError()
    }

    init(viewModel: ViewModel<PDFReaderActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemGray6
        self.definesPresentationContext = true

        self.setupControllers()
        self.setupViews()
        self.select(tab: .annotations)
    }

    private func select(tab: Tab) {
        guard let index = Tab.sortedTabs.firstIndex(of: tab) else { return }
        self.picker.selectedSegmentIndex = index
        self.show(tab: tab)
    }

    private func show(tab: Tab) {
        self.view.endEditing(true)
        self.annotationsController.view.isHidden = tab != .annotations
        self.outlineController.view.isHidden = tab != .outline
    }

    private func setupViews() {
        let picker = UISegmentedControl(items: Tab.sortedTabs.map({ $0.title }))
        picker.translatesAutoresizingMaskIntoConstraints = false

        picker.rx.controlEvent(.valueChanged).subscribe(with: self, onNext: { `self`, _ in
            let tab = Tab.sortedTabs[self.picker.selectedSegmentIndex]
            self.show(tab: tab)
        })
        .disposed(by: self.disposeBag)
        self.view.addSubview(picker)
        self.picker = picker

        let container = UIView()
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(container)

        self.annotationsController.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self.annotationsController.view)
        self.outlineController.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self.outlineController.view)

        picker.setContentHuggingPriority(.defaultHigh, for: .vertical)
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        self.annotationsController.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        self.outlineController.view.setContentHuggingPriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            container.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 4),
            picker.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 15),
            self.view.trailingAnchor.constraint(equalTo: picker.trailingAnchor, constant: 15),
            self.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            self.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            self.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.topAnchor.constraint(equalTo: self.annotationsController.view.topAnchor),
            container.bottomAnchor.constraint(equalTo: self.annotationsController.view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: self.annotationsController.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: self.annotationsController.view.trailingAnchor),
            container.topAnchor.constraint(equalTo: self.outlineController.view.topAnchor),
            container.bottomAnchor.constraint(equalTo: self.outlineController.view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: self.outlineController.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: self.outlineController.view.trailingAnchor)
        ])
    }

    private func setupControllers() {
        let annotationsController = AnnotationsViewController(viewModel: self.viewModel)
        annotationsController.parentDelegate = self.parentDelegate
        annotationsController.coordinatorDelegate = self.coordinatorDelegate
        annotationsController.boundingBoxConverter = self.boundingBoxConverter
        self.addChild(annotationsController)
        self.annotationsController = annotationsController

        let state = TableOfContentsState(document: self.viewModel.state.document)
        let outlineController = TableOfContentsViewController(viewModel: ViewModel(initialState: state, handler: TableOfContentsActionHandler()), selectionAction: { [weak self] page in
            self?.parentDelegate?.tableOfContentsSelected(page: page)
        })
        self.addChild(outlineController)
        self.outlineController = outlineController
    }

    private func add(childController controller: UIViewController) {
        controller.willMove(toParent: self)
        self.addChild(controller)
        controller.didMove(toParent: self)
    }
}

#endif
