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
    private(set) var disposeBag = CompositeDisposable()

    struct ContentConfiguration: UIContentConfiguration {
        let field: ItemDetailState.Field
        let titleWidth: CGFloat
        let layoutMargins: UIEdgeInsets
        let textObservable: PublishSubject<String>
        let disposeBag: CompositeDisposable

        init(field: ItemDetailState.Field, titleWidth: CGFloat, layoutMargins: UIEdgeInsets, disposeBag: CompositeDisposable) {
            self.field = field
            self.titleWidth = titleWidth
            self.layoutMargins = layoutMargins
            self.textObservable = PublishSubject()
            self.disposeBag = disposeBag
        }

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

        fileprivate weak var contentView: ItemDetailFieldEditContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "ItemDetailFieldEditContentView", bundle: nil).instantiate(withOwner: self)[0] as? ItemDetailFieldEditContentView else { return }

            self.add(contentView: view)
            self.contentView = view
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            let disposable = self.contentView.textObservable.bind(to: configuration.textObservable)
            _ = configuration.disposeBag.insert(disposable)

            self.contentView.layoutMargins = configuration.layoutMargins
            self.contentView.setup(with: configuration.field, titleWidth: configuration.titleWidth)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        disposeBag.dispose()
        disposeBag = CompositeDisposable()
    }
}
