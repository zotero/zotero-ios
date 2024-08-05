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
        let attributedTextObservable: PublishSubject<NSAttributedString>
        let disposeBag: CompositeDisposable

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
            let disposable = contentView.attributedTextObservable.subscribe { [weak self] title in
                let newConfiguration = ContentConfiguration(
                    title: title,
                    isEditing: configuration.isEditing,
                    layoutMargins: configuration.layoutMargins,
                    attributedTextObservable: configuration.attributedTextObservable,
                    disposeBag: configuration.disposeBag
                )
                self?.configuration = newConfiguration
                configuration.attributedTextObservable.onNext(title)
            }
            _ = configuration.disposeBag.insert(disposable)

            self.contentView.layoutMargins = configuration.layoutMargins
            self.contentView.setup(with: configuration.title, isEditing: configuration.isEditing)
        }
    }
}
