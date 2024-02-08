//
//  CitationAuthorContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 07.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class CitationAuthorContentView: UIView {
    private weak var titleLabel: UILabel!
    private weak var toggle: UISwitch!

    private var omitAuthorChanged: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)

        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .body)
        title.textColor = .label
        title.text = L10n.Citation.omitAuthor
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        titleLabel = title

        let action = UIAction { [weak self] _ in
            self?.omitAuthorChanged?(self?.toggle.isOn ?? false)
        }
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addAction(action, for: .valueChanged)
        addSubview(toggle)
        self.toggle = toggle

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bottomAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            trailingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 16),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(omitAuthor: Bool, omitAuthorChanged: @escaping (Bool) -> Void) {
        toggle.isOn = omitAuthor
        self.omitAuthorChanged = omitAuthorChanged
    }
}
