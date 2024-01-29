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
        return annotationView.actionPublisher
    }
    var disposeBag: CompositeDisposable? {
        return annotationView.disposeBag
    }

    // MARK: - Lifecycle

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        key = ""
        disposeBag?.dispose()
    }

    // MARK: - Actions

    func updatePreview(image: UIImage?) {
        annotationView?.updatePreview(image: image)
    }

    // MARK: - Setups

    private func setupView() {
        backgroundColor = .systemGray6

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

        contentView.addSubview(selectionView)
        contentView.addSubview(annotationView)

        let selectionViewHorizontal = PDFReaderLayout.annotationLayout.horizontalInset - PDFReaderLayout.cellSelectionLineWidth
        let selectionViewBottom = PDFReaderLayout.cellSeparatorHeight - (PDFReaderLayout.cellSelectionLineWidth * 2)
        let annotationViewBottom = selectionViewBottom + PDFReaderLayout.cellSelectionLineWidth

        NSLayoutConstraint.activate([
            selectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: selectionViewHorizontal),
            contentView.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: selectionViewHorizontal),
            selectionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: selectionView.bottomAnchor, constant: selectionViewBottom),
            annotationView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: PDFReaderLayout.annotationLayout.horizontalInset),
            contentView.trailingAnchor.constraint(equalTo: annotationView.trailingAnchor, constant: PDFReaderLayout.annotationLayout.horizontalInset),
            annotationView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: PDFReaderLayout.cellSelectionLineWidth),
            contentView.bottomAnchor.constraint(equalTo: annotationView.bottomAnchor, constant: annotationViewBottom)
        ])
    }

    func setup(
        with annotation: HtmlEpubAnnotation,
        comment: AnnotationView.Comment?,
        selected: Bool,
        availableWidth: CGFloat,
        library: Library,
        isEditing: Bool,
        currentUserId: Int,
        state: HtmlEpubReaderState
    ) {
        if !selected {
            annotationView.resignFirstResponder()
        }

        key = annotation.key
        selectionView.layer.borderWidth = selected ? PDFReaderLayout.cellSelectionLineWidth : 0
        let availableWidth = availableWidth - (PDFReaderLayout.annotationLayout.horizontalInset * 2)
        annotationView.setup(
            with: annotation,
            comment: comment,
            selected: selected,
            availableWidth: availableWidth,
            library: library,
            currentUserId: currentUserId
        )

        setupAccessibility(
            isAuthor: annotation.isAuthor,
            authorName: annotation.author,
            type: annotation.type,
            pageLabel: annotation.pageLabel,
            text: annotation.text,
            comment: annotation.comment,
            selected: selected
        )
    }

    func setup(
        with annotation: PDFAnnotation,
        text: NSAttributedString?,
        comment: AnnotationView.Comment?,
        preview: UIImage?,
        selected: Bool,
        availableWidth: CGFloat,
        library: Library,
        isEditing: Bool,
        currentUserId: Int,
        displayName: String,
        username: String,
        boundingBoxConverter: AnnotationBoundingBoxConverter,
        pdfAnnotationsCoordinatorDelegate: PdfAnnotationsCoordinatorDelegate,
        state: PDFReaderState
    ) {
        if !selected {
            annotationView.resignFirstResponder()
        }

        let reconfiguringForSameAnnotation = key == annotation.key
        key = annotation.key
        selectionView.layer.borderWidth = selected ? PDFReaderLayout.cellSelectionLineWidth : 0
        let availableWidth = availableWidth - (PDFReaderLayout.annotationLayout.horizontalInset * 2)
        annotationView.setup(
            with: annotation,
            text: text,
            comment: comment,
            preview: preview,
            selected: selected,
            availableWidth: availableWidth,
            library: library,
            currentUserId: currentUserId,
            displayName: displayName,
            username: username,
            boundingBoxConverter: boundingBoxConverter,
            pdfAnnotationsCoordinatorDelegate: pdfAnnotationsCoordinatorDelegate,
            state: state
        )
        if !reconfiguringForSameAnnotation {
            annotationView.setupObserving()
        }
        // Otherwise, reconfigured cells do not have their prepareForReuse method called, so observing is already set up.

        setupAccessibility(
            isAuthor: annotation.isAuthor(currentUserId: currentUserId),
            authorName: annotation.author(displayName: displayName, username: username),
            type: annotation.type,
            pageLabel: annotation.pageLabel,
            text: annotation.text,
            comment: annotation.comment,
            selected: selected
        )
    }

    private func setupAccessibility(isAuthor: Bool, authorName: String, type: AnnotationType, pageLabel: String, text: String?, comment: String, selected: Bool) {
        let author = isAuthor ? nil : authorName
        var label = accessibilityLabel(for: type, pageLabel: pageLabel, author: author)
        if let text {
            switch type {
            case .highlight:
                label += ", " + L10n.Accessibility.Pdf.highlightedText + ": " + text

            case .underline:
                label += ", " + L10n.Accessibility.Pdf.underlinedText + ": " + text

            case .note, .image, .ink, .freeText:
                break
            }
        }
        if !selected {
            if !comment.isEmpty {
                label += ", " + L10n.Accessibility.Pdf.comment + ": " + comment
            }
            if let tags = annotationView.tagString, !tags.isEmpty {
                label += ", " + L10n.Accessibility.Pdf.tags + ": " + tags
            }
        }

        isAccessibilityElement = false
        accessibilityLabel = label
        accessibilityTraits = .button
        if selected {
            accessibilityHint = nil
        } else {
            accessibilityHint = L10n.Accessibility.Pdf.annotationHint
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

        case .underline:
            annotationName = L10n.Accessibility.Pdf.underlineAnnotation

        case .freeText:
            annotationName = L10n.Accessibility.Pdf.textAnnotation
        }
        var label = annotationName + ", " + L10n.page + " " + pageLabel
        if let author = author {
            label += ", \(L10n.Accessibility.Pdf.author): " + author
        }
        return label
    }
}
