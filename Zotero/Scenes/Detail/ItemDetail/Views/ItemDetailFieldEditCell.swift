//
//  ItemDetailFieldEditCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class ItemDetailFieldEditCell: RxTableViewCell {
    @IBOutlet private weak var titleWidth: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var valueTextField: UITextField!
    @IBOutlet private weak var topConstraint: NSLayoutConstraint!
    @IBOutlet private weak var bottomConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint?

    var textObservable: Observable<String> {
        return self.valueTextField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.valueTextField.text ?? "") })
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        let valueFont = UIFont.preferredFont(forTextStyle: .body)
        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
        self.valueTextField.font = valueFont

        self.topConstraint.constant = valueFont.capHeight - valueFont.ascender
        self.bottomConstraint.constant = valueFont.descender

        self.contentView.clipsToBounds = true
    }

    func setup(with field: ItemDetailState.Field, titleWidth: CGFloat) {
        let value = field.additionalInfo?[.formattedEditDate] ?? field.value

        self.titleLabel.text = field.name
        self.titleWidth.constant = titleWidth
        self.valueTextField.text = value

        let height = ceil(self.valueTextField.font!.capHeight + self.layoutMargins.top + self.layoutMargins.bottom)

        if let constraint = self.heightConstraint {
            constraint.constant = height
        } else {
            self.heightConstraint = self.contentView.heightAnchor.constraint(equalToConstant: height)
            self.heightConstraint?.priority = UILayoutPriority(rawValue: 999)
            self.heightConstraint?.isActive = true
        }
    }
}
