//
//  CapHeightLabel.swift
//  Zotero
//
//  Created by Michal Rentka on 06/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class CapHeightLabel: UILabel {
    override var alignmentRectInsets: UIEdgeInsets {
        return UIEdgeInsets(top: (self.font.ascender - self.font.capHeight), left: 0, bottom: 0, right: 0)
    }
}
