//
//  ItemDetailFieldCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ItemDetailFieldCell: UICollectionViewListCell {
    enum CellType {
        case field(ItemDetailState.Field)
        case creator(ItemDetailState.Creator)
        case value(value: String, title: String)
    }

    struct ContentConfiguration: UIContentConfiguration {
        let type: CellType
        let titleWidth: CGFloat
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

        fileprivate weak var contentView: ItemDetailFieldContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailFieldContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailFieldContentView else { return }

            self.add(contentView: view)
            self.contentView = view
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            self.contentView.layoutMargins = configuration.layoutMargins

            switch configuration.type {
            case .creator(let creator):
                self.contentView.setup(with: creator, titleWidth: configuration.titleWidth)
            case .value(let value, let title):
                self.contentView.setup(with: value, title: title, titleWidth: configuration.titleWidth)
            case .field(let field):
                self.contentView.setup(with: field, titleWidth: configuration.titleWidth)
            }
        }
    }
}
