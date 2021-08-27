//
//  UIPasteboard+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 27.08.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import MobileCoreServices
import UIKit

import CocoaLumberjackSwift

extension UIPasteboard {
    func copy(html: String, plaintext: String) {
        guard let htmlData = html.data(using: .utf8) else {
            DDLogError("UIPasteboard: can't convert html string to data")
            UIPasteboard.general.string = plaintext
            return
        }

        var item: [String: Any] = [(kUTTypePlainText as String): plaintext, (kUTTypeHTML as String): htmlData]

        do {
            let attrString = try NSAttributedString(data: htmlData, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
            let data = try attrString.data(from: NSMakeRange(0, attrString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            item[kUTTypeRTF as String] = data
        } catch let error {
            DDLogError("UIPasteboard: can't convert html to attributed string or rtf - \(error)")
        }

        UIPasteboard.general.items = [item]
    }
}
