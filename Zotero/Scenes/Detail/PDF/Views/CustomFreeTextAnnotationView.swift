//
//  CustomFreeTextAnnotationView.swift
//  Zotero
//
//  Created by Michal Rentka on 02.08.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import PSPDFKitUI

protocol FreeTextInputDelegate: AnyObject {
    func showColorPicker(sender: UIView)
    func showFontSizePicker(sender: UIView)
    func changeFontSize(size: UInt)
}

final class CustomFreeTextAnnotationView: FreeTextAnnotationView {
    weak var delegate: FreeTextInputDelegate?

    override func textViewForEditing() -> UITextView {
        let textView = super.textViewForEditing()
        textView.inputAccessoryView = FreeTextInputAccessory()
        return textView
    }
}

final class FreeTextInputAccessory: UIView {
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        self.autoresizingMask = .flexibleWidth
        self.backgroundColor = .systemBackground
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
