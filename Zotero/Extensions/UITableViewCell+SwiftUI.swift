//
//  UITableViewCell+SwiftUI.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

extension UITableViewCell {
    func set<V: View>(view: V) {
        self.contentView.subviews.last?.removeFromSuperview()

        guard let view = UIHostingController(rootView: view).view else { return }

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
