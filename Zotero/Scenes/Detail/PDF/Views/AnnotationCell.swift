//
//  AnnotationCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationCell: UITableViewCell {
    private(set) var key: String = ""
    private weak var annotationView: AnnotationView?

    var performAction: AnnotationViewAction? {
        get {
            return self.annotationView?.performAction
        }

        set {
            self.annotationView?.performAction = newValue
        }
    }

    // MARK: - Lifecycle

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.selectionStyle = .none
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.selectionStyle = .none
        self.setupView()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.key = ""
    }

    // MARK: - Actions

    func updatePreview(image: UIImage?) {
        self.annotationView?.updatePreview(image: image)
    }

    // MARK: - Setups

    private func setupView() {
        guard let view = Bundle.main.loadNibNamed("AnnotationView", owner: nil, options: nil)?.first as? AnnotationView else { return }

        let borderWidth = 1 / UIScreen.main.scale
        view.layer.cornerRadius = 8
        view.layer.borderWidth = borderWidth
        view.layer.shadowOpacity = 1
        view.layer.shadowRadius = 2
        view.layer.shadowOffset = CGSize()
        view.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(view)
        self.annotationView = view

        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: self.contentView.leftAnchor, constant: 8),
            self.contentView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: 8),
            view.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 0),
            self.contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func setup(with annotation: Annotation, attributedComment: NSAttributedString?, preview: UIImage?, selected: Bool, availableWidth: CGFloat, hasWritePermission: Bool) {
        self.key = annotation.key

        self.annotationView?.backgroundColor = self.contentBackgroundColor(selected: selected)
        self.annotationView?.layer.shadowColor = self.shadowColor(selected: selected).cgColor
        self.annotationView?.layer.borderColor = self.borderColor(selected: selected).cgColor
        self.annotationView?.setup(with: annotation, attributedComment: attributedComment, preview: preview, selected: selected,
                                   availableWidth: availableWidth, hasWritePermission: hasWritePermission)
    }

    // MARK: - Colors

    private func shadowColor(selected: Bool) -> UIColor {
        return selected ? Asset.Colors.annotationCellShadow.color : .clear
    }

    private func borderColor(selected: Bool) -> UIColor {
        return selected ? Asset.Colors.annotationCellSelectedBorder.color :
                          Asset.Colors.annotationCellBorder.color
    }

    private func contentBackgroundColor(selected: Bool) -> UIColor {
        return selected ? Asset.Colors.annotationCellSelectedBackground.color :
                          Asset.Colors.annotationCellBackground.color
    }
}
