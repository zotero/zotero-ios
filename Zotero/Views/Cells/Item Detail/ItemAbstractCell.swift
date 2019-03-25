//
//  ItemAbstractCell.swift
//  Zotero
//
//  Created by Michal Rentka on 20/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa

class ItemAbstractCell: UITableViewCell {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var contentLabel: UILabel!
    @IBOutlet private weak var contentTextView: UITextView!

    var textObservable: ControlProperty<String> {
        return self.contentTextView.rx.text.orEmpty
    }

    func setup(with abstract: String, editing: Bool) {
        if editing {
            self.contentTextView.text = abstract
        } else {
            self.contentLabel.text = abstract
        }

        self.contentLabel.isHidden = editing
        self.contentTextView.isHidden = !editing
    }
}
