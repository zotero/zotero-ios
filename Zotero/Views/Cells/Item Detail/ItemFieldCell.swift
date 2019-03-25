//
//  ItemFieldCell.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa

class ItemFieldCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var valueLabel: UILabel!
    @IBOutlet private weak var valueField: UITextField!

    var textObservable: ControlProperty<String> {
        return self.valueField.rx.text.orEmpty
    }

    func setup(with title: String, value: String, editing: Bool) {
        self.valueLabel.isHidden = editing
        self.valueField.isHidden = !editing

        self.titleLabel.text = title
        if editing {
            self.valueField.text = value
        } else {
            self.valueLabel.text = value
        }
    }
}
