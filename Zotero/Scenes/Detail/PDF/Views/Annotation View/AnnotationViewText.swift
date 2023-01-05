//
//  AnnotationViewText.swift
//  Zotero
//
//  Created by Michal Rentka on 13.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import RxSwift
import RxCocoa

final class AnnotationViewText: UIView {
    private(set) weak var textLabel: UILabel!
    private(set) weak var button: UIButton!

    private let layout: AnnotationViewLayout

    var tap: Observable<UIButton> {
        return self.button.rx.tap.flatMap({ Observable.just(self.button) })
    }

    var isEnabled: Bool {
        get {
            return self.button.isEnabled
        }

        set {
            self.button.isEnabled = newValue
        }
    }

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

    func setup(with attributedString: NSAttributedString?) {
        self.textLabel.attributedText = attributedString
    }

    private func setupView() {
        let label = UILabel()
        label.font = self.layout.font
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton()
        button.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.font = self.layout.font

        self.addSubview(label)
        self.addSubview(button)

        let topFontInset = self.layout.verticalSpacerHeight - (self.layout.font.ascender - self.layout.font.xHeight)

        NSLayoutConstraint.activate([
            // Horizontal
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: self.layout.horizontalInset),
            self.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: self.layout.horizontalInset),
            button.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            // Vertical
            label.topAnchor.constraint(equalTo: self.topAnchor, constant: topFontInset),
            self.bottomAnchor.constraint(equalTo: label.lastBaselineAnchor, constant: self.layout.verticalSpacerHeight),
            button.topAnchor.constraint(equalTo: self.topAnchor, constant: topFontInset),
            self.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: self.layout.verticalSpacerHeight)
        ])

        self.textLabel = label
        self.button = button
    }
}

#endif
