//
//  HighlightEditCell.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class HighlightEditCell: UITableViewCell {
    @IBOutlet private weak var lineView: UIView!
    @IBOutlet private weak var textView: UITextView!

    private var observer: AnyObserver<(String, Bool)>?
    var textObservable: Observable<(String, Bool)> {
        return Observable.create { observer -> Disposable in
            self.observer = observer
            return Disposables.create()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.textView.textContainerInset = UIEdgeInsets()
        self.textView.textContainer.lineFragmentPadding = 0
        self.textView.delegate = self
        self.textView.isScrollEnabled = false
    }

    func setup(with text: String, color: String) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
        paragraphStyle.maximumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
        let attributedText = NSAttributedString(string: text, attributes: [.font: AnnotationPopoverLayout.annotationLayout.font,
                                                                           .foregroundColor: Asset.Colors.annotationText.color,
                                                                           .paragraphStyle: paragraphStyle])

        self.lineView.backgroundColor = UIColor(hex: color)
        self.textView.attributedText = attributedText
    }
}

extension HighlightEditCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let height = textView.contentSize.height
        textView.sizeToFit()
        self.observer?.on(.next((textView.text, (height != textView.contentSize.height))))
    }
}
