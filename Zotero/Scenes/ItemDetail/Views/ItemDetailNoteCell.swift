//
//  ItemDetailNoteCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ItemDetailNoteCell: UITableViewCell {
    @IBOutlet private weak var label: UILabel!

    func setup(with note: Note) {
        self.label.text = note.title
    }
}
