//
//  ItemDetailFieldEditContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 04.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemDetailFieldEditContentView: UIView {
    @IBOutlet private weak var titleWidthConstraint: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var valueTextField: UITextField!
    @IBOutlet private weak var topConstraint: NSLayoutConstraint!
    @IBOutlet private weak var bottomConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint?

    var textObservable: Observable<String> {
        return valueTextField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.valueTextField.text ?? "") })
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        let valueFont = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
        valueTextField.font = valueFont

        topConstraint.constant = valueFont.capHeight - valueFont.ascender
        bottomConstraint.constant = valueFont.descender

        clipsToBounds = true
    }

    func setup(with field: ItemDetailState.Field, titleWidth: CGFloat) {
        let value = field.additionalInfo?[.formattedEditDate] ?? field.value

        titleLabel.text = field.name
        titleWidthConstraint.constant = titleWidth
        valueTextField.text = value

        let height = ceil(valueTextField.font!.capHeight + layoutMargins.top + layoutMargins.bottom)

        if let heightConstraint {
            heightConstraint.constant = height
        } else {
            let heightConstraint = heightAnchor.constraint(equalToConstant: height)
            heightConstraint.priority = UILayoutPriority(rawValue: 999)
            heightConstraint.isActive = true
            self.heightConstraint = heightConstraint
        }
    }
}
