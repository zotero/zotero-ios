//
//  SearchBarCell.swift
//  Zotero
//
//  Created by Michal Rentka on 20.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class SearchBarCell: UICollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let text: String
        let changeAction: (String) -> Void

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

        fileprivate weak var searchBar: SearchBar?
        private var disposeBag: DisposeBag

        init(configuration: ContentConfiguration) {
            self.configuration = configuration
            self.disposeBag = DisposeBag()

            super.init(frame: .zero)

            self.backgroundColor = .systemGray6
            self.setupView()
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            guard let searchBar = self.searchBar else { return }

            self.disposeBag = DisposeBag()

            searchBar.text.observe(on: MainScheduler.instance)
                     .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                     .subscribe(onNext: { text in
                         configuration.changeAction(text)
                     })
                     .disposed(by: self.disposeBag)
        }

        private func setupView() {
            let insets = UIEdgeInsets(top: PDFReaderLayout.searchBarVerticalInset, left: 0, bottom: PDFReaderLayout.searchBarVerticalInset - PDFReaderLayout.cellSelectionLineWidth, right: 0)

            let searchBar = SearchBar(frame: frame, insets: insets, cornerRadius: 10)
            searchBar.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(searchBar)
            self.searchBar = searchBar

            NSLayoutConstraint.activate([
                searchBar.heightAnchor.constraint(equalToConstant: 65),
                searchBar.topAnchor.constraint(equalTo: self.topAnchor),
                searchBar.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                searchBar.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                searchBar.trailingAnchor.constraint(equalTo: self.trailingAnchor)
            ])
        }
    }
}
