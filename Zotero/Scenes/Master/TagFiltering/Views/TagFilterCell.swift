//
//  TagFilterCell.swift
//  Zotero
//
//  Created by Michal Rentka on 13.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class TagFilterCell: UICollectionViewCell {
    struct ContentConfiguration: UIContentConfiguration {
        let text: String
        let color: UIColor

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

        fileprivate weak var contentView: TagFilterContentView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "TagFilterContentView", bundle: nil).instantiate(withOwner: self)[0] as? TagFilterContentView else { return }

            self.add(contentView: view)
            self.contentView = view
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            self.contentView.setup(with: configuration.text, color: configuration.color)
        }
    }
}

