//
//  ItemDetailTagCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ItemDetailTagCell: UICollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let tag: Tag
        let isEditing: Bool
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

        fileprivate weak var contentView: ItemDetailTagContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailTagContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailTagContentView else { return }

            self.add(contentView: view)
            view.layoutMargins = configuration.layoutMargins
            self.contentView = view
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            self.contentView.setup(tag: configuration.tag, isEditing: configuration.isEditing)
        }
    }
}
