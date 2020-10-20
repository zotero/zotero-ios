//
//  ItemDetailTitleCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class ItemDetailTitleCell: RxTableViewCell {
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var textField: UITextField!
    @IBOutlet private weak var separatorLeft: NSLayoutConstraint!

    var textObservable: Observable<String> {
        return self.textField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.textField.text ?? "") })
    }

    func setup(with title: String, isEditing: Bool, placeholder: String? = nil) {
        self.separatorLeft.constant = self.separatorInset.left
        if isEditing {
            self.textField.text = title
            self.textField.placeholder = placeholder
        } else {
            self.label.text = title
            if title.isEmpty, let placeholder = placeholder {
                self.label.text = placeholder
            }
        }
        self.textField.isHidden = !isEditing
        self.label.isHidden = isEditing
    }
}
