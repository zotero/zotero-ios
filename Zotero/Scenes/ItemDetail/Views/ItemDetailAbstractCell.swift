//
//  ItemDetailAbstractCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailAbstractCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var contentLabel: UILabel!
    @IBOutlet private weak var contentTextView: UITextView!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .regular)
    }

    func setup(with abstract: String, isEditing: Bool) {
        self.contentLabel.text = abstract
        self.contentTextView.text = abstract
        self.contentLabel.isHidden = isEditing
        self.contentTextView.isHidden = !isEditing
    }
}
