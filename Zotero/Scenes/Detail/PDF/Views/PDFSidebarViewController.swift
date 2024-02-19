//
//  PDFSidebarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 18.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

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
        case thumbnails

        var title: String {
            switch self {
            case .annotations:
                return "Annotations"

            case .outline:
                return "Outline"

            case .thumbnails:
                return "Thumbnails"
            }
        }

        static var sortedTabs: [Tab] {
            return [.thumbnails, .annotations, .outline]
        }
    }

    private unowned let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var picker: UISegmentedControl!
    private weak var thumbnailsController: PDFThumbnailsViewController!
    private weak var annotationsController: PDFAnnotationsViewController!
    private weak var outlineController: TableOfContentsViewController!
    weak var parentDelegate: (PDFReaderContainerDelegate & SidebarDelegate & AnnotationsDelegate)?
    weak var coordinatorDelegate: PdfAnnotationsCoordinatorDelegate?
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

        view.backgroundColor = .systemGray6
        definesPresentationContext = true

        setupControllers()
        setupViews()
        select(tab: .annotations)
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        thumbnailsController.set(visiblePage: viewModel.state.visiblePage)
    }

    private func select(tab: Tab) {
        guard let index = Tab.sortedTabs.firstIndex(of: tab) else { return }
        picker.selectedSegmentIndex = index
        show(tab: tab)
    }

    private func show(tab: Tab) {
        view.endEditing(true)
        annotationsController.view.isHidden = tab != .annotations
        outlineController.view.isHidden = tab != .outline
        thumbnailsController.view.isHidden = tab != .thumbnails
    }

    private func setupViews() {
        let picker = UISegmentedControl(items: Tab.sortedTabs.map({ $0.title }))
        picker.translatesAutoresizingMaskIntoConstraints = false

        picker.rx.controlEvent(.valueChanged).subscribe(with: self, onNext: { `self`, _ in
            let tab = Tab.sortedTabs[picker.selectedSegmentIndex]
            self.show(tab: tab)
        })
        .disposed(by: disposeBag)
        view.addSubview(picker)
        self.picker = picker

        let container = UIView()
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        annotationsController.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(annotationsController.view)
        outlineController.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(outlineController.view)
        thumbnailsController.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(thumbnailsController.view)

        picker.setContentHuggingPriority(.defaultHigh, for: .vertical)
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        annotationsController.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        outlineController.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        thumbnailsController.view.setContentHuggingPriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            container.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 4),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            view.trailingAnchor.constraint(equalTo: picker.trailingAnchor, constant: 15),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.topAnchor.constraint(equalTo: thumbnailsController.view.topAnchor),
            container.bottomAnchor.constraint(equalTo: thumbnailsController.view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: thumbnailsController.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: thumbnailsController.view.trailingAnchor),
            container.topAnchor.constraint(equalTo: annotationsController.view.topAnchor),
            container.bottomAnchor.constraint(equalTo: annotationsController.view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: annotationsController.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: annotationsController.view.trailingAnchor),
            container.topAnchor.constraint(equalTo: outlineController.view.topAnchor),
            container.bottomAnchor.constraint(equalTo: outlineController.view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: outlineController.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: outlineController.view.trailingAnchor)
        ])
    }

    private func setupControllers() {
        let annotationsController = PDFAnnotationsViewController(viewModel: viewModel)
        annotationsController.parentDelegate = parentDelegate
        annotationsController.coordinatorDelegate = coordinatorDelegate
        annotationsController.boundingBoxConverter = boundingBoxConverter
        add(childController: annotationsController)
        self.annotationsController = annotationsController

        let tocState = TableOfContentsState(document: viewModel.state.document)
        let outlineController = TableOfContentsViewController(viewModel: ViewModel(initialState: tocState, handler: TableOfContentsActionHandler()), selectionAction: { [weak self] page in
            self?.parentDelegate?.tableOfContentsSelected(page: page)
        })
        add(childController: outlineController)
        self.outlineController = outlineController

        let thumbnailsState = PDFThumbnailsState(
            key: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            document: viewModel.state.document,
            selectedPageIndex: viewModel.state.visiblePage,
            isDark: viewModel.state.interfaceStyle == .dark
        )
        let thumbnailsViewModel = ViewModel(initialState: thumbnailsState, handler: PDFThumbnailsActionHandler(thumbnailController: viewModel.handler.pdfThumbnailController))
        let thumbnailsController = PDFThumbnailsViewController(viewModel: thumbnailsViewModel)
        add(childController: thumbnailsController)
        self.thumbnailsController = thumbnailsController

        viewModel
            .stateObservable
            .subscribe(with: thumbnailsViewModel, onNext: { viewModel, state in
                guard state.changes.contains(.visiblePageFromDocument) else { return }
                viewModel.process(action: .setSelectedPage(pageIndex: state.visiblePage, type: .fromDocument))
            })
            .disposed(by: disposeBag)

        thumbnailsViewModel
            .stateObservable
            .subscribe(with: viewModel, onNext: { viewModel, state in
                guard state.changes.contains(.selection) else { return }
                viewModel.process(action: .setVisiblePage(page: state.selectedPageIndex, userActionFromDocument: false, fromThumbnailList: true))
            })
            .disposed(by: disposeBag)
    }

    private func add(childController controller: UIViewController) {
        controller.willMove(toParent: self)
        addChild(controller)
        controller.didMove(toParent: self)
    }
}
