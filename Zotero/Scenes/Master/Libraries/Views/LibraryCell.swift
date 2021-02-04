//
//  LibraryCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class LibraryCell: UITableViewCell {
    enum LibraryState {
        case normal, locked, archived
    }

    @IBOutlet private weak var iconLeftConstraint: NSLayoutConstraint!
    @IBOutlet private weak var iconView: UIImageView!
    @IBOutlet private weak var iconToLabelConstraint: NSLayoutConstraint!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var titleRightConstraint: NSLayoutConstraint!

    private static let horizontalPadding: CGFloat = 16

    func setup(with name: String, libraryState: LibraryState) {
        self.iconView.image = self.image(for: libraryState).withRenderingMode(.alwaysTemplate)
        self.titleLabel.text = name

        let hasExtraPadding = libraryState != .normal
        self.iconLeftConstraint.constant = LibraryCell.horizontalPadding - (hasExtraPadding ? 2 : 0)
        self.iconToLabelConstraint.constant = LibraryCell.horizontalPadding - (hasExtraPadding ? 2 : 0)
        self.titleRightConstraint.constant = LibraryCell.horizontalPadding
    }

    private func image(for state: LibraryState) -> UIImage {
        switch state {
        case .normal: return Asset.Images.Cells.library.image
        case .locked: return Asset.Images.Cells.libraryReadonly.image
        case .archived: return Asset.Images.Cells.libraryArchived.image
        }
    }
}
