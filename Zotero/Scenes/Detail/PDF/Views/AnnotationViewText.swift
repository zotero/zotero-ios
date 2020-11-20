//
//  AnnotationViewText.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa

class AnnotationViewText: UIView {
    private weak var textLabel: UILabel!
    private weak var button: UIButton!
    private weak var topInsetConstraint: NSLayoutConstraint!

    var tap: Observable<UIButton> {
        return self.button.rx.tap.flatMap({ Observable.just(self.button) })
    }

    init() {
        let label = UILabel()
        label.font = PDFReaderLayout.font
        label.numberOfLines = 0
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton()
        button.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        button.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white

        self.addSubview(label)
        self.addSubview(button)

        let topFontOffset = PDFReaderLayout.font.ascender - PDFReaderLayout.font.xHeight
        let topInset = label.topAnchor.constraint(equalTo: self.topAnchor, constant: PDFReaderLayout.annotationsCellSeparatorHeight - topFontOffset)

        NSLayoutConstraint.activate([
            // Horizontal
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            self.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            button.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            // Vertical
            topInset,
            self.bottomAnchor.constraint(equalTo: label.lastBaselineAnchor, constant: PDFReaderLayout.annotationsCellSeparatorHeight),
            button.topAnchor.constraint(equalTo: self.topAnchor),
            button.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.textLabel = label
        self.button = button
        self.topInsetConstraint = topInset
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(with attributedString: NSAttributedString?, halfTopInset: Bool) {
        self.textLabel.attributedText = attributedString

        let topFontOffset = PDFReaderLayout.font.ascender - PDFReaderLayout.font.xHeight
        let topInset = halfTopInset ? (PDFReaderLayout.annotationsCellSeparatorHeight / 2) : PDFReaderLayout.annotationsCellSeparatorHeight
        self.topInsetConstraint.constant = topInset - topFontOffset
    }
}
