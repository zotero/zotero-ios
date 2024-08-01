//
//  AnnotationTextView.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 1/8/24.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class AnnotationTextView: TextKit1TextView {
    private static let allowedActions: [String] = ["cut:", "copy:", "paste:", "toggleBoldface:", "toggleItalics:", "toggleSuperscript", "toggleSubscript", "replace:"]

    private let defaultFont: UIFont

    init(defaultFont: UIFont) {
        self.defaultFont = defaultFont
        super.init(frame: CGRect(), textContainer: nil)
        font = defaultFont
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
