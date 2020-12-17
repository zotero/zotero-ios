//
//  AnnotationCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class AnnotationCell: UITableViewCell {
    private(set) var key: String = ""
    private weak var annotationView: AnnotationView!
    private weak var selectionView: UIView!

    var actionPublisher: PublishSubject<AnnotationView.Action> {
        return self.annotationView.actionPublisher
    }
    var disposeBag: DisposeBag {
        return self.annotationView.disposeBag
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
        selectionView.backgroundColor = .systemGray6
        selectionView.layer.cornerRadius = 10
        selectionView.layer.borderColor = Asset.Colors.annotationSelectedCellBorder.color.cgColor
        selectionView.layer.masksToBounds = true
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        self.selectionView = selectionView

        let annotationView = AnnotationView(layout: PDFReaderLayout.annotationLayout, commentPlaceholder: L10n.Pdf.AnnotationsSidebar.addComment)
        annotationView.layer.cornerRadius = 10
        annotationView.layer.masksToBounds = true
        self.annotationView = annotationView

        self.contentView.addSubview(selectionView)
        self.contentView.addSubview(annotationView)

        let selectionViewHorizontal = PDFReaderLayout.annotationLayout.horizontalInset - PDFReaderLayout.cellSelectionLineWidth
        let selectionViewBottom = PDFReaderLayout.cellSeparatorHeight - (PDFReaderLayout.cellSelectionLineWidth * 2)
        let annotationViewBottom = selectionViewBottom + PDFReaderLayout.cellSelectionLineWidth

        NSLayoutConstraint.activate([
            selectionView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: selectionViewHorizontal),
            self.contentView.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: selectionViewHorizontal),
            selectionView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.contentView.bottomAnchor.constraint(equalTo: selectionView.bottomAnchor, constant: selectionViewBottom),
            annotationView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: PDFReaderLayout.annotationLayout.horizontalInset),
            self.contentView.trailingAnchor.constraint(equalTo: annotationView.trailingAnchor, constant: PDFReaderLayout.annotationLayout.horizontalInset),
            annotationView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: PDFReaderLayout.cellSelectionLineWidth),
            self.contentView.bottomAnchor.constraint(equalTo: annotationView.bottomAnchor, constant: annotationViewBottom)
        ])
    }

    func setup(with annotation: Annotation, attributedComment: NSAttributedString?, preview: UIImage?, selected: Bool, commentActive: Bool, availableWidth: CGFloat, hasWritePermission: Bool) {
        if !selected {
            self.annotationView.resignFirstResponder()
        }

        self.key = annotation.key
        self.selectionView.layer.borderWidth = selected ? PDFReaderLayout.cellSelectionLineWidth : 0
        let availableWidth = availableWidth - (PDFReaderLayout.annotationLayout.horizontalInset * 2)
        self.annotationView.setup(with: annotation, attributedComment: attributedComment, preview: preview, selected: selected, commentActive: commentActive, availableWidth: availableWidth, hasWritePermission: hasWritePermission)
    }
}
