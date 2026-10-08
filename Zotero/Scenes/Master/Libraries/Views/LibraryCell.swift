//
//  LibraryCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class LibraryCell: UICollectionViewListCell {
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

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        if #available(iOS 26.0, *) {
            if traitCollection.splitViewControllerLayoutEnvironment == .expanded {
                return super.preferredLayoutAttributesFitting(layoutAttributes)
            } else {
                layoutAttributes.size.height = 52
            }
        } else {
            layoutAttributes.size.height = 44
        }
        return layoutAttributes
    }
    
    func setup(with name: String, libraryState: LibraryState) {
        var configuration = defaultContentConfiguration()
        configuration.image = libraryState.image.withRenderingMode(.alwaysTemplate)
        configuration.imageProperties.tintColor = Asset.Colors.zoteroBlue.color
        configuration.imageProperties.reservedLayoutSize = CGSize(width: 28, height: 28)
        configuration.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        configuration.text = name
        configuration.textProperties.font = .systemFont(ofSize: 17)
        configuration.textProperties.numberOfLines = 1
        if #available(iOS 26.0, *) {
            if traitCollection.splitViewControllerLayoutEnvironment != .expanded {
                configuration.imageToTextPadding = 12
                configuration.axesPreservingSuperviewLayoutMargins = []
                configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            }
        } else {
            configuration.imageToTextPadding = 16
            configuration.axesPreservingSuperviewLayoutMargins = []
            configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        }
        contentConfiguration = configuration
        accessibilityLabel = libraryState.accessibilityNamePrefix + name
    }
}
