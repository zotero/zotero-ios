//
//  CitationPreviewCell.swift
//  Zotero
//
//  Created by Michal Rentka on 07.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CitationPreviewCell: UICollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let preview: String
        let height: CGFloat

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

        fileprivate weak var contentView: CitationPreviewContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            let view = CitationPreviewContentView()
            add(contentView: view)
            contentView = view
            apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            contentView.setup(preview: configuration.preview, height: configuration.height)
        }
    }
}
