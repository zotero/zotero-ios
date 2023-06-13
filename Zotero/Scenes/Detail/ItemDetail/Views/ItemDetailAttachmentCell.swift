//
//  ItemDetailAttachmentCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ItemDetailAttachmentCell: UICollectionViewListCell {
    enum Kind: Equatable, Hashable {
        case `default`
        case inProgress(CGFloat)
        case failed(Error)
        case disabled

        static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case (.default, .default), (.disabled, .disabled):
                return true

            case (.inProgress(let lProgress), .inProgress(let rProgress)) where lProgress == rProgress:
                return true

            case (.failed(let lError), .failed(let rError)) where lError.localizedDescription == rError.localizedDescription:
                return true

            default:
                return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .default:
                hasher.combine(1)

            case .disabled:
                hasher.combine(2)

            case .inProgress(let progress):
                hasher.combine(3)
                hasher.combine(progress)

            case .failed(let error):
                hasher.combine(4)
                hasher.combine(error.localizedDescription.hash)
            }
        }
    }

    struct ContentConfiguration: UIContentConfiguration {
        let attachment: Attachment
        let type: Kind
        let layoutMargins: UIEdgeInsets

        func makeContentView() -> UIView & UIContentView {
            return ContentView(configuration: self)
        }

        func updated(for state: UIConfigurationState) -> ContentConfiguration {
            return self
        }
    }

    final class ContentView: UIView, UIContentView {
        var configuration: UIContentConfiguration {
            didSet {
                guard let configuration = self.configuration as? ContentConfiguration else { return }
                self.apply(configuration: configuration)
            }
        }

        fileprivate weak var contentView: ItemDetailAttachmentContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailAttachmentContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailAttachmentContentView else { return }

            self.add(contentView: view)
            self.contentView = view
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            self.contentView.layoutMargins = configuration.layoutMargins
            self.contentView.setup(with: configuration.attachment, type: configuration.type)
        }

        fileprivate func set(backgroundColor: UIColor) {
            self.contentView.fileView.set(backgroundColor: backgroundColor)
        }
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        let color = state.isHighlighted || state.isSelected ? Asset.Colors.cellHighlighted.color : .systemBackground

        self.contentView.backgroundColor = color
        (self.contentView as? ContentView)?.set(backgroundColor: color)

        super.updateConfiguration(using: state)
    }
}
