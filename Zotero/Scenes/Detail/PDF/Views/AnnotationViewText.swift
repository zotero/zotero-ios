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

    var tap: ControlEvent<Void> {
        return self.button.rx.tap
    }

    init() {
        let label = UILabel()
        label.font = PDFReaderLayout.font
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white

        self.addSubview(label)
        self.addSubview(button)

        let topFontOffset = PDFReaderLayout.font.ascender - PDFReaderLayout.font.xHeight

        NSLayoutConstraint.activate([
            // Horizontal
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: PDFReaderLayout.horizontalInset),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: PDFReaderLayout.horizontalInset),
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
