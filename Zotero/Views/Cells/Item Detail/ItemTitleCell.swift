//
//  ItemTitleCell.swift
//  Zotero
//
//  Created by Michal Rentka on 20/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa

class ItemTitleCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleField: UITextField!
    @IBOutlet private weak var typeLabel: UILabel!

    var textObservable: ControlProperty<String> {
        return self.titleField.rx.text.orEmpty
    }

    func setup(with title: String, type: String, editing: Bool) {
        self.typeLabel.text = type
        if editing {
            self.titleField.text = title
        } else {
            self.titleLabel?.text = title
        }

        self.titleLabel.isHidden = editing
        self.titleField.isHidden = !editing
    }
}
