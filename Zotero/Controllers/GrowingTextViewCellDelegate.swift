//
//  GrowingTextViewCellDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class GrowingTextViewCellDelegate: NSObject {
    private unowned let label: UILabel
    private let placeholder: NSAttributedString?
    private let menuItems: [UIMenuItem]?

    private var observer: AnyObserver<(NSAttributedString, Bool)>?
    var textObservable: Observable<(NSAttributedString, Bool)> {
        return Observable.create { observer -> Disposable in
            self.observer = observer
            return Disposables.create()
        }
    }

    init(label: UILabel, placeholder: NSAttributedString?, menuItems: [UIMenuItem]?) {
        self.label = label
        self.placeholder = placeholder
        self.menuItems = menuItems
        super.init()
    }

    private func didChange(attributedText: NSAttributedString) {
        if attributedText.string.isEmpty {
            self.label.text = " "
        } else if let lastChar = attributedText.string.unicodeScalars.last, CharacterSet.newlines.contains(lastChar) {
            // If last line is an empty newline, the label doesn't grow appropriately and we get misaligned view. Add a whitespace to the last line so that the label grows.
            let mutableString = NSMutableAttributedString(attributedString: attributedText)
            mutableString.append(NSAttributedString(string: " "))
            self.label.attributedText = mutableString
        } else {
            self.label.attributedText = attributedText
        }
    }
}

extension GrowingTextViewCellDelegate: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if let menuItems = self.menuItems {
            UIMenuController.shared.menuItems = menuItems
        }
        if textView.text == self.placeholder?.string {
            textView.selectedRange = NSRange(location: 0, length: 0)
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if let placeholder = self.placeholder, textView.text.isEmpty {
            textView.attributedText = placeholder
            textView.textColor = .placeholderText
            self.label.attributedText = placeholder
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if textView.text == self.placeholder?.string {
            textView.text = ""
            textView.textColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
                return traitCollection.userInterfaceStyle == .dark ? .white : .darkText
            })
            self.label.text = " "
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        let height = self.label.frame.height

        self.didChange(attributedText: textView.attributedText)

        self.label.layoutIfNeeded()
        let needsReload = height != self.label.frame.height
        self.observer?.on(.next((textView.attributedText, needsReload)))
    }
}
