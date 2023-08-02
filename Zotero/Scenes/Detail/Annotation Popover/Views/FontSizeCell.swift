//
//  FontSizeCell.swift
//  Zotero
//
//  Created by Michal Rentka on 01.08.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class FontSizeCell: RxTableViewCell {
    private weak var fontSizeView: FontSizeView!
    var tapObservable: PublishSubject<()> { return self.fontSizeView.tapObservable }
    var valueObservable: PublishSubject<UInt> { return self.fontSizeView.valueObservable }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    func set(value: UInt) {
        self.fontSizeView.value = value
    }

    private func setup() {
        let fontSizeView = FontSizeView(contentInsets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        fontSizeView.translatesAutoresizingMaskIntoConstraints = false
        fontSizeView.button.isUserInteractionEnabled = false
        self.fontSizeView = fontSizeView
        self.contentView.addSubview(fontSizeView)

        NSLayoutConstraint.activate([
            self.contentView.topAnchor.constraint(equalTo: fontSizeView.topAnchor),
            self.contentView.bottomAnchor.constraint(equalTo: fontSizeView.bottomAnchor),
            self.contentView.leadingAnchor.constraint(equalTo: fontSizeView.leadingAnchor),
            self.contentView.trailingAnchor.constraint(equalTo: fontSizeView.trailingAnchor)
        ])
    }
}
