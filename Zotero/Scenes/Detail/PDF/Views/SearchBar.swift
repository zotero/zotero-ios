//
//  SearchBar.swift
//  Zotero
//
//  Created by Michal Rentka on 18.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class SearchBar: UIView {
    private static let cancelOffset: CGFloat = 8

    private weak var textField: UITextField!
    private weak var cancelButton: UIButton!
    private var cancelRightConstraint: NSLayoutConstraint!
    private var textFieldRightConstraint: NSLayoutConstraint!

    private let insets: UIEdgeInsets
    private let cornerRadius: CGFloat
    private let disposeBag: DisposeBag

    var text: Observable<String> {
        return self.textField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.textField.text ?? "") })
    }

    // MARK: - Lifecycle

    init(frame: CGRect, insets: UIEdgeInsets, cornerRadius: CGFloat) {
        self.insets = insets
        self.cornerRadius = cornerRadius
        self.disposeBag = DisposeBag()
        super.init(frame: frame)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - Actions

    private func setCancel(active: Bool) {

        self.cancelRightConstraint.isActive = active
        self.textFieldRightConstraint.isActive = !active

        if active {
            self.cancelButton.isHidden = false
        }

        UIView.animate(withDuration: 0.2,
                       animations: {
                           self.cancelButton.alpha = active ? 1 : 0
                           self.layoutIfNeeded()
                       },
                       completion: { finished in
                           guard finished else { return }
                           self.cancelButton.isHidden = !active
                       })
    }

    // MARK: - Setups

    private func setupView() {
        let background = UIView()
        background.backgroundColor = Asset.Colors.searchBackground.color
        background.layer.cornerRadius = self.cornerRadius
        background.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass")?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = Asset.Colors.searchMagnifyingGlass.color
        icon.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        icon.setContentHuggingPriority(.defaultHigh, for: .vertical)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let textField = UITextField()
        textField.delegate = self
        textField.attributedPlaceholder = NSAttributedString(string: L10n.Searchbar.placeholder, attributes: [.foregroundColor: Asset.Colors.searchMagnifyingGlass.color])
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.returnKeyType = .search

        let cancel = UIButton(type: .custom)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitle(L10n.cancel, for: .normal)
        cancel.setTitleColor(Asset.Colors.zoteroBlueWithDarkMode.color, for: .normal)
        cancel.contentEdgeInsets = UIEdgeInsets(top: 0, left: SearchBar.cancelOffset, bottom: 0, right: self.insets.right)
        cancel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cancel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        cancel.isHidden = true
        cancel.alpha = 0
        cancel.rx.tap.subscribe(onNext: { [weak self] in
            self?.textField.resignFirstResponder()
        })
        .disposed(by: self.disposeBag)

        background.addSubview(icon)
        background.addSubview(textField)
        self.addSubview(background)
        self.addSubview(cancel)

        self.textFieldRightConstraint = self.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: self.insets.right)
        self.cancelRightConstraint = self.trailingAnchor.constraint(equalTo: cancel.trailingAnchor)

        NSLayoutConstraint.activate([
            // Background
            background.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: self.insets.left),
            self.textFieldRightConstraint,
            background.topAnchor.constraint(equalTo: self.topAnchor, constant: self.insets.top),
            self.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: self.insets.bottom),
            // Magnifying glass
            icon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: self.cornerRadius),
            icon.topAnchor.constraint(greaterThanOrEqualTo: background.topAnchor, constant: 4),
            background.bottomAnchor.constraint(greaterThanOrEqualTo: icon.bottomAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            // Text field
            textField.topAnchor.constraint(equalTo: background.topAnchor),
            background.bottomAnchor.constraint(equalTo: textField.bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            background.trailingAnchor.constraint(equalTo: textField.trailingAnchor, constant: self.cornerRadius),
            // Cancel button
            background.trailingAnchor.constraint(equalTo: cancel.leadingAnchor),
            cancel.topAnchor.constraint(equalTo: self.topAnchor),
            self.bottomAnchor.constraint(equalTo: cancel.bottomAnchor)
        ])

        self.textField = textField
        self.cancelButton = cancel
    }
}

extension SearchBar: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        self.setCancel(active: true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        self.setCancel(active: false)
    }
}
