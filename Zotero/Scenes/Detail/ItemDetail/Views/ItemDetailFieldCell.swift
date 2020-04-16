//
//  ItemDetailFieldCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class ItemDetailFieldCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleWidth: NSLayoutConstraint!
    @IBOutlet private weak var valueTextField: UITextField!
    @IBOutlet private weak var valueLabel: UILabel!

    var textObservable: ControlProperty<String> {
        return self.valueTextField.rx.text.orEmpty
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
        self.valueLabel.textColor = self.traitCollection.userInterfaceStyle == .light ? .black : .white
    }

    func setup(with field: ItemDetailState.Field, isEditing: Bool, titleWidth: CGFloat) {
        self.titleLabel.text = field.name
        self.valueTextField.text = field.value
        self.valueLabel.text = field.value
        self.valueLabel.isHidden = isEditing
        self.valueTextField.isHidden = !isEditing
        self.titleWidth.constant = titleWidth
    }

    func setup(with creator: ItemDetailState.Creator, titleWidth: CGFloat) {
        self.titleLabel.text = creator.localizedType
        self.valueLabel.text = creator.name
        self.valueLabel.isHidden = false
        self.valueTextField.isHidden = true
        self.titleWidth.constant = titleWidth
    }

    func setup(with date: String, title: String, titleWidth: CGFloat) {
        self.titleLabel.text = title
        self.valueLabel.text = date
        self.valueLabel.isHidden = false
        self.valueTextField.isHidden = true
        self.titleWidth.constant = titleWidth
    }
}
