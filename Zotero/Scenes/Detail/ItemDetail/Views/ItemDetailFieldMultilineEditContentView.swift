//
//  ItemDetailFieldMultilineEditContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 04.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemDetailFieldMultilineEditContentView: UIView {
    @IBOutlet private weak var titleWidth: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var valueTextView: UITextView!
    @IBOutlet private weak var titleTopConstraint: NSLayoutConstraint!
    @IBOutlet private weak var textViewTopConstraint: NSLayoutConstraint!
    @IBOutlet private weak var bottomConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint?

    private static let textViewTapAreaOffset: CGFloat = 8

    private var observer: AnyObserver<String>?
    var textObservable: Observable<String> {
        return Observable.create { observer -> Disposable in
            self.observer = observer
            return Disposables.create()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        let valueFont = UIFont.preferredFont(forTextStyle: .body)

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
        self.valueTextView.font = valueFont

        self.titleTopConstraint.constant = valueFont.capHeight - valueFont.ascender
        self.textViewTopConstraint.constant = valueFont.capHeight - valueFont.ascender - ItemDetailFieldMultilineEditContentView.textViewTapAreaOffset
        self.bottomConstraint.constant = valueFont.descender - ItemDetailLayout.separatorHeight - ItemDetailFieldMultilineEditContentView.textViewTapAreaOffset

        self.valueTextView.delegate = self
        self.valueTextView.isScrollEnabled = false
        self.valueTextView.textContainerInset = UIEdgeInsets(top: ItemDetailFieldMultilineEditContentView.textViewTapAreaOffset, left: 0,
                                                             bottom: ItemDetailFieldMultilineEditContentView.textViewTapAreaOffset, right: 0)
        self.valueTextView.textContainer.lineFragmentPadding = 0

        self.clipsToBounds = true
    }

    func setup(with field: ItemDetailState.Field, titleWidth: CGFloat) {
        self.titleLabel.text = field.name
        self.titleWidth.constant = titleWidth
        self.valueTextView.text = field.value
    }
}

extension ItemDetailFieldMultilineEditContentView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        self.observer?.on(.next(textView.text))
    }
}
