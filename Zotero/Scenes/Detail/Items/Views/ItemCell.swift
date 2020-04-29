//
//  ItemCell.swift
//  Zotero
//
//  Created by Michal Rentka on 17/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

class ItemCell: UITableViewCell {

    func set(item: RItem) {
        self.set(view: ItemRow(item: item))
    }
}
