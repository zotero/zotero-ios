//
//  ItemDetailAbstractCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ItemDetailAbstractCell: UICollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let text: String
        let isCollapsed: Bool
        let layoutMargins: UIEdgeInsets
        let maxWidth: CGFloat

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

        fileprivate weak var contentView: ItemDetailAbstractContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailAbstractContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailAbstractContentView else { return }

            self.add(contentView: view)
            self.contentView = view
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            self.contentView.layoutMargins = configuration.layoutMargins
            self.contentView.setup(with: configuration.text, isCollapsed: configuration.isCollapsed, maxWidth: configuration.maxWidth)
        }
    }
}
