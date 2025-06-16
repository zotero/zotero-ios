//
//  ItemDetailFieldEditCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class ItemDetailFieldEditCell: UICollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let field: ItemDetailState.Field
        let titleWidth: CGFloat
        let layoutMargins: UIEdgeInsets
        let textChanged: (String) -> Void

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
                guard let configuration = configuration as? ContentConfiguration else { return }
                apply(configuration: configuration)
            }
        }

        fileprivate weak var contentView: ItemDetailFieldEditContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailFieldEditContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailFieldEditContentView else { return }

            add(contentView: view)
            contentView = view
            apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            contentView.textChanged = configuration.textChanged
            contentView.layoutMargins = configuration.layoutMargins
            contentView.setup(with: configuration.field, titleWidth: configuration.titleWidth)
        }
    }
}
