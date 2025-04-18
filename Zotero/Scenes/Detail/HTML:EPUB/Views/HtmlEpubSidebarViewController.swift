//
//  HtmlEpubSidebarViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 10.02.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol HtmlEpubSidebarDelegate: AnyObject {
    func tableOfContentsSelected(location: [String: Any])
}

class HtmlEpubSidebarViewController: UIViewController {
    enum Tab {
        case annotations
        case outline

        var title: String {
            switch self {
            case .annotations:
                return "Annotations"

            case .outline:
                return "Outline"
            }
        }

        static var sortedTabs: [Tab] {
            return [.annotations, .outline]
        }
    }

    private unowned let viewModel: ViewModel<HtmlEpubReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var picker: UISegmentedControl!
    private weak var controllerContainer: UIView!
    private weak var currentController: UIViewController?
    private var controllerDisposeBag: DisposeBag?
    weak var parentDelegate: (HtmlEpubReaderContainerDelegate & ReaderAnnotationsDelegate & HtmlEpubSidebarDelegate)?
    weak var coordinatorDelegate: ReaderSidebarCoordinatorDelegate?

    required init?(coder: NSCoder) {
        fatalError()
    }

    init(viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
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

        func createAnnotationsController() -> HtmlEpubAnnotationsViewController {
            let annotationsController = HtmlEpubAnnotationsViewController(viewModel: viewModel)
            annotationsController.parentDelegate = parentDelegate
            annotationsController.coordinatorDelegate = coordinatorDelegate
            return annotationsController
        }

        func createToCController() -> TableOfContentsViewController<HtmlEpubOutline> {
            let outlines = viewModel.state.outlines.map(HtmlEpubOutline.init)
            let tocState = TableOfContentsState<HtmlEpubOutline>(outlines: outlines)
            return TableOfContentsViewController<HtmlEpubOutline>(viewModel: ViewModel(initialState: tocState, handler: TableOfContentsActionHandler()), selectionAction: { [weak self] outline in
                self?.parentDelegate?.tableOfContentsSelected(location: outline.location)
            })
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
