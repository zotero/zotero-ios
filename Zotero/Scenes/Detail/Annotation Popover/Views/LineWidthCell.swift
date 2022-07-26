//
//  LineWidthCell.swift
//  Zotero
//
//  Created by Michal Rentka on 06.09.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class LineWidthCell: RxTableViewCell {

    private weak var lineView: LineWidthView!
    var valueObservable: Observable<Float> { return self.lineView.valueObservable }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    func set(value: Float) {
        self.lineView.value = value
    }

    private func setup() {
        let lineView = LineWidthView(title: L10n.Pdf.AnnotationPopover.lineWidth, settings: .lineWidth)
        lineView.translatesAutoresizingMaskIntoConstraints = false
        self.lineView = lineView
        self.contentView.addSubview(lineView)

        NSLayoutConstraint.activate([
            self.contentView.topAnchor.constraint(equalTo: lineView.topAnchor),
            self.contentView.bottomAnchor.constraint(equalTo: lineView.bottomAnchor),
            self.contentView.leadingAnchor.constraint(equalTo: lineView.leadingAnchor),
            self.contentView.trailingAnchor.constraint(equalTo: lineView.trailingAnchor)
        ])
    }
}
