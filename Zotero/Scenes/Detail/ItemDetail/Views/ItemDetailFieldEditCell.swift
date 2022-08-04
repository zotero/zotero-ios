//
//  ItemDetailFieldEditCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class ItemDetailFieldEditCell: RxCollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let field: ItemDetailState.Field
        let titleWidth: CGFloat

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
                self.contentView.setup(with: configuration.field, titleWidth: configuration.titleWidth)
            }
        }

        fileprivate weak var contentView: ItemDetailFieldEditContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailFieldEditContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailFieldEditContentView else { return }

            self.add(contentView: view)
            self.contentView = view
            self.contentView.setup(with: configuration.field, titleWidth: configuration.titleWidth)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }
    }

    var textObservable: Observable<String>? {
        return (self.contentView as? ItemDetailFieldEditContentView)?.textObservable
    }
}
