//
//  ReaderSettingsSegmentedCellContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 03.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class ReaderSettingsSegmentedCellContentView: UIView {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var segmentedControl: UISegmentedControl!

    func setup(title: String, actions: [UIAction], selectedIndex: Int) {
        self.titleLabel.text = title
        self.segmentedControl.removeAllSegments()
        for (idx, action) in actions.enumerated() {
            self.segmentedControl.insertSegment(action: action, at: idx, animated: false)
        }
        self.segmentedControl.selectedSegmentIndex = selectedIndex
    }
}
