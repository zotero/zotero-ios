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

final class ItemDetailTitleCell: RxTableViewCell {
    @IBOutlet private weak var labelTop: NSLayoutConstraint!
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var textField: UITextField!
    @IBOutlet private weak var separatorHeight: NSLayoutConstraint!

    var textObservable: Observable<String> {
        return self.textField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.textField.text ?? "") })
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        self.separatorHeight.constant = ItemDetailLayout.separatorHeight
    }

    func setup(with title: String, isEditing: Bool, placeholder: String? = nil) {
        self.textField.isHidden = !isEditing
        self.label.isHidden = isEditing

        self.labelTop.constant = self.label.font.capHeight - self.label.font.ascender

        if isEditing {
            self.textField.text = title
            self.textField.placeholder = placeholder
        } else {
            if !title.isEmpty {
                self.label.text = title
            } else if let placeholder = placeholder {
                self.label.text = placeholder
            }
        }
    }
}
