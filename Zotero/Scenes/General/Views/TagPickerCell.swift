//
//  TagPickerCell.swift
//  Zotero
//
//  Created by Michal Rentka on 05/11/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class TagPickerCell: UICollectionViewListCell {
    private let tagView = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        tagView.layer.cornerRadius = 8
        tagView.layer.masksToBounds = true
        tagView.backgroundColor = .systemBackground
        label.font = .preferredFont(forTextStyle: .body)

        let stackView = UIStackView(arrangedSubviews: [tagView, label])
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            tagView.widthAnchor.constraint(equalToConstant: 16),
            tagView.heightAnchor.constraint(equalToConstant: 16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        accessories = [.multiselect(displayed: .whenEditing)]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)

        var configuration = defaultBackgroundConfiguration().updated(for: state)
        if #available(iOS 26.0, *), state.isSelected {
            configuration.backgroundColor = .systemGray5
            configuration.backgroundColorTransformer = nil
        }
        backgroundConfiguration = configuration
    }

    func setup(with tag: Tag) {
        let (color, style) = TagColorGenerator.uiColor(for: tag.color)

        switch style {
        case .border:
            tagView.isHidden = true

        case .filled:
            tagView.backgroundColor = color
            tagView.isHidden = false
        }

        label.text = tag.name
    }
}
