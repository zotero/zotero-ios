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
    @IBOutlet private weak var labelTop: NSLayoutConstraint!
    @IBOutlet private weak var label: UILabel!
    @IBOutlet private weak var textFieldTop: NSLayoutConstraint!
    @IBOutlet private weak var textField: UITextField!
    @IBOutlet private weak var separatorHeight: NSLayoutConstraint!

    private static let top: CGFloat = 44

    var textObservable: Observable<String> {
        return self.textField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.textField.text ?? "") })
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        let separatorHeight = 1 / UIScreen.main.scale
        self.separatorHeight.constant = separatorHeight

        let font = self.label.font!
        let top = ItemDetailTitleCell.top - (font.ascender - font.capHeight) - separatorHeight
        self.labelTop.constant = top
        self.textFieldTop.constant = top
    }

    func setup(with title: String, isEditing: Bool, placeholder: String? = nil) {
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
