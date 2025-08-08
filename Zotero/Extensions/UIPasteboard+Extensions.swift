//
//  UIPasteboard+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 27.08.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

import CocoaLumberjackSwift

extension UIPasteboard {
    func copy(html: String, plainText: String) {
        var item: [String: Any] = [UTType.plainText.identifier: plainText, UTType.html.identifier: html]

        if let htmlData = html.data(using: .utf8) {
            do {
                item[UTType.rtf.identifier] = try Data.convertHTMLToRTF(htmlData: htmlData)
            } catch let error {
                DDLogError("UIPasteboard: can't convert html to attributed string or rtf - \(error)")
            }
        }

        UIPasteboard.general.items = [item]
    }
}

extension Data {
    static func convertHTMLToRTF(htmlData: Data) throws -> Data {
        let attrString = try NSAttributedString(data: htmlData, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        return try attrString.data(from: NSRange(location: 0, length: attrString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}
