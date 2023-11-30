//
//  SearchBar.swift
//  Zotero
//
//  Created by Michal Rentka on 18.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class SearchBar: UIView {
    private static let cancelOffset: CGFloat = 8

    private weak var textField: UITextField!
    private weak var clearButton: UIButton!
    private weak var cancelButton: UIButton!
    private var cancelRightConstraint: NSLayoutConstraint!
    private var textFieldRightConstraint: NSLayoutConstraint!

    private let insets: UIEdgeInsets
    private let cornerRadius: CGFloat
    private let disposeBag: DisposeBag
    let text: BehaviorSubject<String>

    // MARK: - Lifecycle

    init(frame: CGRect, insets: UIEdgeInsets, cornerRadius: CGFloat) {
        self.insets = insets
        self.cornerRadius = cornerRadius
        self.text = BehaviorSubject(value: "")
        self.disposeBag = DisposeBag()
        super.init(frame: frame)
        self.setupView()

        self.textField.rx.controlEvent(.editingChanged).flatMap({ Observable.just(self.textField.text ?? "") }).subscribe(onNext: { [weak self] text in
            self?.text.on(.next(text))
            self?.clearButton.isHidden = text.isEmpty
        })
        .disposed(by: self.disposeBag)
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

    private func clear() {
        self.clearButton.isHidden = true
        self.textField.text = ""
        self.text.on(.next(""))
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
        textField.adjustsFontForContentSizeCategory = true
        textField.attributedPlaceholder = NSAttributedString(string: L10n.Searchbar.placeholder, attributes: [.foregroundColor: Asset.Colors.searchMagnifyingGlass.color])
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.returnKeyType = .search
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let clear = UIButton()
        clear.translatesAutoresizingMaskIntoConstraints = false
        clear.accessibilityLabel = L10n.Searchbar.accessibilityClear
        clear.tintColor = .systemGray
        clear.isHidden = true
        clear.rx.tap.subscribe(onNext: { [weak self] in
            self?.clear()
        })
        .disposed(by: self.disposeBag)
        clear.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        clear.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let clearImage = UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .medium))?.withRenderingMode(.alwaysTemplate)

        var clearConfiguration = UIButton.Configuration.plain()
        clearConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: self.cornerRadius, bottom: 8, trailing: self.cornerRadius)
        clearConfiguration.image = clearImage
        clear.configuration = clearConfiguration

        var cancelConfiguration = UIButton.Configuration.plain()
        cancelConfiguration.title = L10n.cancel
        cancelConfiguration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
        cancelConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: SearchBar.cancelOffset, bottom: 0, trailing: insets.right)
        let cancel = UIButton(type: .custom)
        cancel.configuration = clearConfiguration
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.accessibilityLabel = L10n.Searchbar.accessibilityCancel
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
        background.addSubview(clear)
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
            // Clear button
            clear.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
            clear.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            background.trailingAnchor.constraint(equalTo: clear.trailingAnchor),
            // Cancel button
            background.trailingAnchor.constraint(equalTo: cancel.leadingAnchor),
            cancel.topAnchor.constraint(equalTo: self.topAnchor),
            self.bottomAnchor.constraint(equalTo: cancel.bottomAnchor)
        ])

        self.textField = textField
        self.clearButton = clear
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
