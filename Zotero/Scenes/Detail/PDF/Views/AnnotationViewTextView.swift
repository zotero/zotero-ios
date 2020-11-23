//
//  AnnotationViewTextView.swift
//  Zotero
//
//  Created by Michal Rentka on 20.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class AnnotationViewTextView: UIView {
    private weak var label: UILabel!
    private weak var textView: UITextView!
    private weak var topInsetConstraint: NSLayoutConstraint!

    private let placeholder: String

    private var observer: AnyObserver<(NSAttributedString, Bool)>?
    var textObservable: Observable<(NSAttributedString, Bool)> {
        return Observable.create { observer -> Disposable in
            self.observer = observer
            return Disposables.create()
        }
    }

    init(placeholder: String, minHeight: CGFloat?) {
        self.placeholder = placeholder

        let label = UILabel()
        label.font = PDFReaderLayout.font
        label.numberOfLines = 0
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true

        let textView = UITextView()
        textView.font = PDFReaderLayout.font
        textView.textContainerInset = UIEdgeInsets()
        textView.textContainer.lineFragmentPadding = 0
        textView.text = placeholder
        textView.textColor = .lightGray
        textView.isScrollEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white

        self.addSubview(textView)
        self.addSubview(label)

        let topFontOffset = PDFReaderLayout.font.ascender - PDFReaderLayout.font.xHeight
        let topInset = label.topAnchor.constraint(equalTo: self.topAnchor, constant: PDFReaderLayout.annotationsCellSeparatorHeight - topFontOffset)

        if let minHeight = minHeight {
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true
        }

        NSLayoutConstraint.activate([
            // Horizontal
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            self.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            textView.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            // Vertical
            topInset,
            self.bottomAnchor.constraint(equalTo: label.lastBaselineAnchor, constant: PDFReaderLayout.annotationsCellSeparatorHeight),
            textView.topAnchor.constraint(equalTo: label.topAnchor),
            textView.bottomAnchor.constraint(equalTo: label.bottomAnchor)
        ])

        textView.delegate = self
        self.label = label
        self.textView = textView
        self.topInsetConstraint = topInset
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(text: NSAttributedString?, halfTopInset: Bool) {
        self.label.attributedText = text
        if let text = text, !text.string.isEmpty {
            self.textView.textColor = .black
            self.textView.attributedText = text
        } else {
            self.textView.textColor = .lightGray
            self.textView.text = self.placeholder
        }

        let topFontOffset = PDFReaderLayout.font.ascender - PDFReaderLayout.font.xHeight
        let topInset = halfTopInset ? (PDFReaderLayout.annotationsCellSeparatorHeight / 2) : PDFReaderLayout.annotationsCellSeparatorHeight
        self.topInsetConstraint.constant = topInset - topFontOffset
    }
}

extension AnnotationViewTextView: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.text == self.placeholder {
            textView.text = ""
            textView.textColor = .black
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = self.placeholder
            textView.textColor = .lightGray
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        let height = self.label.frame.height
        self.label.attributedText = textView.attributedText
        self.label.layoutIfNeeded()
        let needsReload = height != self.label.frame.height
        self.observer?.on(.next((textView.attributedText, needsReload)))
    }
}
