//
//  PDFSettingsSegmentedCell.swift
//  Zotero
//
//  Created by Michal Rentka on 03.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class PDFSettingsSegmentedCell: UICollectionViewListCell {
    struct ContentConfiguration: UIContentConfiguration {
        let title: String
        let actions: [UIAction]
        let selectedIndex: Int

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

        fileprivate weak var contentView: PDFSettingsSegmentedCellContentView?

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            guard let view = UINib.init(nibName: "PDFSettingsSegmentedCellContentView", bundle: nil).instantiate(withOwner: self)[0] as? PDFSettingsSegmentedCellContentView else { return }
            self.setup(view: view)
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            self.contentView?.setup(title: configuration.title, actions: configuration.actions, selectedIndex: configuration.selectedIndex)
        }

        private func setup(view: PDFSettingsSegmentedCellContentView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(view)
            self.contentView = view

            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                self.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                view.topAnchor.constraint(equalTo: self.topAnchor),
                self.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
}
