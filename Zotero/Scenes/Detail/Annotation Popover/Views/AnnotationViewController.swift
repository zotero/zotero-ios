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
    private unowned let attributedStringConverter: HtmlAttributedStringConverter
    private let disposeBag: DisposeBag

    private weak var annotationView: AnnotationView?

    weak var coordinatorDelegate: AnnotationPopoverAnnotationCoordinatorDelegate?

    private var commentPlaceholder: String {
        if self.viewModel.state.library.metadataEditable || self.viewModel.state.selectedAnnotation?.isAuthor == true {
            return L10n.Pdf.AnnotationsSidebar.addComment
        }
        return L10n.Pdf.AnnotationPopover.noComment
    }

    // MARK: - Lifecycle

    init(viewModel: ViewModel<PDFReaderActionHandler>, attributedStringConverter: HtmlAttributedStringConverter) {
        self.viewModel = viewModel
        self.attributedStringConverter = attributedStringConverter
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let annotationView = AnnotationView(layout: AnnotationPopoverLayout.annotationLayout, commentPlaceholder: self.commentPlaceholder)
        annotationView.widthAnchor.constraint(equalToConstant: AnnotationPopoverLayout.width).isActive = true
        self.annotationView = annotationView

        let view = UIView()
        view.backgroundColor = Asset.Colors.annotationPopoverBackground.color
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
        guard let size = self.annotationView?.systemLayoutSizeFitting(CGSize(width: AnnotationPopoverLayout.width, height: .greatestFiniteMagnitude)) else { return }
        self.preferredContentSize = size
        self.navigationController?.preferredContentSize = size
    }

    private func update(state: PDFReaderState) {
        guard let annotation = state.selectedAnnotation else {
            self.dismiss(animated: true, completion: nil)
            return
        }

        if let keys = state.loadedPreviewImageAnnotationKeys, keys.contains(annotation.key) {
            let preview = state.previewCache.object(forKey: (annotation.key as NSString))
            self.annotationView?.updatePreview(image: preview)
        }

        if state.changes.contains(.annotations), let annotation = state.selectedAnnotation {
            self.annotationView?.setupHeader(with: annotation, selected: true, hasWritePermission: state.library.metadataEditable)
        }
    }

    private func perform(action: AnnotationView.Action) {
        let state = self.viewModel.state

        guard state.library.metadataEditable,
              let annotation = state.selectedAnnotation else { return }

        switch action {
        case .options:
            self.coordinatorDelegate?.showEdit(annotation: annotation,
                                               saveAction: { [weak self] annotation in
                                                   self?.viewModel.process(action: .updateAnnotationProperties(annotation))
                                               },
                                               deleteAction: { [weak self] annotation in
                                                   self?.viewModel.process(action: .removeAnnotation(annotation))
                                               })
        case .setComment(let comment):
            self.viewModel.process(action: .setComment(key: annotation.key, comment: comment))

        case .setCommentActive: break

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
        let comment = self.attributedStringConverter.convert(text: annotation.comment, baseFont: AnnotationPopoverLayout.annotationLayout.font)
        annotationView.setup(with: annotation, attributedComment: comment, preview: nil, selected: true, commentActive: true,
                             availableWidth: AnnotationPopoverLayout.width, hasWritePermission: state.library.metadataEditable)
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
