//
//  TextFieldCell.swift
//  Zotero
//
//  Created by Michal Rentka on 01.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

class TextFieldCell: RxTableViewCell {
    @IBOutlet private weak var textField: UITextField!

    var textObservable: Observable<String> {
        return self.textField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.textField.text ?? "") })
    }

    override func becomeFirstResponder() -> Bool {
        self.textField.becomeFirstResponder()
    }

    func setup(with text: String) {
        self.textField.text = text
    }
}
