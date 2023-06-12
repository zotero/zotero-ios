//
//  NoteEditorTitleView.swift
//  Zotero
//
//  Created by Michal Rentka on 20.07.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class NoteEditorTitleView: UIStackView {
    init(type: String, title: String) {
        super.init(frame: CGRect())

        self.axis = .horizontal
        self.spacing = 12
        self.alignment = .center

        self.setup(type: type, title: title)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setups

    private func setup(type: String, title: String) {
        let iconName = ItemTypes.iconName(for: type, contentType: nil)
        let imageView = UIImageView(image: UIImage(named: iconName))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        self.addArrangedSubview(imageView)

        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.font = .preferredFont(forTextStyle: .subheadline).withTraits(.traitBold)
        label.text = title
        label.numberOfLines = 1
        self.addArrangedSubview(label)
    }
}
