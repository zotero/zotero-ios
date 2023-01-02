//
//  AnnotationViewTextView.swift
//  Zotero
//
//  Created by Michal Rentka on 20.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import RxSwift

final class AnnotationViewTextView: UIView {
    private(set) weak var textView: UITextView!

    private let layout: AnnotationViewLayout
    private let placeholder: String

    private var textViewDelegate: PlaceholderTextViewDelegate!
    var textObservable: Observable<(NSAttributedString, Bool)> {
        return self.textViewDelegate.textObservable.flatMap { _ -> Observable<(NSAttributedString, Bool)> in
            let height = self.textView.contentSize.height
            self.textView.sizeToFit()
            self.setupAccessibilityLabel()
            return Observable.just((self.textView.attributedText, (height != self.textView.contentSize.height)))
        }
    }
    var didBecomeActive: Observable<()> {
        return self.textViewDelegate.didBecomeActive
    }
    var accessibilityLabelPrefix: String?

    // MARK: - Lifecycle

    init(layout: AnnotationViewLayout, placeholder: String) {
        self.layout = layout
        self.placeholder = placeholder

        super.init(frame: CGRect())

        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = layout.backgroundColor

        self.setupView()
        self.setupTextViewDelegate()
        self.textView.sizeToFit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.textViewDelegate.layoutPlaceholder(in: self.textView)
    }

    // MARK: - Actions

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return self.textView.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        return self.textView.resignFirstResponder()
    }

    func set(placeholderColor: UIColor) {
        self.textViewDelegate.set(placeholderColor: placeholderColor)
    }

    // MARK: - Setups

    func setup(text: NSAttributedString?) {
        self.setupAccessibilityLabel()
        self.textView.isAccessibilityElement = true

        if let text = text {
            self.textViewDelegate.set(text: text, to: self.textView)
        } else {
            self.textViewDelegate.set(text: "", to: self.textView)
        }
    }

    private func setupAccessibilityLabel() {
        if self.textView.attributedText.string.isEmpty {
            self.accessibilityLabel = self.placeholder
            return
        }

        var label = self.textView.attributedText.string
        if let prefix = self.accessibilityLabelPrefix {
            label = prefix + label
        }
        self.accessibilityLabel = label
    }

    private func setupView() {
        let textView = AnnotationTextView(defaultFont: self.layout.font)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets()
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = self.layout.font

        self.addSubview(textView)

        let topFontOffset = self.layout.font.ascender - self.layout.font.xHeight
        let bottomFontOffset = self.layout.font.descender

        if let minHeight = self.layout.commentMinHeight {
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true
        }

        NSLayoutConstraint.activate([
            // Horizontal
            textView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: self.layout.horizontalInset),
            self.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: self.layout.horizontalInset),
            // Vertical
            textView.topAnchor.constraint(equalTo: self.topAnchor, constant: self.layout.verticalSpacerHeight - topFontOffset),
            self.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: self.layout.verticalSpacerHeight + bottomFontOffset)
        ])

        self.textView = textView
    }

    private func setupTextViewDelegate() {
        let bold = UIMenuItem(title: "Bold", action: #selector(UITextView.toggleBoldface(_:)))
        let italics = UIMenuItem(title: "Italics", action: #selector(UITextView.toggleItalics(_:)))
        let superscript = UIMenuItem(title: "Superscript", action: #selector(AnnotationTextView.toggleSuperscript))
        let `subscript` = UIMenuItem(title: "Subscript", action: #selector(AnnotationTextView.toggleSubscript))
        let items = [bold, italics, superscript, `subscript`]
        let delegate = PlaceholderTextViewDelegate(placeholder: self.placeholder, menuItems: items, textView: self.textView)
        self.textView.delegate = delegate
        self.textViewDelegate = delegate
    }
}

fileprivate final class AnnotationTextView: UITextView {
    private static let allowedActions: [String] = ["cut:", "copy:", "paste:", "toggleBoldface:", "toggleItalics:", "toggleSuperscript", "toggleSubscript", "replace:"]

    private let defaultFont: UIFont

    init(defaultFont: UIFont) {
        self.defaultFont = defaultFont
        super.init(frame: CGRect(), textContainer: nil)
        self.font = defaultFont
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return AnnotationTextView.allowedActions.contains(action.description)
    }

    @objc func toggleSuperscript() {
        guard self.selectedRange.length > 0 else { return }
        self.perform(attributedStringAction: { StringAttribute.toggleSuperscript(in: $0, range: $1, defaultFont: self.defaultFont) })
    }

    @objc func toggleSubscript() {
        guard self.selectedRange.length > 0 else { return }
        self.perform(attributedStringAction: { StringAttribute.toggleSubscript(in: $0, range: $1, defaultFont: self.defaultFont) })
    }

    private func perform(attributedStringAction: (NSMutableAttributedString, NSRange) -> Void) {
        let range = self.selectedRange
        let string = NSMutableAttributedString(attributedString: self.attributedText)
        attributedStringAction(string, range)
        self.attributedText = string
        self.selectedRange = range
        self.delegate?.textViewDidChange?(self)
    }
}

#endif
