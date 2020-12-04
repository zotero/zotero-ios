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

        let delegate = GrowingTextViewCellDelegate(label: self.label, placeholder: nil, menuItems: nil)
        self.textViewDelegate = delegate

        self.textView.textContainerInset = UIEdgeInsets()
        self.textView.textContainer.lineFragmentPadding = 0
        self.textView.delegate = delegate
        self.textView.font = AnnotationPopoverLayout.annotationLayout.font

        self.label.font = AnnotationPopoverLayout.annotationLayout.font
    }

    func setup(with text: String, color: String) {
        self.lineView.backgroundColor = UIColor(hex: color)
        self.label.text = text
        self.textView.text = text
    }
}
