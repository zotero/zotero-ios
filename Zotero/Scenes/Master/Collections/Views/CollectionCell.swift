//
//  CollectionCell.swift
//  Zotero
//
//  Created by Michal Rentka on 14/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CollectionCell: UICollectionViewListCell {
    struct Accessories: OptionSet {
        typealias RawValue = Int8

        var rawValue: Int8

        init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        static let badge = Accessories(rawValue: 1 << 0)
        static let chevron = Accessories(rawValue: 1 << 1)
    }
    
    struct ContentConfiguration: UIContentConfiguration {
        let collection: Collection
        let hasChildren: Bool
        let accessories: Accessories

        var toggleCollapsed: (() -> Void)?
        var isCollapsedProvider: (() -> Bool)?

        func makeContentView() -> UIView & UIContentView {
            return ContentView(baseConfiguration: self)
        }

        func updated(for state: UIConfigurationState) -> ContentConfiguration {
            return self
        }
    }

    struct SearchContentConfiguration: UIContentConfiguration {
        let collection: Collection
        let hasChildren: Bool
        let isActive: Bool
        let accessories: Accessories

        func makeContentView() -> UIView & UIContentView {
            return ContentView(searchConfiguration: self)
        }

        func updated(for state: UIConfigurationState) -> SearchContentConfiguration {
            return self
        }
    }

    struct LibraryContentConfiguration: UIContentConfiguration {
        let name: String
        let accessories: Accessories

        var toggleCollapsed: (() -> Void)?
        var isCollapsedProvider: (() -> Bool)?

        func makeContentView() -> UIView & UIContentView {
            return ContentView(libraryConfiguration: self)
        }

        func updated(for state: UIConfigurationState) -> LibraryContentConfiguration {
            return self
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOS 26.0.0, *) {
            indentationWidth = 16
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var backgroundConfiguration = UIBackgroundConfiguration.listPlainCell().updated(for: state)

        if #available(iOS 26.0.0, *) {
            if state.isHighlighted || state.isSelected {
                switch traitCollection.splitViewControllerLayoutEnvironment {
                case .expanded:
                    let selectedBackgroundView = UIView()
                    selectedBackgroundView.backgroundColor = .tertiarySystemFill
                    selectedBackgroundView.cornerConfiguration = .capsule()
                    self.selectedBackgroundView = selectedBackgroundView
                    (contentView as? ContentView)?.contentView?.updateTitleLabel(emphasized: true)
                    return

                case .none, .collapsed:
                    break

                @unknown default:
                    break
                }
                selectedBackgroundView = nil
                backgroundConfiguration.backgroundColor = .systemGray5
            }
            (contentView as? ContentView)?.contentView?.updateTitleLabel(emphasized: false)
        }

        self.backgroundConfiguration = backgroundConfiguration
    }

    final class ContentView: UIView, UIContentView {
        var configuration: UIContentConfiguration {
            didSet {
                if let configuration = self.configuration as? ContentConfiguration {
                    self.apply(configuration: configuration)
                } else if let configuration = self.configuration as? SearchContentConfiguration {
                    self.apply(configuration: configuration)
                } else if let configuration = self.configuration as? LibraryContentConfiguration {
                    self.apply(configuration: configuration)
                }
            }
        }

        fileprivate weak var contentView: CollectionCellContentView?

        private init(configuration: UIContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            let view = CollectionCellContentView()
            self.setup(view: view)
        }

        convenience init(baseConfiguration: ContentConfiguration) {
            self.init(configuration: baseConfiguration)
            self.apply(configuration: baseConfiguration)
        }

        convenience init(searchConfiguration: SearchContentConfiguration) {
            self.init(configuration: searchConfiguration)
            self.apply(configuration: searchConfiguration)
        }

        convenience init(libraryConfiguration: LibraryContentConfiguration) {
            self.init(configuration: libraryConfiguration)
            self.apply(configuration: libraryConfiguration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            let isCollapsed = configuration.isCollapsedProvider?() ?? false
            self.contentView?.set(collection: configuration.collection, hasChildren: configuration.hasChildren, isCollapsed: isCollapsed, accessories: configuration.accessories, toggleCollapsed: configuration.toggleCollapsed)
        }

        private func apply(configuration: SearchContentConfiguration) {
            self.contentView?.set(collection: configuration.collection, hasChildren: configuration.hasChildren, isCollapsed: false, accessories: configuration.accessories, toggleCollapsed: nil)
            self.contentView?.alpha = configuration.isActive ? 1 : 0.4
        }

        private func apply(configuration: LibraryContentConfiguration) {
            let isCollapsed = configuration.isCollapsedProvider?() ?? false
            self.contentView?.set(libraryName: configuration.name, isCollapsed: isCollapsed, accessories: configuration.accessories, toggleCollapsed: configuration.toggleCollapsed)
        }

        private func setup(view: CollectionCellContentView) {
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

    var collection: Collection? {
        guard let contentView = self.contentView as? ContentView else { return nil }

        if let configuration = contentView.configuration as? ContentConfiguration {
            return configuration.collection
        }
        if let configuration = contentView.configuration as? SearchContentConfiguration {
            return configuration.collection
        }
        return nil
    }
}
