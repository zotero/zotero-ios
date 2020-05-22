//
//  ItemDetailAbstractCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa

class ItemDetailAbstractCell: RxTableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var contentLabel: UILabel!
    @IBOutlet private weak var contentTextView: UITextView!

    var textObservable: ControlProperty<String> {
        return self.contentTextView.rx.text.orEmpty
    }

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
