//
//  AnnotationCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationCell: UITableViewCell {
    private(set) var key: String = ""
    private weak var annotationView: AnnotationView?

    var performAction: AnnotationViewAction? {
        get {
            return self.annotationView?.performAction
        }

        set {
            self.annotationView?.performAction = newValue
        }
    }

    // MARK: - Lifecycle

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.selectionStyle = .none
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.selectionStyle = .none
        self.setupView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.key = ""
    }

    // MARK: - Actions

    func updatePreview(image: UIImage?) {
        self.annotationView?.updatePreview(image: image)
    }

    // MARK: - Setups

    private func setupView() {
        let view = AnnotationView()
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        self.contentView.addSubview(view)
        self.annotationView = view

        self.contentView.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: PDFReaderLayout.horizontalInset),
            self.contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: PDFReaderLayout.horizontalInset),
            view.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 0),
            self.contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func setup(with annotation: Annotation, attributedComment: NSAttributedString?, preview: UIImage?, selected: Bool, availableWidth: CGFloat, hasWritePermission: Bool) {
        self.key = annotation.key

        self.annotationView?.backgroundColor = Asset.Colors.annotationCellBackground.color
        self.annotationView?.layer.borderColor = selected ? Asset.Colors.annotationSelectedCellBorder.color.cgColor : nil
        self.annotationView?.layer.borderWidth = selected ? 3 : 0
        self.annotationView?.setup(with: annotation, attributedComment: attributedComment, preview: preview, selected: selected,
                                   availableWidth: (availableWidth - (PDFReaderLayout.horizontalInset * 2)), hasWritePermission: hasWritePermission)
    }
}
