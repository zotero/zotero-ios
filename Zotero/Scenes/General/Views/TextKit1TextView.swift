//
//  TextKit1TextView.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 7/7/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class TextKit1TextView: UITextView {
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        forceTextKit1()
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        forceTextKit1()
    }
    
    private func forceTextKit1() {
        // Accessing textView layoutManager to force use of TextKit 1,
        // to avoid scribble insert crash per https://developer.apple.com/forums/thread/724216
        _ = layoutManager
    }
}
