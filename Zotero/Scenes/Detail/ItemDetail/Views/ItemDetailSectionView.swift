//
//  ItemDetailSectionView.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ItemDetailSectionView: UICollectionReusableView {
    private weak var titleLabel: UILabel?

    override init(frame: CGRect) {
        super.init(frame: frame)

        let separatorColor = UIColor(dynamicProvider: { traitCollection -> UIColor in
            traitCollection.userInterfaceStyle == .light ? .opaqueSeparator : Asset.Colors.itemDetailDarkSeparator.color
        })

        let container = UIView()
        container.backgroundColor = .white
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        let topSeparator = UIView()
        topSeparator.backgroundColor = separatorColor
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(topSeparator)

        let titleContainer = UIView()
        titleContainer.backgroundColor = .systemGray6
        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleContainer)

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = Asset.Colors.itemDetailHeaderTitle.color
        titleLabel.setContentHuggingPriority(UILayoutPriority(251), for: .horizontal)
        titleLabel.setContentHuggingPriority(UILayoutPriority(251), for: .vertical)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(titleLabel)
        self.titleLabel = titleLabel

        let bottomSeparator = UIView()
        bottomSeparator.backgroundColor = separatorColor
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bottomSeparator)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            topSeparator.topAnchor.constraint(equalTo: container.topAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: ItemDetailLayout.separatorHeight),
            titleContainer.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            titleContainer.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
            titleContainer.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor),
            bottomSeparator.topAnchor.constraint(equalTo: titleContainer.bottomAnchor),
            bottomSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomSeparator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: ItemDetailLayout.separatorHeight)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(with title: String) {
        titleLabel?.text = title
    }
}
