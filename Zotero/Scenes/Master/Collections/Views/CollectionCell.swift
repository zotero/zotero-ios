//
//  CollectionCell.swift
//  Zotero
//
//  Created by Michal Rentka on 14/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

class CollectionCell: UITableViewCell {
    private static let imageWidth: CGFloat = 36

    func set(collection: Collection) {
        self.set(view: CollectionRow(data: collection))
        self.setupSeparatorInset(with: collection.level)
    }

    private func setupSeparatorInset(with level: Int) {
        let leftInset = CollectionRow.levelOffset + CollectionCell.imageWidth + (CGFloat(level) * CollectionRow.levelOffset)
        self.separatorInset = UIEdgeInsets(top: 0, left: leftInset, bottom: 0, right: 0)
    }
}
