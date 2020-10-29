//
//  ItemDetailFieldEditCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemDetailFieldEditCell: RxTableViewCell {
    @IBOutlet private weak var titleWidth: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var valueTop: NSLayoutConstraint!
    @IBOutlet private weak var valueTextField: UITextField!
    // UITextField has problem with aligning to baseline, so there's a hidden label used for autolayout
    @IBOutlet private weak var hiddenLabel: UILabel!

    var textObservable: Observable<String> {
        return self.valueTextField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.valueTextField.text ?? "") })
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
        self.valueTextField.font = .preferredFont(forTextStyle: .body)
        self.hiddenLabel.font = self.valueTextField.font
    }

    func setup(with field: ItemDetailState.Field, titleWidth: CGFloat) {
        self.titleLabel.text = field.name
        self.hiddenLabel.text = field.value
        self.titleWidth.constant = titleWidth

        self.valueTextField.text = field.value

        self.valueTop.constant = self.valueTextField.font!.capHeight - self.valueTextField.font!.ascender
    }
}
