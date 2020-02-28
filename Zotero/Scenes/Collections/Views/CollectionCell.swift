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
        self.contentView.subviews.last?.removeFromSuperview()
        self.setupView(with: collection)
        self.setupSeparatorInset(with: collection.level)
    }

    private func setupView(with collection: Collection) {
        guard let view = UIHostingController(rootView: CollectionRow(data: collection)).view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear

        self.contentView.addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor)
        ])
    }

    private func setupSeparatorInset(with level: Int) {
        let leftInset = CollectionRow.levelOffset + CollectionCell.imageWidth + (CGFloat(level) * CollectionRow.levelOffset)
        self.separatorInset = UIEdgeInsets(top: 0, left: leftInset, bottom: 0, right: 0)
    }
}
