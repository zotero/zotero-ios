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

    private let viewModel: ViewModel<PDFReaderActionHandler>
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

        if tab != .annotations {
            // Showing a tab other than annotations, so setting sidebar editing to false, in case annotations were edited previously.
            viewModel.process(action: .setSidebarEditingEnabled(false))
        }
        
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
            let initialState = viewModel.state
            let annotationProvider = viewModel.handler.annotationProvider
            let annotationsViewModel = ViewModel(
                initialState: PDFAnnotationsState(
                    key: initialState.key,
                    document: initialState.document,
                    userId: initialState.userId,
                    username: initialState.username,
                    library: initialState.library,
                    settings: initialState.settings,
                    interfaceStyle: initialState.interfaceStyle,
                    annotationPages: initialState.annotationPages,
                    selectedAnnotationKey: initialState.selectedAnnotationKey,
                    selectedAnnotationCommentActive: initialState.selectedAnnotationCommentActive,
                    sidebarEditingEnabled: initialState.sidebarEditingEnabled,
                    searchTerm: initialState.searchTerm,
                    filter: initialState.filter,
                    databaseAnnotations: initialState.databaseAnnotations,
                    documentAnnotations: initialState.documentAnnotations,
                    documentAnnotationKeys: annotationProvider?.keys ?? [],
                    documentAnnotationUniqueBaseColors: annotationProvider?.uniqueBaseColors ?? []
                ),
                handler: PDFAnnotationsActionHandler()
            )
            annotationsViewModel.process(action: .initializeSortedKeys)
            let disposeBag = DisposeBag()
            controllerDisposeBag = disposeBag

            viewModel
                .stateObservable
                .subscribe(onNext: { [weak annotationsViewModel] state in
                    guard let annotationsViewModel else { return }
                    if state.changes.contains(.annotations) {
                        let updatesSelection = state.changes.contains(.selection) && state.selectionFromDocument
                        annotationsViewModel.process(action: .setAnnotations(
                            annotationPages: state.annotationPages,
                            changedAnnotationKeys: state.changedAnnotationKeys,
                            selectedAnnotationKey: updatesSelection ? state.selectedAnnotationKey : nil,
                            selectionFromDocument: updatesSelection,
                            databaseAnnotations: state.databaseAnnotations
                        ))
                    } else if state.changes.contains(.selection), state.selectionFromDocument {
                        annotationsViewModel.process(action: .setSelection(
                            selectedAnnotationKey: state.selectedAnnotationKey,
                            selectionFromDocument: state.selectionFromDocument
                        ))
                    }
                    if state.changes.contains(.library) {
                        annotationsViewModel.process(action: .setLibrary(state.library))
                    }
                    if state.changes.contains(.appearance) {
                        annotationsViewModel.process(action: .setAppearance(settings: state.settings, interfaceStyle: state.interfaceStyle))
                    } else if state.changes.contains(.settings) {
                        annotationsViewModel.process(action: .setSettings(state.settings))
                    }
                })
                .disposed(by: disposeBag)

            annotationsViewModel
                .stateObservable
                .subscribe(onNext: { [weak viewModel] state in
                    guard let viewModel else { return }
                    if state.changes.contains(.activeComment) {
                        viewModel.process(action: .setCommentActive(state.selectedAnnotationCommentActive))
                    }
                    if state.changes.contains(.sidebarEditing) {
                        viewModel.process(action: .setSidebarEditingEnabled(state.sidebarEditingEnabled))
                    }
                    if state.changes.contains(.filter) {
                        viewModel.process(action: .filterAnnotations(searchTerm: state.searchTerm, filter: state.filter))
                    }
                    if state.changes.contains(.selection), state.selectionFromSidebar {
                        if let selectedAnnotationKey = state.selectedAnnotationKey {
                            viewModel.process(action: .selectAnnotation(selectedAnnotationKey))
                        } else {
                            viewModel.process(action: .deselectSelectedAnnotationFromDocument)
                        }
                    }
                    guard let action = state.outgoingAction else { return }
                    switch action {
                    case .setTags(let key, let tags):
                        viewModel.process(action: .setTags(key: key, tags: tags))

                    case .updateAnnotationProperties(let key, let type, let color, let lineWidth, let fontSize, let pageLabel, let updateSubsequentLabels, let highlightText, let higlightFont):
                        viewModel.process(action: .updateAnnotationProperties(
                            key: key,
                            type: type,
                            color: color,
                            lineWidth: lineWidth,
                            fontSize: fontSize,
                            pageLabel: pageLabel,
                            updateSubsequentLabels: updateSubsequentLabels,
                            highlightText: highlightText,
                            higlightFont: higlightFont
                        ))

                    case .removeAnnotation(let key):
                        viewModel.process(action: .removeAnnotation(key))

                    case .setComment(let key, let comment):
                        viewModel.process(action: .setComment(key: key, comment: comment))

                    case .mergeAnnotations(let annotations):
                        viewModel.process(action: .mergeAnnotations(annotations))

                    case .removeAnnotations(let annotations):
                        viewModel.process(action: .removeAnnotations(annotations))
                    }
                })
                .disposed(by: disposeBag)

            let annotationsController = PDFAnnotationsViewController(
                viewModel: annotationsViewModel,
                annotationProvider: viewModel.handler.annotationProvider,
                annotationPreviewController: viewModel.handler.annotationPreviewController,
                initialAppearance: viewModel.handler.appearance
            )
            annotationsController.parentDelegate = parentDelegate
            annotationsController.coordinatorDelegate = coordinatorDelegate
            annotationsController.boundingBoxConverter = boundingBoxConverter
            return annotationsController
        }

        func createToCController() -> TableOfContentsViewController<PDFOutline> {
            let root = viewModel.state.document.outline.flatMap({ PDFOutline(element: $0) })
            let outlines = root?.children ?? []
            let visiblePage = UInt(max(viewModel.state.visiblePage, 0))
            let currentId = PDFSidebarViewController.findOutline(forPage: visiblePage, in: outlines)?.id
            let tocState = TableOfContentsState<PDFOutline>(outlines: outlines, currentOutlineId: currentId)
            let tocViewModel = ViewModel(initialState: tocState, handler: TableOfContentsActionHandler<PDFOutline>())

            let bag = DisposeBag()
            viewModel.stateObservable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak tocViewModel] state in
                    guard let tocViewModel, state.changes.contains(.visiblePage) else { return }
                    let page = UInt(max(state.visiblePage, 0))
                    let id = PDFSidebarViewController.findOutline(forPage: page, in: tocViewModel.state.outlines)?.id
                    tocViewModel.process(action: .setCurrentOutline(id))
                })
                .disposed(by: bag)
            controllerDisposeBag = bag

            return TableOfContentsViewController<PDFOutline>(viewModel: tocViewModel, selectionAction: { [weak self] outline in
                self?.parentDelegate?.tableOfContentsSelected(page: outline.page)
            })
        }

        func createThumbnailsController() -> PDFThumbnailsViewController {
            let thumbnailsState = PDFThumbnailsState(
                key: viewModel.state.key,
                libraryId: viewModel.state.library.identifier,
                document: viewModel.state.document,
                selectedPageIndex: viewModel.state.visiblePage,
                appearance: viewModel.handler.appearance
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
                .subscribe(onNext: { [weak viewModel] state in
                    guard let viewModel else { return }
                    if state.changes.contains(.selection) {
                        viewModel.process(action: .setVisiblePage(page: state.selectedPageIndex, userActionFromDocument: false, fromThumbnailList: true))
                    }
                })
                .disposed(by: disposeBag)

            return thumbnailsController
        }
    }

    private static func findOutline(forPage page: UInt, in outlines: [PDFOutline]) -> PDFOutline? {
        guard let best = outlines.filter({ $0.page <= page }).max(by: { $0.page < $1.page }) else { return nil }
        return findOutline(forPage: page, in: best.children) ?? best
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
