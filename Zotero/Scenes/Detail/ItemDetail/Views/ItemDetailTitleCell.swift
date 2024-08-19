//
//  ItemDetailTitleCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import RxSwift

final class ItemDetailTitleCell: UICollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let title: NSAttributedString
        let isEditing: Bool
        let layoutMargins: UIEdgeInsets
        let attributedTextChanged: ((NSAttributedString) -> Void)?

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

        fileprivate weak var contentView: ItemDetailTitleContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            let view = ItemDetailTitleContentView(frame: .zero)

            self.add(contentView: view)
            self.contentView = view
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            contentView.attributedTextChanged = configuration.attributedTextChanged
            contentView.layoutMargins = configuration.layoutMargins
            contentView.setup(with: configuration.title, isEditing: configuration.isEditing)
        }
    }
}
