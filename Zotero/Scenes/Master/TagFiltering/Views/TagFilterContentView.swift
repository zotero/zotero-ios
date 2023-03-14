//
//  TagFilterContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 13.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class TagFilterContentView: UIView {
    @IBOutlet private weak var textLabel: UILabel!

    func setup(with text: String, color: UIColor) {
        self.textLabel.text = text
        self.textLabel.backgroundColor = color
    }
}
