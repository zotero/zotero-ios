//
//  TextContentEditCell.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class TextContentEditCell: RxTableViewCell {
    let attributedTextAndHeightReloadNeededObservable: PublishSubject<(NSAttributedString, Bool)>

    private weak var lineView: UIView?
    private weak var textView: FormattedTextView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        attributedTextAndHeightReloadNeededObservable = PublishSubject()
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
        selectionStyle = .none

        func setup() {
            let lineView = UIView()
            lineView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(lineView)
            self.lineView = lineView

            let textView = FormattedTextView(defaultFont: AnnotationPopoverLayout.annotationLayout.font)
            textView.textContainerInset = UIEdgeInsets()
            textView.textContainer.lineFragmentPadding = 0
            textView.delegate = self
            textView.isScrollEnabled = false
            textView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(textView)
            self.textView = textView

            NSLayoutConstraint.activate([
                lineView.topAnchor.constraint(equalTo: textView.topAnchor),
                lineView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
                lineView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                lineView.widthAnchor.constraint(equalToConstant: 3),
                textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
                textView.leadingAnchor.constraint(equalTo: lineView.trailingAnchor, constant: 8),
                contentView.bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: 10),
                contentView.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 16)
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var caretRect: CGRect? {
        guard let textView, textView.isFirstResponder, let selectedPosition = textView.selectedTextRange?.start else { return nil }
        return textView.caretRect(for: selectedPosition)
    }

    func setup(with text: NSAttributedString, color: String) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
        paragraphStyle.maximumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
        let attributedText = NSMutableAttributedString(attributedString: text)
        attributedText.addAttributes([.foregroundColor: Asset.Colors.annotationText.color, .paragraphStyle: paragraphStyle], range: .init(location: 0, length: attributedText.length))

        lineView?.backgroundColor = UIColor(hex: color)
        textView?.attributedText = attributedText
    }
}

extension TextContentEditCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let height = textView.contentSize.height
        textView.sizeToFit()
        attributedTextAndHeightReloadNeededObservable.onNext((textView.attributedText, height != textView.contentSize.height))
    }
}
