//
//  PlaceholderTextViewDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 06.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class PlaceholderTextViewDelegate: NSObject {
    private let placeholderLayer: CATextLayer
    private let placeholder: String

    init(placeholder: String, textView: UITextView) {
        self.placeholder = placeholder
        placeholderLayer = CATextLayer()

        super.init()

        setup(placeholder: placeholder, textView: textView)

        func setup(placeholder: String, textView: UITextView) {
            placeholderLayer.string = placeholder
            placeholderLayer.font = textView.font
            placeholderLayer.fontSize = textView.font?.pointSize ?? 0
            placeholderLayer.foregroundColor = UIColor.placeholderText.cgColor
            placeholderLayer.contentsScale = UIScreen.main.scale

            textView.layer.addSublayer(placeholderLayer)

            layoutPlaceholder(in: textView)
        }
    }

    func set(text: String, to textView: UITextView) {
        placeholderLayer.isHidden = !text.isEmpty

        let oldRange = textView.selectedRange
        let isSameLengthText = text.count == textView.text.count

        textView.text = text
        textView.isAccessibilityElement = true

        if isSameLengthText {
            textView.selectedRange = oldRange
        }
    }

    func set(text: NSAttributedString, to textView: UITextView) {
        placeholderLayer.isHidden = !text.string.isEmpty

        let oldRange = textView.selectedRange
        let isSameLengthText = text.string.count == textView.attributedText.string.count

        textView.attributedText = text
        textView.isAccessibilityElement = true

        if isSameLengthText {
            textView.selectedRange = oldRange
        }
    }

    func set(placeholderColor: UIColor) {
        placeholderLayer.foregroundColor = placeholderColor.cgColor
    }

    func layoutPlaceholder(in textView: UITextView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderLayer.frame = textView.bounds
        CATransaction.commit()
    }
}

extension PlaceholderTextViewDelegate: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        placeholderLayer.foregroundColor = UIColor.placeholderText.cgColor
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        placeholderLayer.isHidden = !textView.text.isEmpty
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if textView.text.isEmpty && !text.isEmpty {
            placeholderLayer.isHidden = true
        }
        return true
    }
}
