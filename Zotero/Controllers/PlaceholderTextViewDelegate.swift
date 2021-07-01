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
    private let placeholder: String
    private let menuItems: [UIMenuItem]?

    private var observer: AnyObserver<String>?
    var textObservable: Observable<String> {
        return Observable.create { observer -> Disposable in
            self.observer = observer
            return Disposables.create()
        }
    }

    init(placeholder: String, menuItems: [UIMenuItem]?) {
        self.placeholder = placeholder
        self.menuItems = menuItems
        super.init()
    }

    func set(text: String, to textView: UITextView) {
        if text.isEmpty {
            self.setPlaceholder(to: textView)
        } else {
            textView.text = text
            textView.textColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
                return traitCollection.userInterfaceStyle == .dark ? .white : .darkText
            })
        }
    }

    private func setPlaceholder(to textView: UITextView) {
        textView.text = self.placeholder
        textView.textColor = .placeholderText
    }
}

extension PlaceholderTextViewDelegate: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if let menuItems = self.menuItems {
            UIMenuController.shared.menuItems = menuItems
        }
        if textView.text == self.placeholder {
            DispatchQueue.main.async {
                textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.beginningOfDocument)
            }
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            self.setPlaceholder(to: textView)
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if textView.text == self.placeholder {
            textView.text = ""
            textView.textColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
                return traitCollection.userInterfaceStyle == .dark ? .white : .darkText
            })
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        self.observer?.on(.next(textView.text))
    }
}
