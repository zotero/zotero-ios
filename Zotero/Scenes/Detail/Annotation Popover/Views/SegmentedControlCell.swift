//
//  SegmentedControlCell.swift
//  Zotero
//
//  Created by Michal Rentka on 14.01.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class SegmentedControlCell: UITableViewCell {
    private weak var segmentedControl: UISegmentedControl?

    private var selectionChanged: ((Int) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
        selectionStyle = .none

        func setup() {
            let segmentedControl = UISegmentedControl()
            segmentedControl.addAction(UIAction(handler: { [weak self] _ in
                self?.selectionChanged?(self?.segmentedControl?.selectedSegmentIndex ?? 0)
            }), for: .valueChanged)
            segmentedControl.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(segmentedControl)
            self.segmentedControl = segmentedControl

            NSLayoutConstraint.activate([
                segmentedControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                contentView.bottomAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
                segmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
                contentView.trailingAnchor.constraint(equalTo: segmentedControl.trailingAnchor, constant: 15)
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        selectionChanged = nil
    }

    func setup(selected: Int, segments: [String], selectionChanged: @escaping (Int) -> Void) {
        self.selectionChanged = selectionChanged
        segmentedControl?.removeAllSegments()
        for (idx, segment) in segments.enumerated() {
            segmentedControl?.insertSegment(withTitle: segment, at: idx, animated: false)
        }
        segmentedControl?.selectedSegmentIndex = selected < segments.count ? selected : 0
    }
}
