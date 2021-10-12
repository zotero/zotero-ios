//
//  WebDavPropParserDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class WebDavPropParserDelegate: NSObject, XMLParserDelegate {
    var mtime: Int?
    var fileHash: String?

    private var currentValue: String = ""

    private enum Element: String {
        case mtime
        case hash
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {}

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let element = Element(rawValue: elementName) {
            switch element {
            case .mtime:
                self.mtime = Int(self.currentValue)
            case .hash:
                self.fileHash = self.currentValue
            }
        }

        self.currentValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        self.currentValue += string
    }
}
