//
//  ItemDetailCreatorEditingCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailCreatorEditingCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var splitContainer: UIStackView!
    @IBOutlet private weak var firstNameTextField: UITextField!
    @IBOutlet private weak var lastNameTextField: UITextField!
    @IBOutlet private weak var fullTextField: UITextField!
    @IBOutlet private weak var button: UIButton!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
    }

    func setup(with creator: ItemDetailStore.State.Creator) {
        self.titleLabel.text = creator.localizedType

        let isSplit = creator.namePresentation == .separate
        self.splitContainer.isHidden = !isSplit
        self.fullTextField.isHidden = isSplit
        self.firstNameTextField.text = creator.firstName
        self.lastNameTextField.text = creator.lastName
        self.fullTextField.text = creator.fullName

        let buttonTitle = isSplit ? "Merge name" : "Split name"
        self.button.setTitle(buttonTitle, for: .normal)
    }
}
