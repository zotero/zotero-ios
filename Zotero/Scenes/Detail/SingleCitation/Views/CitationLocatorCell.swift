//
//  CitationLocatorCell.swift
//  Zotero
//
//  Created by Michal Rentka on 06.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CitationLocatorCell: UICollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let locator: String
        let value: String
        let locatorChanged: (String) -> Void
        let valueChanged: (String) -> Void

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
                apply(configuration: configuration)
            }
        }

        fileprivate weak var contentView: CitationLocatorContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            let view = CitationLocatorContentView()
            add(contentView: view)
            contentView = view
            apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            contentView.setup(withLocator: configuration.locator, value: configuration.value, locatorChanged: configuration.locatorChanged, valueChanged: configuration.valueChanged)
        }
    }
}
