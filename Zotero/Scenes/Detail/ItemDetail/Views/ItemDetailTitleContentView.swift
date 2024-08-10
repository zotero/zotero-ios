//
//  ItemDetailTitleContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import RxSwift

final class ItemDetailTitleContentView: UIView {
    private weak var textView: FormattedTextView!
    private weak var topConstraint: NSLayoutConstraint!
    private weak var bottomConstraint: NSLayoutConstraint!
    private weak var separatorHeight: NSLayoutConstraint!

    var attributedTextObservable: Observable<NSAttributedString> {
        textView.attributedTextObservable
    }

    private var delegate: PlaceholderTextViewDelegate!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        backgroundColor = .systemBackground
        isAccessibilityElement = false
        setupBottomConstraint()

        func setup() {
            let font: UIFont = .preferredFont(for: .headline, weight: .regular)
            let textView = FormattedTextView(defaultFont: font)
            textView.textContainerInset = UIEdgeInsets()
            textView.textContainer.lineFragmentPadding = 0
            textView.isScrollEnabled = false
            textView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textView)
            self.textView = textView

            delegate = PlaceholderTextViewDelegate(placeholder: L10n.ItemDetail.untitled, textView: textView)
            textView.delegate = delegate

            let separatorView = UIView()
            separatorView.backgroundColor = .separator
            separatorView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(separatorView)

            topConstraint = textView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor, constant: font.capHeight - font.ascender)
            bottomConstraint = layoutMarginsGuide.bottomAnchor.constraint(equalTo: textView.bottomAnchor)
            separatorHeight = separatorView.heightAnchor.constraint(equalToConstant: ItemDetailLayout.separatorHeight)

            NSLayoutConstraint.activate([
                topConstraint,
                bottomConstraint,
                textView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                layoutMarginsGuide.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
                bottomAnchor.constraint(equalTo: separatorView.bottomAnchor),
                separatorView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                trailingAnchor.constraint(equalTo: separatorView.trailingAnchor),
                separatorHeight
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        setupBottomConstraint()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        delegate.layoutPlaceholder(in: textView)
    }

    func setup(with title: NSAttributedString, isEditing: Bool) {
        textView.isEditable = isEditing
        delegate.set(text: title, to: textView)
    }
    
    private func setupBottomConstraint() {
        if traitCollection.horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad, let font = textView.font {
            bottomConstraint.constant = -font.descender
        } else {
            bottomConstraint.constant = 0
        }
    }
}
