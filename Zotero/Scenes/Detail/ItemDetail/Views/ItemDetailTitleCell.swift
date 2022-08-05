//
//  ItemDetailTitleCell.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxCocoa
import RxSwift

final class ItemDetailTitleCell: RxCollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let title: String
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
                self.contentView.setup(with: configuration.title, isEditing: configuration.isEditing)
            }
        }

        fileprivate weak var contentView: ItemDetailTitleContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailTitleContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailTitleContentView else { return }

            self.add(contentView: view)
            view.layoutMargins = configuration.layoutMargins
            self.contentView = view
            self.contentView.setup(with: configuration.title, isEditing: configuration.isEditing)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }
    }

    var textObservable: Observable<String>? {
        return (self.contentView as? ItemDetailTitleContentView)?.delegate.textObservable
    }
}
