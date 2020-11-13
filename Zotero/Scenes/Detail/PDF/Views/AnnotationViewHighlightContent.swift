//
//  AnnotationViewHighlightContent.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa

class AnnotationViewHighlightContent: UIView {
    private var lineView: UIView!
    private var textLabel: UILabel!
    private var button: UIButton!

    var tap: ControlEvent<Void> {
        return self.button.rx.tap
    }

    init() {
        let lineView = UIView()
        lineView.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.font = PDFReaderLayout.font
        label.textColor = Asset.Colors.annotationText.color
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white

        self.addSubview(lineView)
        self.addSubview(label)
        self.addSubview(button)

        let topFontOffset = PDFReaderLayout.font.ascender - PDFReaderLayout.font.xHeight

        NSLayoutConstraint.activate([
            // Horizontal
            lineView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: PDFReaderLayout.horizontalInset),
            label.leadingAnchor.constraint(equalTo: lineView.trailingAnchor, constant: PDFReaderLayout.annotationHighlightContentLeadingOffset),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: PDFReaderLayout.horizontalInset),
            button.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            // Height
            lineView.heightAnchor.constraint(equalTo: label.heightAnchor),
            // Vertical
            lineView.topAnchor.constraint(equalTo: label.topAnchor),
            lineView.bottomAnchor.constraint(equalTo: label.bottomAnchor),
            label.topAnchor.constraint(equalTo: self.topAnchor, constant: -topFontOffset),
            label.lastBaselineAnchor.constraint(equalTo: self.bottomAnchor),
            button.topAnchor.constraint(equalTo: self.topAnchor),
            button.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.lineView = lineView
        self.textLabel = label
        self.button = button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(with color: UIColor, text: String) {
        self.lineView.backgroundColor = color

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = PDFReaderLayout.annotationLineHeight
        paragraphStyle.maximumLineHeight = PDFReaderLayout.annotationLineHeight
        let attributedString = NSAttributedString(string: text, attributes: [.paragraphStyle: paragraphStyle])
        self.textLabel.attributedText = attributedString
    }
}
