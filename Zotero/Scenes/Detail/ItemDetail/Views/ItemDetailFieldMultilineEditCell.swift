//
//  ItemDetailFieldMultilineEditCell.swift
//  Zotero
//
//  Created by Michal Rentka on 07.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemDetailFieldMultilineEditCell: UICollectionViewListCell {
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

        fileprivate weak var contentView: ItemDetailFieldMultilineEditContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailFieldMultilineEditContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailFieldMultilineEditContentView else { return }

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
