//
//  HighlightEditCell.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class HighlightEditCell: UITableViewCell {
    @IBOutlet private weak var lineView: UIView!
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var textView: UITextView!

    private var textViewDelegate: GrowingTextViewCellDelegate!
    var textObservable: Observable<(NSAttributedString, Bool)> {
        return self.textViewDelegate.textObservable
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.textViewDelegate = GrowingTextViewCellDelegate(label: self.label, placeholder: nil, menuItems: nil)

        self.textView.textContainerInset = UIEdgeInsets()
        self.textView.textContainer.lineFragmentPadding = 0
        self.textView.delegate = self.textViewDelegate
    }

    func setup(with text: String, color: String) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
        paragraphStyle.maximumLineHeight = AnnotationPopoverLayout.annotationLayout.lineHeight
        let attributedText = NSAttributedString(string: text, attributes: [.font: AnnotationPopoverLayout.annotationLayout.font,
                                                                           .foregroundColor: Asset.Colors.annotationText.color,
                                                                           .paragraphStyle: paragraphStyle])

        self.lineView.backgroundColor = UIColor(hex: color)
        self.label.attributedText = attributedText
        self.textView.attributedText = attributedText
    }
}
