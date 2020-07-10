//
//  CheckboxButton.swift
//  Zotero
//
//  Created by Michal Rentka on 14/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class CheckboxButton: UIButton {
    var selectedBackgroundColor: UIColor = .clear {
        didSet {
            if self.isSelected {
                self.backgroundColor = self.selectedBackgroundColor
            }
        }
    }

    var deselectedBackgroundColor: UIColor = .clear {
        didSet {
            if !self.isSelected {
                self.backgroundColor = self.deselectedBackgroundColor
            }
        }
    }

    var selectedTintColor: UIColor = .black {
        didSet {
            if self.isSelected {
                self.tintColor = self.selectedTintColor
            }
        }
    }

    var deselectedTintColor: UIColor = Asset.Colors.zoteroBlue.color {
        didSet {
            if !self.isSelected {
                self.tintColor = self.deselectedTintColor
            }
        }
    }

    override var isSelected: Bool {
        didSet {
            if self.isSelected {
                self.backgroundColor = self.selectedBackgroundColor
                self.tintColor = self.selectedTintColor
            } else {
                self.backgroundColor = self.deselectedBackgroundColor
                self.tintColor = self.deselectedTintColor
            }
        }
    }
}
