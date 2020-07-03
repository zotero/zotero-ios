//
//  AnnotationCommentEditorViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 02/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class AnnotationCommentEditorViewController: UIViewController {
    enum ToolbarAction: Int, CaseIterable {
        case b = 1
        case i = 2
        case sup = 3
        case sub = 4

        init(attribute: StringAttribute) {
            switch attribute {
            case .bold: self = .b
            case .italic: self = .i
            case .superscript: self = .sup
            case .subscript: self = .sub
            }
        }

        var toAttribute: StringAttribute {
            switch self {
            case .b: return .bold
            case .i: return .italic
            case .sub: return .subscript
            case .sup: return .superscript
            }
        }
    }

    @IBOutlet private weak var textView: UITextView!
    @IBOutlet private weak var buttonToolbar: UIStackView!

    private let font: UIFont
    private let text: String
    private let saveAction: (String) -> Void
    private unowned let converter: HtmlAttributedStringConverter
    private let disposeBag: DisposeBag

    private var ignoreSelectionChange: Bool
    private var activeActions: [ToolbarAction] {
        return self.buttonToolbar.arrangedSubviews
                                 .compactMap({ view -> ToolbarAction? in
                                     if let button = view as? CheckboxButton, button.isSelected {
                                         return ToolbarAction(rawValue: button.tag)
                                     }
                                     return nil
                                 })
    }

    // MARK: - Lifecycle

    init(text: String, converter: HtmlAttributedStringConverter, saveAction: @escaping (String) -> Void) {
        self.text = text
        self.converter = converter
        self.saveAction = saveAction
        self.ignoreSelectionChange = false
        self.font = UIFont.preferredFont(for: .body, weight: .regular)
        self.disposeBag = DisposeBag()
        super.init(nibName: "AnnotationCommentEditorViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupToolbarButtons()
        self.setupTextView()
    }

    // MARK: - Actions

    @objc func save() {
        guard let attributedString = self.textView.attributedText, !attributedString.string.isEmpty else { return }
        self.saveAction(self.converter.convert(attributedString: attributedString))
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Toolbar

    private func toggle(button: CheckboxButton) {
        // Toggle button
        button.isSelected = !button.isSelected

        guard let action = ToolbarAction(rawValue: button.tag), button.isSelected else { return }

        // .sub and .sup are mutually exclusive, so toggle the other one off
        switch action {
        case .sub:
            self.deselectButton(with: .sup)
        case .sup:
            self.deselectButton(with: .sub)
        default: break
        }
    }

    private func selectButtons(with actions: [ToolbarAction]) {
        for view in self.buttonToolbar.arrangedSubviews {
            guard let button = view as? CheckboxButton,
                  let action = ToolbarAction(rawValue: button.tag) else { continue }
            button.isSelected = actions.contains(action)
        }
    }

    private func deselectButton(with action: ToolbarAction) {
        guard let button = self.buttonToolbar.arrangedSubviews.first(where: { $0.tag == action.rawValue }) as? CheckboxButton,
              button.isSelected else { return }
        button.isSelected = false
    }

    private func deselectAllButtons() {
        for view in self.buttonToolbar.arrangedSubviews {
            guard let button = view as? CheckboxButton, button.isSelected else { continue }
            button.isSelected = false
        }
    }

    // MARK: - Text selection

    private func selectActiveButtons(in range: NSRange) {
        if range.length == 0 {
            // If selected range is 0, just check current typing attributes
            self.selectButtons(from: self.textView.typingAttributes)
            return
        }

        // Otherwise check whether the whole range has the same attributes (and activate their respective buttons)
        // or they differ (and deactivate all buttons)
        var hasMultipleRanges = false
        var lastAttributes: [NSAttributedString.Key: Any] = [:]
        self.textView.attributedText.enumerateAttributes(in: range, options: []) { attributes, range, shouldStop in
            if lastAttributes.isEmpty {
                lastAttributes = attributes
            } else {
                hasMultipleRanges = true
                shouldStop[0] = true
            }
        }

        if hasMultipleRanges {
            self.deselectAllButtons()
        } else {
            self.selectButtons(from: lastAttributes)
        }
    }

    private func selectButtons(from attributes: [NSAttributedString.Key: Any]) {
        let actions = StringAttribute.attributes(from: attributes).map(ToolbarAction.init)
        self.selectButtons(with: actions)
    }

    // MARK: - Text editing

    private func setActive(actions: [ToolbarAction]) {
        if actions.isEmpty {
            self.textView.typingAttributes = [.font: self.font]
        } else {
            let attributes = StringAttribute.nsStringAttributes(from: actions.map({ $0.toAttribute }), baseFont: self.font)
            self.textView.typingAttributes = attributes
        }
    }

    private func updateText(in range: NSRange, with action: ToolbarAction, active: Bool) {
        guard range.length > 0, let attributedString = self.textView.attributedText else { return }

        let mutableString = NSMutableAttributedString(attributedString: attributedString)

        attributedString.enumerateAttributes(in: range, options: []) { attributes, range, _ in
            switch action {
            case .b:
                self.change(trait: .traitBold, to: active, attributes: attributes, at: range, in: mutableString)
            case .i:
                self.change(trait: .traitItalic, to: active, attributes: attributes, at: range, in: mutableString)
            case .sup:
                self.change(superscript: true, to: active, attributes: attributes, at: range, in: mutableString)
            case .sub:
                self.change(superscript: false, to: active, attributes: attributes, at: range, in: mutableString)
            }
        }

        self.updateTextView(with: mutableString)
    }

    private func change(trait: UIFontDescriptor.SymbolicTraits, to active: Bool, attributes: [NSMutableAttributedString.Key: Any],
                        at range: NSRange, in string: NSMutableAttributedString) {
        let font = (attributes[.font] as? UIFont) ?? self.font
        var traits = font.fontDescriptor.symbolicTraits
        if traits.contains(trait) && !active {
            traits.remove(trait)
        } else if !traits.contains(trait) && active {
            traits.insert(trait)
        }
        string.addAttributes([.font: font.withTraits(traits)], range: range)
    }

    private func change(superscript: Bool, to active: Bool, attributes: [NSMutableAttributedString.Key: Any],
                        at range: NSRange, in string: NSMutableAttributedString) {
        let font = (attributes[.font] as? UIFont) ?? self.font
        let newFontSize = active ? StringAttribute.subOrSuperScriptFontSizeRatio * self.font.pointSize : self.font.pointSize
        if font.pointSize != newFontSize {
            string.addAttributes([.font: font.withSize(newFontSize)], range: range)
        }

        if active {
            let offsetRatio = superscript ? StringAttribute.superscriptFontOffset : StringAttribute.subscriptFontOffset
            let offset = self.font.pointSize * offsetRatio * (superscript ? 1 : -1)
            string.addAttributes([.baselineOffset: offset], range: range)
        } else {
            string.removeAttribute(.baselineOffset, range: range)
        }
    }

    private func updateTextView(with attributedString: NSAttributedString) {
        self.ignoreSelectionChange = true
        let range = self.textView.selectedRange
        self.textView.attributedText = attributedString
        self.textView.selectedRange = range
        self.ignoreSelectionChange = false
    }

    // MARK: - Setups

    private func setupToolbarButtons() {
        let buttons = ToolbarAction.allCases.map { action -> CheckboxButton in
            let imageName: String
            switch action {
            case .b:
                imageName = "bold"
            case .i:
                imageName = "italic"
            case .sup:
                imageName = "textformat.superscript"
            case .sub:
                imageName = "textformat.subscript"
            }

            let button = CheckboxButton()
            button.tag = action.rawValue
            button.setImage(UIImage(systemName: imageName), for: .normal)
            button.deselectedTintColor = .black
            button.selectedTintColor = .systemBlue
            button.widthAnchor.constraint(equalTo: button.heightAnchor).isActive = true
            button.setContentHuggingPriority(.required, for: .horizontal)

            button.rx
                  .controlEvent(.touchDown)
                  .subscribe(onNext: { [weak self, weak button] _ in
                      guard let `self` = self, let button = button else { return }
                      self.toggle(button: button)
                      let actions = self.activeActions
                      self.updateText(in: self.textView.selectedRange, with: action, active: button.isSelected)
                      self.setActive(actions: actions)

                  })
                  .disposed(by: self.disposeBag)

            return button
        }

        buttons.forEach { button in
            self.buttonToolbar.addArrangedSubview(button)
        }
        // add empty UIView to the end of stack view so that the last button doesn't try to fill the whole view
        self.buttonToolbar.addArrangedSubview(UIView())
    }

    private func setupTextView() {
        self.textView.font = self.font
        self.textView.attributedText = self.converter.convert(comment: self.text, baseFont: self.font)
        self.textView.delegate = self
    }
}

extension AnnotationCommentEditorViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        self.ignoreSelectionChange = true
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        self.ignoreSelectionChange = false
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !self.ignoreSelectionChange else { return }
        self.selectActiveButtons(in: textView.selectedRange)
    }
}
