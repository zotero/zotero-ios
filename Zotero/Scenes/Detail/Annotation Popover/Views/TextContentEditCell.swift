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
    let textAndHeightReloadNeededObservable: PublishSubject<(String, Bool)>

    private var lineView: UIView?
    private var textView: UITextView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        textAndHeightReloadNeededObservable = PublishSubject()
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
        selectionStyle = .none

        func setup() {
            let lineView = UIView()
            lineView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(lineView)
            self.lineView = lineView

            let textView = TextKit1TextView()
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

    func setup(with text: String, color: String) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
        paragraphStyle.maximumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
        let attributedText = NSAttributedString(
            string: text,
            attributes: [.font: AnnotationPopoverLayout.annotationLayout.font, .foregroundColor: Asset.Colors.annotationText.color, .paragraphStyle: paragraphStyle]
        )

        lineView?.backgroundColor = UIColor(hex: color)
        textView?.attributedText = attributedText
    }
}

extension TextContentEditCell: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let height = textView.contentSize.height
        textView.sizeToFit()
        textAndHeightReloadNeededObservable.onNext((textView.text, height != textView.contentSize.height))
    }
}
