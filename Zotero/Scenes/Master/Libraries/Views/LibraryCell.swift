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

        var image: UIImage {
            switch self {
            case .normal:
                return Asset.Images.Cells.library.image

            case .locked:
                return Asset.Images.Cells.libraryReadonly.image

            case .archived:
                return Asset.Images.Cells.libraryArchived.image
            }
        }

        var accessibilityNamePrefix: String {
            switch self {
            case .normal:
                return ""

            case .locked:
                return "\(L10n.Accessibility.locked) "

            case .archived:
                return "\(L10n.Accessibility.archived) "
            }
        }
    }

    private weak var iconView: UIImageView!
    private weak var titleLabel: UILabel!

    static var titleLabelLeadingOffset: CGFloat {
        if #available(iOS 26.0.0, *) {
            return 56
        } else {
            return 60
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()

        func setup() {
            let iconView = UIImageView()
            iconView.tintColor = Asset.Colors.zoteroBlue.color
            iconView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(iconView)
            self.iconView = iconView

            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(titleLabel)
            self.titleLabel = titleLabel

            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
                iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
                titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.titleLabelLeadingOffset),
                titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                contentView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16)
            ])
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup(with name: String, libraryState: LibraryState) {
        iconView.image = libraryState.image.withRenderingMode(.alwaysTemplate)
        titleLabel.text = name
        titleLabel.accessibilityLabel = libraryState.accessibilityNamePrefix + name
    }
}
