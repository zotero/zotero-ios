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

    private let layout: AnnotationViewLayout

    var tap: Observable<UIButton> {
        return self.button.rx.tap.flatMap({ Observable.just(self.button) })
    }

    init(layout: AnnotationViewLayout) {
        self.layout = layout

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = .white
        self.setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(with attributedString: NSAttributedString?, halfTopInset: Bool) {
        self.textLabel.attributedText = attributedString

        let topFontOffset = self.layout.font.ascender - self.layout.font.xHeight
        let topInset = halfTopInset ? (self.layout.verticalSpacerHeight / 2) : self.layout.verticalSpacerHeight
        self.topInsetConstraint.constant = topInset - topFontOffset
    }

    private func setupView() {
        let label = UILabel()
        label.font = self.layout.font
        label.numberOfLines = 0
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton()
        button.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        button.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(label)
        self.addSubview(button)

        let topInset = label.topAnchor.constraint(equalTo: self.topAnchor, constant: 0)

        NSLayoutConstraint.activate([
            // Horizontal
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: self.layout.horizontalInset),
            self.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: self.layout.horizontalInset),
            button.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            // Vertical
            topInset,
            self.bottomAnchor.constraint(equalTo: label.lastBaselineAnchor, constant: self.layout.verticalSpacerHeight),
            button.topAnchor.constraint(equalTo: self.topAnchor),
            button.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.textLabel = label
        self.button = button
        self.topInsetConstraint = topInset
    }
}
