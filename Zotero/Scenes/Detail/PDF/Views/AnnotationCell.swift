//
//  AnnotationCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationCell: UITableViewCell {
    private var key: String = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    func setup(with annotation: Annotation, preview: UIImage?, selected: Bool) {
        self.key = annotation.key
        self.set(view: AnnotationRow(annotation: annotation, preview: preview, selected: selected))
    }

    private func setup() {
        self.selectionStyle = .none
        self.contentView.backgroundColor = UIColor(hex: "#d2d8e2")
    }
}
