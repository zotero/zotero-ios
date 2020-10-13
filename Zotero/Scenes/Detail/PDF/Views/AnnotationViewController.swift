//
//  AnnotationViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 13/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

typealias AnnotationViewControllerAction = (AnnotationView.Action, Annotation, UIButton) -> Void

class AnnotationViewController: UIViewController {
    private static let width: CGFloat = 300

    private let annotation: Annotation
    private let attributedComment: NSAttributedString?
    private let preview: UIImage?
    private let hasWritePermission: Bool

    private var annotationView: AnnotationView? {
        return self.view as? AnnotationView
    }

    var performAction: AnnotationViewControllerAction?

    init(annotation: Annotation, attributedComment: NSAttributedString?, preview: UIImage?, hasWritePermission: Bool) {
        self.annotation = annotation
        self.attributedComment = attributedComment
        self.preview = preview
        self.hasWritePermission = hasWritePermission
        super.init(nibName: nil, bundle: nil)
        self.preferredContentSize = CGSize(width: AnnotationViewController.width, height: UIView.noIntrinsicMetric)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        guard let view = Bundle.main.loadNibNamed("AnnotationView", owner: nil, options: nil)?.first as? UIView else { fatalError() }
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.annotationView?.setup(with: self.annotation, attributedComment: self.attributedComment, preview: self.preview, selected: true, availableWidth: AnnotationViewController.width, hasWritePermission: self.hasWritePermission)
        self.annotationView?.performAction = { [weak self] action, sender in
            guard let annotation = self?.annotation else { return }
            self?.performAction?(action, annotation, sender)
        }
    }

    func updatePreview(image: UIImage?) {
        self.annotationView?.updatePreview(image: image)
    }
}
