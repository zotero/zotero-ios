//
//  CollectionRowView.swift
//  ZShare
//
//  Created by Michal Rentka on 09.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class CollectionRowView: UIView {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var checkmark: UIImageView!

    var tapAction: (() -> Void)?

    @IBAction private func tap() {
        self.tapAction?()
    }

    func change(selected: Bool) {
        self.checkmark.isHidden = !selected
    }

    func setup(with title: String, isSelected: Bool) {
        self.titleLabel.text = title
        self.checkmark.isHidden = !isSelected
    }
}
