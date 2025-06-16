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
    private(set) var disposeBag = DisposeBag()

    struct ContentConfiguration: UIContentConfiguration {
        let field: ItemDetailState.Field
        let titleWidth: CGFloat
        let layoutMargins: UIEdgeInsets
        let textObservable: PublishSubject<String>
        let disposeBag: DisposeBag

        init(field: ItemDetailState.Field, titleWidth: CGFloat, layoutMargins: UIEdgeInsets, disposeBag: DisposeBag) {
            self.field = field
            self.titleWidth = titleWidth
            self.layoutMargins = layoutMargins
            textObservable = PublishSubject()
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
            contentView.textObservable
                .bind(to: configuration.textObservable)
                .disposed(by: configuration.disposeBag)

            contentView.layoutMargins = configuration.layoutMargins
            contentView.setup(with: configuration.field, titleWidth: configuration.titleWidth)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        disposeBag = DisposeBag()
    }
}
