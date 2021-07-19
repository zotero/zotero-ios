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
    private let menuItems: [UIMenuItem]?
    private let placeholderLayer: CATextLayer
    private let placeholder: String

    private var observer: AnyObserver<String>?
    var textObservable: Observable<String> {
        return Observable.create { observer -> Disposable in
            self.observer = observer
            return Disposables.create()
        }
    }

    init(placeholder: String, menuItems: [UIMenuItem]?, textView: UITextView) {
        self.menuItems = menuItems
        self.placeholder = placeholder
        self.placeholderLayer = CATextLayer()

        super.init()

        self.setup(placeholder: placeholder, textView: textView)
    }

    func set(text: String, to textView: UITextView) {
        self.placeholderLayer.isHidden = !text.isEmpty
        textView.text = text
    }

    func set(text: NSAttributedString, to textView: UITextView) {
        self.placeholderLayer.isHidden = !text.string.isEmpty
        textView.attributedText = text
    }

    func layoutPlaceholder(in textView: UITextView) {
        self.placeholderLayer.frame = textView.bounds
    }

    private func setup(placeholder: String, textView: UITextView) {
        self.placeholderLayer.string = placeholder
        self.placeholderLayer.font = textView.font
        self.placeholderLayer.fontSize = textView.font?.pointSize ?? 0
        self.placeholderLayer.foregroundColor = UIColor.placeholderText.cgColor
        self.placeholderLayer.contentsScale = UIScreen.main.scale

        textView.layer.addSublayer(self.placeholderLayer)

        self.layoutPlaceholder(in: textView)
    }
}

extension PlaceholderTextViewDelegate: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if let menuItems = self.menuItems {
            UIMenuController.shared.menuItems = menuItems
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        self.placeholderLayer.isHidden = !textView.text.isEmpty
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if textView.text.isEmpty && !text.isEmpty {
            self.placeholderLayer.isHidden = true
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        self.observer?.on(.next(textView.text))
    }
}
