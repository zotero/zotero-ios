//
//  AnnotationPreviewCommentEditorViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 30/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class AnnotationPreviewCommentEditorViewController: UIViewController {
    private let imageLoadSingle: Single<UIImage>?
    private let text: String
    private unowned let converter: HtmlAttributedStringConverter?
    private let saveAction: (String) -> Void
    private let disposeBag: DisposeBag

    private weak var activityIndicator: UIActivityIndicatorView?
    private weak var imageView: UIImageView?
    private weak var imageHeightConstraint: NSLayoutConstraint?
    private weak var commentEditorController: AnnotationCommentEditorViewController?

    // MARK: - Lifecycle

    init(text: String, imageLoader: Single<UIImage>?, converter: HtmlAttributedStringConverter? = nil,
         saveAction: @escaping (String) -> Void) {
        self.text = text
        self.imageLoadSingle = imageLoader
        self.converter = converter
        self.saveAction = saveAction
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .white
        self.setupViews()
        self.setupNavigationBar()
        self.loadPreview()
    }

    // MARK: - Actions

    private func loadPreview() {
        guard let imageLoader = self.imageLoadSingle else {
            self.set(preview: nil, animated: false)
            return
        }

        imageLoader.observeOn(MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self] image in
                       self?.set(preview: image, animated: true)
                   }, onError: { [weak self] _ in
                       self?.set(preview: nil, animated: true)
                   })
                   .disposed(by: self.disposeBag)
    }

    private func set(preview: UIImage?, animated: Bool) {
        self.imageView?.image = preview

        if preview == nil {
            self.imageHeightConstraint?.constant = 0
        } else {
            self.imageHeightConstraint?.isActive = false
        }

        self.activityIndicator?.stopAnimating()

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func cancel() {
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupViews() {
        let imageView = UIImageView(image: nil)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .secondarySystemBackground
        self.imageView = imageView

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        self.activityIndicator = activityIndicator

        let commentEditor = AnnotationCommentEditorViewController(text: self.text, converter: self.converter, saveAction: self.saveAction)
        commentEditor.view.translatesAutoresizingMaskIntoConstraints = false
        self.commentEditorController = commentEditor

        commentEditor.willMove(toParent: self)
        self.addChild(commentEditor)
        self.view.addSubview(commentEditor.view)
        commentEditor.didMove(toParent: self)

        self.view.addSubview(imageView)
        self.view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: commentEditor.view.topAnchor),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
            commentEditor.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            commentEditor.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            commentEditor.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: imageView.centerXAnchor)
        ])

        let tmpHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 100)
        tmpHeightConstraint.isActive = true
        self.imageHeightConstraint = tmpHeightConstraint

        activityIndicator.startAnimating()
    }

    private func setupNavigationBar() {
        let cancel = UIBarButtonItem(title: L10n.cancel, style: .plain, target: self,
                                     action: #selector(AnnotationPreviewCommentEditorViewController.cancel))
        self.navigationItem.leftBarButtonItem = cancel

        let save = UIBarButtonItem(title: L10n.save, style: .done, target: self.commentEditorController,
                                   action: #selector(AnnotationCommentEditorViewController.save))
        self.navigationItem.rightBarButtonItem = save
    }
}
