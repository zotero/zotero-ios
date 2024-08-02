//
//  FormattedTextView.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 1/8/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import RxSwift

final class FormattedTextView: TextKit1TextView {
    private static let allowedActions: [String] = ["cut:", "copy:", "paste:", "toggleBoldface:", "toggleItalics:", "toggleSuperscript", "toggleSubscript", "replace:"]

    private let defaultFont: UIFont
    private let menuItems: [UIMenuItem]
    private let disposeBag: DisposeBag

    init(defaultFont: UIFont) {
        self.defaultFont = defaultFont
        menuItems = createMenuItems()
        disposeBag = DisposeBag()
        super.init(frame: CGRect(), textContainer: nil)
        font = defaultFont
        setupObservers()

        func createMenuItems() -> [UIMenuItem] {
            let bold = UIMenuItem(title: "Bold", action: #selector(Self.toggleBoldface(_:)))
            let italics = UIMenuItem(title: "Italics", action: #selector(Self.toggleItalics(_:)))
            let superscript = UIMenuItem(title: "Superscript", action: #selector(Self.toggleSuperscript))
            let `subscript` = UIMenuItem(title: "Subscript", action: #selector(Self.toggleSubscript))
            return [bold, italics, superscript, `subscript`]
        }
        
        func setupObservers() {
            NotificationCenter.default
                .rx
                .notification(Self.textDidBeginEditingNotification)
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let self else { return }
                    UIMenuController.shared.menuItems = menuItems
                })
                .disposed(by: disposeBag)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return Self.allowedActions.contains(action.description)
    }

    @objc func toggleSuperscript() {
        guard selectedRange.length > 0 else { return }
        perform(attributedStringAction: { StringAttribute.toggleSuperscript(in: $0, range: $1, defaultFont: defaultFont) })
    }

    @objc func toggleSubscript() {
        guard selectedRange.length > 0 else { return }
        perform(attributedStringAction: { StringAttribute.toggleSubscript(in: $0, range: $1, defaultFont: defaultFont) })
    }

    private func perform(attributedStringAction: (NSMutableAttributedString, NSRange) -> Void) {
        let range = selectedRange
        let string = NSMutableAttributedString(attributedString: attributedText)
        attributedStringAction(string, range)
        attributedText = string
        selectedRange = range
        delegate?.textViewDidChange?(self)
    }
}
