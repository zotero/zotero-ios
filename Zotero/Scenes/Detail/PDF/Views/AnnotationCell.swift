//
//  AnnotationCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class AnnotationCell: UITableViewCell {
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

    func setup(with annotation: Annotation, comment: AnnotationView.Comment?, preview: UIImage?, selected: Bool, availableWidth: CGFloat, library: Library) {
        if !selected {
            self.annotationView.resignFirstResponder()
        }

        self.key = annotation.key
        self.selectionView.layer.borderWidth = selected ? PDFReaderLayout.cellSelectionLineWidth : 0
        let availableWidth = availableWidth - (PDFReaderLayout.annotationLayout.horizontalInset * 2)
        self.annotationView.setup(with: annotation, comment: comment, preview: preview, selected: selected, availableWidth: availableWidth, library: library)

        self.setupAccessibility(for: annotation, selected: selected)
    }

    private func setupAccessibility(for annotation: Annotation, selected: Bool) {
        let author = annotation.isAuthor || annotation.author.isEmpty ? nil : annotation.author

        var label = self.accessibilityLabel(for: annotation.type, pageLabel: annotation.pageLabel, author: author)

        if let text = annotation.text {
            label += ", " + L10n.Accessibility.Pdf.highlightedText + ": " + text
        }

        if !selected {
            if !annotation.comment.isEmpty {
                label += ", " + L10n.Accessibility.Pdf.comment + ": " + annotation.comment
            }
            if let tags = self.annotationView.tagString, !tags.isEmpty {
                label += ", " + L10n.Accessibility.Pdf.tags + ": " + tags
            }
        }

        self.isAccessibilityElement = false
        self.accessibilityLabel = label
        self.accessibilityTraits = .button
        if selected {
            self.accessibilityHint = nil
        } else {
            self.accessibilityHint = L10n.Accessibility.Pdf.annotationHint
        }
    }

    private func accessibilityLabel(for type: AnnotationType, pageLabel: String, author: String?) -> String {
        let annotationName: String
        switch type {
        case .highlight:
            annotationName = L10n.Accessibility.Pdf.highlightAnnotation
        case .image:
            annotationName = L10n.Accessibility.Pdf.imageAnnotation
        case .note:
            annotationName = L10n.Accessibility.Pdf.noteAnnotation
        case .ink:
            annotationName = L10n.Accessibility.Pdf.inkAnnotation
        }
        var label = annotationName + ", " + L10n.page + " " + pageLabel
        if let author = author {
            label += ", \(L10n.Accessibility.Pdf.author): " + author
        }
        return label
    }
}
