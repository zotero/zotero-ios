//
//  ItemsToolbarDownloadProgressView.swift
//  Zotero
//
//  Created by Michal Rentka on 31.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class ItemsToolbarDownloadProgressView: UIView {
    private var label: UILabel!
    private var progressView: UIProgressView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.createViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.createViews()
    }

    func set(downloaded: Int, total: Int, progress: Float) {
        self.label.text = L10n.Items.toolbarDownloaded(downloaded, total)
        self.progressView.progress = progress
    }

    private func createViews() {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        self.label = label

        let progressView = UIProgressView(progressViewStyle: .bar)
        progressView.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
        progressView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        self.progressView = progressView

        let stackView = UIStackView(arrangedSubviews: [label, progressView])
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stackView)

        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            self.topAnchor.constraint(equalTo: stackView.topAnchor),
            self.bottomAnchor.constraint(equalTo: stackView.bottomAnchor)
        ])
    }
}
