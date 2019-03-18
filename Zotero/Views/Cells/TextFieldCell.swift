//
//  TextFieldCell.swift
//  Zotero
//
//  Created by Michal Rentka on 18/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class TextFieldCell: UITableViewCell {
    // Outlets
    @IBOutlet private weak var textField: UITextField!
    // Variables
    private var changeAction: ((String) -> Void)?

    func focusTextField() {
        self.textField.becomeFirstResponder()
    }

    func setup(with text: String, placeholder: String, changed: @escaping (String) -> Void) {
        self.textField.text = text
        self.textField.placeholder = placeholder
        self.changeAction = changed
    }
}

extension TextFieldCell: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        let oldText = textField.text ?? ""
        let newText = (oldText as NSString).replacingCharacters(in: range, with: string)
        self.changeAction?(newText)
        return true
    }
}
