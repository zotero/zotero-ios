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
    var tapObservable: PublishSubject<()> { return fontSizeView.tapObservable }
    var valueObservable: PublishSubject<CGFloat> { return fontSizeView.valueObservable }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func set(value: CGFloat) {
        fontSizeView.value = value
    }

    private func setup() {
        let fontSizeView = FontSizeView(contentInsets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16), stepperEnabled: true)
        fontSizeView.translatesAutoresizingMaskIntoConstraints = false
        fontSizeView.button.isUserInteractionEnabled = false
        self.fontSizeView = fontSizeView
        contentView.addSubview(fontSizeView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: fontSizeView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: fontSizeView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: fontSizeView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: fontSizeView.trailingAnchor)
        ])
    }
}
