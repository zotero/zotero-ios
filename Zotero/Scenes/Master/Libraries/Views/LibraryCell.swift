//
//  LibraryCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class LibraryCell: UITableViewCell {
    @IBOutlet private weak var iconLeftConstraint: NSLayoutConstraint!
    @IBOutlet private weak var iconView: UIImageView!
    @IBOutlet private weak var iconToLabelConstraint: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleRightConstraint: NSLayoutConstraint!

    private static let horizontalPadding: CGFloat = 16

    func setup(with name: String, isReadOnly: Bool) {
        let image = isReadOnly ? Asset.Images.Cells.libraryReadonly.image :
                                 Asset.Images.Cells.library.image
        self.iconView.image = image.withRenderingMode(.alwaysTemplate)
        self.titleLabel.text = name

        self.iconLeftConstraint.constant = LibraryCell.horizontalPadding - (isReadOnly ? 2 : 0)
        self.iconToLabelConstraint.constant = LibraryCell.horizontalPadding - (isReadOnly ? 2 : 0)
        self.titleRightConstraint.constant = LibraryCell.horizontalPadding
    }
}
