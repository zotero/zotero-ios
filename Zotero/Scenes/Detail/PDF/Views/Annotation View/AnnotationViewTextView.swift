//
//  AnnotationViewTextView.swift
//  Zotero
//
//  Created by Michal Rentka on 20.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class AnnotationViewTextView: UIView {
    private(set) var textView: UITextView!

    private let layout: AnnotationViewLayout
    private let placeholder: String

    private var textViewDelegate: PlaceholderTextViewDelegate!
    var textObservable: Observable<(NSAttributedString, Bool)?> {
        return textViewDelegate.textObservable.flatMap { [weak self] _ -> Observable<(NSAttributedString, Bool)?> in
            guard let self else { return Observable.just(nil) }
            let height = textView.contentSize.height
            textView.sizeToFit()
            setupAccessibilityLabel()
            return Observable.just((textView.attributedText, (height != textView.contentSize.height)))
        }
    }
    var didBecomeActive: Observable<()> {
        return textViewDelegate.didBecomeActive
    }
    var accessibilityLabelPrefix: String?

    // MARK: - Lifecycle

    init(layout: AnnotationViewLayout, placeholder: String) {
        self.layout = layout
        self.placeholder = placeholder

        super.init(frame: CGRect())

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = layout.backgroundColor

        setupView()
        setupTextViewDelegate()
        textView.sizeToFit()

        func setupView() {
            let textView = AnnotationTextView(defaultFont: layout.font)
            textView.adjustsFontForContentSizeCategory = true
            textView.textContainerInset = UIEdgeInsets()
            textView.textContainer.lineFragmentPadding = 0
            textView.isScrollEnabled = false
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.font = layout.font

            addSubview(textView)

            let topFontOffset = layout.font.ascender - layout.font.xHeight
            let bottomFontOffset = layout.font.descender

            if let minHeight = layout.commentMinHeight {
                textView.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true
            }

            NSLayoutConstraint.activate([
                // Horizontal
                textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: layout.horizontalInset),
                trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: layout.horizontalInset),
                // Vertical
                textView.topAnchor.constraint(equalTo: topAnchor, constant: layout.verticalSpacerHeight - topFontOffset),
                bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: layout.verticalSpacerHeight + bottomFontOffset)
            ])

            self.textView = textView
        }

        func setupTextViewDelegate() {
            let bold = UIMenuItem(title: "Bold", action: #selector(UITextView.toggleBoldface(_:)))
            let italics = UIMenuItem(title: "Italics", action: #selector(UITextView.toggleItalics(_:)))
            let superscript = UIMenuItem(title: "Superscript", action: #selector(AnnotationTextView.toggleSuperscript))
            let `subscript` = UIMenuItem(title: "Subscript", action: #selector(AnnotationTextView.toggleSubscript))
            let items = [bold, italics, superscript, `subscript`]
            let delegate = PlaceholderTextViewDelegate(placeholder: placeholder, menuItems: items, textView: textView)
            textView.delegate = delegate
            textViewDelegate = delegate
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textViewDelegate.layoutPlaceholder(in: textView)
    }

    // MARK: - Actions

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textView.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        return textView.resignFirstResponder()
    }

    func set(placeholderColor: UIColor) {
        textViewDelegate.set(placeholderColor: placeholderColor)
    }

    // MARK: - Setups

    func setup(text: NSAttributedString?) {
        setupAccessibilityLabel()
        textView.isAccessibilityElement = true

        if let text {
            textViewDelegate.set(text: text, to: textView)
        } else {
            textViewDelegate.set(text: "", to: textView)
        }
    }

    private func setupAccessibilityLabel() {
        if textView.attributedText.string.isEmpty {
            accessibilityLabel = placeholder
            return
        }

        var label = textView.attributedText.string
        if let prefix = accessibilityLabelPrefix {
            label = prefix + label
        }
        accessibilityLabel = label
    }
}
