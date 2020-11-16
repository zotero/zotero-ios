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
    private var textLabel: UILabel!
    private var button: UIButton!

    var tap: Observable<UIButton> {
        return self.button.rx.tap.flatMap({ Observable.just(self.button) })
    }

    init() {
        let label = UILabel()
        label.font = PDFReaderLayout.font
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white
        self.clipsToBounds = false

        self.addSubview(label)
        self.addSubview(button)

        let topFontOffset = PDFReaderLayout.font.ascender - PDFReaderLayout.font.xHeight

        NSLayoutConstraint.activate([
            // Horizontal
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            self.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: PDFReaderLayout.annotationsHorizontalInset),
            button.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            // Vertical
            label.topAnchor.constraint(equalTo: self.topAnchor, constant: -topFontOffset),
            label.lastBaselineAnchor.constraint(equalTo: self.bottomAnchor),
            button.topAnchor.constraint(equalTo: self.topAnchor),
            button.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.textLabel = label
        self.button = button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(with attributedString: NSAttributedString) {
        self.textLabel.attributedText = attributedString
    }
}
