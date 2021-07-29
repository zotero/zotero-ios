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

final class AnnotationViewHighlightContent: UIView {
    private weak var lineView: UIView!
    private weak var textLabel: UILabel!
//    private weak var button: UIButton!
    private weak var bottomInsetConstraint: NSLayoutConstraint!

    private let layout: AnnotationViewLayout

//    var tap: Observable<UIButton> {
//        return self.button.rx.tap.flatMap({ Observable.just(self.button) })
//    }

    init(layout: AnnotationViewLayout) {
        self.layout = layout

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = layout.backgroundColor
        self.setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(with color: UIColor, text: String, bottomInset: CGFloat, accessibilityType: AnnotationView.AccessibilityType) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = self.layout.lineHeight
        paragraphStyle.maximumLineHeight = self.layout.lineHeight
        let attributedString = NSAttributedString(string: text, attributes: [.paragraphStyle: paragraphStyle,
                                                                             .font: self.layout.font,
                                                                             .foregroundColor: Asset.Colors.annotationText.color])

        self.lineView.backgroundColor = color
        self.textLabel.attributedText = attributedString
        self.bottomInsetConstraint.constant = bottomInset

//        switch accessibilityType {
//        case .cell:
//            self.textLabel.isAccessibilityElement = false
//        case .view:
//            self.textLabel.accessibilityLabel = attributedString.string
//        }
    }

    private func setupView() {
        let lineView = UIView()
        lineView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)

//        let button = UIButton()
//        button.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(lineView)
        self.addSubview(label)
//        self.addSubview(button)

        let bottomInset = self.bottomAnchor.constraint(equalTo: lineView.bottomAnchor, constant: self.layout.highlightLineVerticalInsets)

        NSLayoutConstraint.activate([
            // Horizontal
            lineView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: self.layout.horizontalInset),
            label.leadingAnchor.constraint(equalTo: lineView.trailingAnchor, constant: self.layout.highlightContentLeadingOffset),
            self.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: self.layout.horizontalInset),
//            button.leadingAnchor.constraint(equalTo: self.leadingAnchor),
//            button.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            // Size
            lineView.heightAnchor.constraint(equalTo: label.heightAnchor),
            lineView.widthAnchor.constraint(equalToConstant: self.layout.highlightLineWidth),
            // Vertical
            lineView.topAnchor.constraint(equalTo: label.topAnchor),
            lineView.bottomAnchor.constraint(equalTo: label.bottomAnchor),
            lineView.topAnchor.constraint(equalTo: self.topAnchor, constant: self.layout.highlightLineVerticalInsets),
            bottomInset,
//            button.topAnchor.constraint(equalTo: self.topAnchor),
//            button.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.lineView = lineView
        self.textLabel = label
//        self.button = button
        self.bottomInsetConstraint = bottomInset
    }
}
