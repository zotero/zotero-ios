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
    @IBOutlet private weak var button: UIButton!

    func setup(title: String, actions: [UIAction], selectedIndex: Int) {
        button.menu = UIMenu(children: actions)
        button.showsMenuAsPrimaryAction = true
        button.contentHorizontalAlignment = .fill

        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .label
        configuration.title = title
        configuration.titleAlignment = .leading
        configuration.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        configuration.imagePlacement = .trailing
        button.configuration = configuration

        titleLabel.text = title
        segmentedControl.removeAllSegments()
        for (idx, action) in actions.enumerated() {
            segmentedControl.insertSegment(action: action, at: idx, animated: false)
        }
        segmentedControl.selectedSegmentIndex = selectedIndex
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let isTruncated = isTextTruncated()
        button.isHidden = !isTruncated
        titleLabel.isHidden = isTruncated
        segmentedControl.isHidden = isTruncated

        func isTextTruncated() -> Bool {
            guard let text = titleLabel.text, let font = titleLabel.font else { return false }
            let size = (text as NSString).boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: titleLabel.bounds.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).size
            return size.width > titleLabel.bounds.width
        }
    }
}
