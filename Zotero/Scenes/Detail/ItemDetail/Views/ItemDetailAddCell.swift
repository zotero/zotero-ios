//
//  ItemDetailAddCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ItemDetailAddCell: UICollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let title: String
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
                self.contentView.setup(with: configuration.title)
            }
        }

        fileprivate weak var contentView: ItemDetailAddContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailAddContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailAddContentView else { return }

            self.add(contentView: view)
            view.layoutMargins = configuration.layoutMargins
            self.contentView = view
            self.contentView.setup(with: configuration.title)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }
    }
}
