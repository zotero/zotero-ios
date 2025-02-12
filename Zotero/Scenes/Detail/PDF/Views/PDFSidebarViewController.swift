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

protocol PDFSidebarDelegate: AnyObject {
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
    private weak var controllerContainer: UIView!
    private weak var currentController: UIViewController?
    private var controllerDisposeBag: DisposeBag?
    weak var parentDelegate: (PDFReaderContainerDelegate & PDFSidebarDelegate & ReaderAnnotationsDelegate)?
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

        view.isHidden = true
        view.backgroundColor = .systemGray6
        definesPresentationContext = true

        setupViews()
        select(tab: .annotations)
    }

    private func select(tab: Tab) {
        guard let index = Tab.sortedTabs.firstIndex(of: tab) else { return }
        picker.selectedSegmentIndex = index
        show(tab: tab)
    }

    private func show(tab: Tab) {
        view.endEditing(true)

        if let controller = currentController {
            controllerDisposeBag = nil
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            controller.didMove(toParent: nil)
        }

        let controller: UIViewController
        switch tab {
        case .annotations:
            controller = createAnnotationsController()

        case .outline:
            controller = createToCController()

        case .thumbnails:
            controller = createThumbnailsController()
        }

        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        controller.willMove(toParent: self)
        addChild(controller)
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        currentController = controller

        NSLayoutConstraint.activate([
            controllerContainer.topAnchor.constraint(equalTo: controller.view.topAnchor),
            controllerContainer.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            controllerContainer.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            controllerContainer.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor)
        ])

        func createAnnotationsController() -> PDFAnnotationsViewController {
            let annotationsController = PDFAnnotationsViewController(viewModel: viewModel)
            annotationsController.parentDelegate = parentDelegate
            annotationsController.coordinatorDelegate = coordinatorDelegate
            annotationsController.boundingBoxConverter = boundingBoxConverter
            return annotationsController
        }

        func createToCController() -> TableOfContentsViewController<PDFOutline> {
            let root = viewModel.state.document.outline.flatMap({ PDFOutline(element: $0) })
            let tocState = TableOfContentsState<PDFOutline>(outlines: root?.children ?? [])
            return TableOfContentsViewController<PDFOutline>(viewModel: ViewModel(initialState: tocState, handler: TableOfContentsActionHandler()), selectionAction: { [weak self] outline in
                self?.parentDelegate?.tableOfContentsSelected(page: outline.page)
            })
        }

        func createThumbnailsController() -> PDFThumbnailsViewController {
            let thumbnailsState = PDFThumbnailsState(
                key: viewModel.state.key,
                libraryId: viewModel.state.library.identifier,
                document: viewModel.state.document,
                selectedPageIndex: viewModel.state.visiblePage,
                appearance: .from(appearanceMode: viewModel.state.settings.appearanceMode, interfaceStyle: viewModel.state.interfaceStyle)
            )
            let thumbnailsViewModel = ViewModel(initialState: thumbnailsState, handler: PDFThumbnailsActionHandler(thumbnailController: viewModel.handler.pdfThumbnailController))
            let thumbnailsController = PDFThumbnailsViewController(viewModel: thumbnailsViewModel)
            let disposeBag = DisposeBag()
            controllerDisposeBag = disposeBag

            viewModel
                .stateObservable
                .subscribe(onNext: { [weak thumbnailsViewModel] state in
                    guard let thumbnailsViewModel else { return }
                    if state.changes.contains(.visiblePageFromDocument) {
                        thumbnailsViewModel.process(action: .setSelectedPage(pageIndex: state.visiblePage, type: .fromDocument))
                    }
                    if state.changes.contains(.annotations) {
                        thumbnailsViewModel.process(action: .reloadThumbnails)
                    }
                    if state.changes.contains(.appearance) {
                        thumbnailsViewModel.process(action: .setAppearance(.from(appearanceMode: state.settings.appearanceMode, interfaceStyle: state.interfaceStyle)))
                    }
                })
                .disposed(by: disposeBag)

            thumbnailsViewModel
                .stateObservable
                .subscribe(with: viewModel, onNext: { viewModel, state in
                    guard state.changes.contains(.selection) else { return }
                    viewModel.process(action: .setVisiblePage(page: state.selectedPageIndex, userActionFromDocument: false, fromThumbnailList: true))
                })
                .disposed(by: disposeBag)

            return thumbnailsController
        }
    }

    private func setupViews() {
        let picker = UISegmentedControl(items: Tab.sortedTabs.map({ $0.title }))
        picker.translatesAutoresizingMaskIntoConstraints = false

        picker.rx.controlEvent(.valueChanged).subscribe(onNext: { [weak self] _ in
            let tab = Tab.sortedTabs[picker.selectedSegmentIndex]
            self?.show(tab: tab)
        })
        .disposed(by: disposeBag)
        view.addSubview(picker)
        self.picker = picker

        let container = UIView()
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        controllerContainer = container

        picker.setContentHuggingPriority(.defaultHigh, for: .vertical)
        container.setContentHuggingPriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            container.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 4),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            view.trailingAnchor.constraint(equalTo: picker.trailingAnchor, constant: 15),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }
}
