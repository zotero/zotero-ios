//
//  AnnotationViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 13/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

#if PDFENABLED

typealias AnnotationViewControllerAction = (AnnotationView.Action, Annotation, UIButton) -> Void

class AnnotationViewController: UIViewController {
    private let viewModel: ViewModel<PDFReaderActionHandler>
    private let disposeBag: DisposeBag

    private weak var annotationView: AnnotationView?

    weak var coordinatorDelegate: AnnotationPopoverAnnotationCoordinatorDelegate?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let annotationView = AnnotationView(type: .popover)
        annotationView.widthAnchor.constraint(equalToConstant: PDFReaderLayout.annotationPopoverWidth).isActive = true
        self.annotationView = annotationView

        let view = UIView()
        view.backgroundColor = .white
        view.addSubview(annotationView)

        NSLayoutConstraint.activate([
            annotationView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            annotationView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            annotationView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor),
            annotationView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor)
        ])

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupAnnotationView()

        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.updatePreferredContentSize()
    }

    // MARK: - Actions

    private func updatePreferredContentSize() {
        guard let size = self.annotationView?.systemLayoutSizeFitting(CGSize(width: PDFReaderLayout.annotationPopoverWidth, height: .greatestFiniteMagnitude)) else { return }
        self.preferredContentSize = size
        self.navigationController?.preferredContentSize = size
    }

    private func update(state: PDFReaderState) {
        if let keys = state.loadedPreviewImageAnnotationKeys,
           let selectedKey = state.selectedAnnotation?.key,
           keys.contains(selectedKey) {
            let preview = state.previewCache.object(forKey: (selectedKey as NSString))
            self.annotationView?.updatePreview(image: preview)
        }

        if state.selectedAnnotation == nil {
            self.dismiss(animated: true, completion: nil)
        }
    }

    private func perform(action: AnnotationView.Action) {
        let state = self.viewModel.state

        guard state.library.metadataEditable,
              let annotation = state.selectedAnnotation else { return }

        switch action {
        case .highlight, .options:
            self.coordinatorDelegate?.showEdit()
        case .setComment(let comment):
            guard let key = self.viewModel.state.selectedAnnotation?.key else { return }
            self.viewModel.process(action: .setComment(key: key, comment: comment))
        case .reloadHeight:
            self.updatePreferredContentSize()
        case .tags:
            guard annotation.isAuthor else { return }

            let selected = Set(annotation.tags.map({ $0.name }))
            self.coordinatorDelegate?.showTagPicker(libraryId: state.library.identifier, selected: selected, picked: { [weak self] tags in
                self?.viewModel.process(action: .setTags(tags, annotation.key))
            })
        }
    }

    private func update(annotationView: AnnotationView, state: PDFReaderState) {
        guard let annotation = state.selectedAnnotation else { return }
        let comment = state.comments[annotation.key]
        annotationView.setup(with: annotation, attributedComment: comment, preview: nil, selected: true,
                             availableWidth: PDFReaderLayout.annotationPopoverWidth, hasWritePermission: state.library.metadataEditable)
    }

    // MARK: - Setups

    private func setupAnnotationView() {
        guard let annotationView = self.annotationView else { return }
        self.update(annotationView: annotationView, state: self.viewModel.state)
        annotationView.actionPublisher.subscribe(onNext: { [weak self] action in
            self?.perform(action: action)
        })
        .disposed(by: annotationView.disposeBag)
    }
}

#endif
