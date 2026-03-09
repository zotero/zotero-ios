//
//  SpeechHighlighterOverlayView.swift
//  Zotero
//
//  Created by Michal Rentka on 09.03.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class SpeechHighlighterOverlayView: UIView {
    private weak var textLabel: UILabel?

    var deleteAction: (() -> Void)?
    var skipBackwardAction: (() -> Void)?
    var backwardAction: (() -> Void)?
    var forwardAction: (() -> Void)?
    var skipForwardAction: (() -> Void)?
    var colorAction: (() -> Void)?

    init(isCompact: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup(isCompact: isCompact)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String?) {
        textLabel?.text = text
    }

    // MARK: - Setup

    private func setup(isCompact: Bool) {
        backgroundColor = .systemBackground
        layer.cornerRadius = 13
        layer.masksToBounds = true
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.cgColor

        let textLabel = createTextLabel()
        let textContainer = createTextContainer(textLabel: textLabel)
        let separator = createSeparator()
        let buttonStack = createButtonStack()

        addSubview(textContainer)
        addSubview(separator)
        addSubview(buttonStack)

        if isCompact {
            // Compact: text on top, controls on bottom
            NSLayoutConstraint.activate([
                textContainer.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                textContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                trailingAnchor.constraint(equalTo: textContainer.trailingAnchor, constant: 12),
                separator.topAnchor.constraint(equalTo: textContainer.bottomAnchor, constant: 12),
                separator.leadingAnchor.constraint(equalTo: leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: trailingAnchor),
                separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                buttonStack.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
                buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                trailingAnchor.constraint(equalTo: buttonStack.trailingAnchor, constant: 8),
                bottomAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 4)
            ])
        } else {
            // Regular: controls on top, text on bottom
            NSLayoutConstraint.activate([
                buttonStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                trailingAnchor.constraint(equalTo: buttonStack.trailingAnchor, constant: 8),
                separator.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 4),
                separator.leadingAnchor.constraint(equalTo: leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: trailingAnchor),
                separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                textContainer.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
                textContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                trailingAnchor.constraint(equalTo: textContainer.trailingAnchor, constant: 12),
                bottomAnchor.constraint(equalTo: textContainer.bottomAnchor, constant: 12)
            ])
        }

        self.textLabel = textLabel
    }

    private func createTextLabel() -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        return label
    }

    private func createTextContainer(textLabel: UILabel) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.4)
        container.layer.cornerRadius = 4
        container.addSubview(textLabel)
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            textLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 8)
        ])
        return container
    }

    private func createSeparator() -> UIView {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        return separator
    }

    private func createButtonStack() -> UIStackView {
        let imageConfig = UIImage.SymbolConfiguration(scale: .large)

        let deleteButton = createButton(systemName: "trash", config: imageConfig, tintColor: .systemRed) { [weak self] in self?.deleteAction?() }
        let skipBackwardButton = createButton(systemName: "arrow.left.to.line", config: imageConfig) { [weak self] in self?.skipBackwardAction?() }
        let backwardButton = createButton(systemName: "arrow.left", config: imageConfig) { [weak self] in self?.backwardAction?() }
        let forwardButton = createButton(systemName: "arrow.right", config: imageConfig) { [weak self] in self?.forwardAction?() }
        let skipForwardButton = createButton(systemName: "arrow.right.to.line", config: imageConfig) { [weak self] in self?.skipForwardAction?() }
        let colorButton = createColorButton()

        let stack = UIStackView(arrangedSubviews: [deleteButton, skipBackwardButton, backwardButton, forwardButton, skipForwardButton, colorButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        return stack
    }

    private func createButton(
        systemName: String,
        config: UIImage.SymbolConfiguration,
        tintColor: UIColor = Asset.Colors.zoteroBlueWithDarkMode.color,
        action: @escaping () -> Void
    ) -> UIButton {
        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.image = UIImage(systemName: systemName, withConfiguration: config)
        buttonConfig.baseForegroundColor = tintColor
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: buttonConfig)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction(handler: { _ in action() }), for: .touchUpInside)
        return button
    }

    private func createColorButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "character.textbox", withConfiguration: UIImage.SymbolConfiguration(scale: .large))
        config.baseForegroundColor = .systemOrange
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction(handler: { [weak self] _ in self?.colorAction?() }), for: .touchUpInside)
        return button
    }
}
