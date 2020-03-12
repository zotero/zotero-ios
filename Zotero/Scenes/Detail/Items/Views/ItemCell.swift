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
        self.contentView.subviews.last?.removeFromSuperview()
        self.setupView(with: item)
    }

    private func setupView(with item: RItem) {
        guard let view = UIHostingController(rootView: ItemRow(item: item)).view else { return }
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
}
