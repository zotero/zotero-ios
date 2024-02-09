//
//  CitationLocatorContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 06.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class CitationLocatorContentView: UIView {
    private weak var locatorButton: UIButton!
    private weak var valueField: UITextField!

    private var valueChanged: ((String) -> Void)?

    init() {
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 60)
        let button = UIButton(configuration: configuration)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = true
        addSubview(button)
        locatorButton = button

        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.delegate = self
        textField.placeholder = "Number"
        addSubview(textField)
        valueField = textField

        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: button.topAnchor),
            leadingAnchor.constraint(equalTo: button.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: textField.leadingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            topAnchor.constraint(equalTo: textField.topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup(withLocator locator: String, value: String, locatorChanged: @escaping (String) -> Void, valueChanged: @escaping (String) -> Void) {
        self.valueChanged = valueChanged
        valueField.text = value
        setupButton()

        func setupButton() {
            let locatorElements: [UIMenuElement] = SingleCitationState.locators.compactMap { pickerLocator in
                return UIAction(title: localized(locator: pickerLocator), state: locator == pickerLocator ? .on : .off) { _ in
                    locatorChanged(pickerLocator)
                }
            }
            var configuration = locatorButton.configuration
            configuration?.title = localized(locator: locator)
            locatorButton.configuration = configuration
            locatorButton.menu = UIMenu(children: locatorElements)
        }

        func localized(locator: String) -> String {
            return NSLocalizedString("citation.locator.\(locator)", comment: "")
        }
    }
}

extension CitationLocatorContentView: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text as? NSString else { return true }
        let newString = text.replacingCharacters(in: range, with: string)
        valueChanged?(newString)
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
