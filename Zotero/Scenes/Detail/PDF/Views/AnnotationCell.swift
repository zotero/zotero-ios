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
    private weak var annotationView: AnnotationView!
    private weak var selectionView: UIView!

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
        let selectionView = UIView()
        selectionView.backgroundColor = Asset.Colors.annotationCellBackground.color
        selectionView.layer.cornerRadius = 10
        selectionView.layer.borderColor = Asset.Colors.annotationSelectedCellBorder.color.cgColor
        selectionView.layer.masksToBounds = true
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        self.selectionView = selectionView

        let annotationView = AnnotationView()
        annotationView.layer.cornerRadius = 10
        annotationView.layer.masksToBounds = true
        annotationView.backgroundColor = Asset.Colors.annotationCellBackground.color
        self.annotationView = annotationView

        self.contentView.addSubview(selectionView)
        self.contentView.addSubview(annotationView)

        let selectionViewHorizontal = PDFReaderLayout.annotationsHorizontalInset - PDFReaderLayout.annotationSelectionLineWidth
        let selectionViewBottom = PDFReaderLayout.annotationsCellSeparatorHeight - (PDFReaderLayout.annotationSelectionLineWidth * 2)
        let annotationViewBottom = selectionViewBottom + PDFReaderLayout.annotationSelectionLineWidth

        NSLayoutConstraint.activate([
            selectionView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: selectionViewHorizontal),
            self.contentView.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: selectionViewHorizontal),
            selectionView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.contentView.bottomAnchor.constraint(equalTo: selectionView.bottomAnchor, constant: selectionViewBottom),
            annotationView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            self.contentView.trailingAnchor.constraint(equalTo: annotationView.trailingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            annotationView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: PDFReaderLayout.annotationSelectionLineWidth),
            self.contentView.bottomAnchor.constraint(equalTo: annotationView.bottomAnchor, constant: annotationViewBottom)
        ])
    }

    func setup(with annotation: Annotation, attributedComment: NSAttributedString?, preview: UIImage?, selected: Bool, availableWidth: CGFloat, hasWritePermission: Bool) {
        self.key = annotation.key
        self.selectionView.layer.borderWidth = selected ? PDFReaderLayout.annotationSelectionLineWidth : 0
        let availableWidth = availableWidth - (PDFReaderLayout.annotationsHorizontalInset * 2)
        self.annotationView.setup(with: annotation, attributedComment: attributedComment, preview: preview, selected: selected, availableWidth: availableWidth, hasWritePermission: hasWritePermission)
    }
}
