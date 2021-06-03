//
//  StyleParserDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 03.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class StyleParserDelegate: NSObject, XMLParserDelegate {
    private static let idPrefix = "http://www.zotero.org/styles/"

    private(set) var style: CitationStyle?

    private var currentValue: String

    private var identifier: String?
    private var title: String?
    private var updated: Date?
    private var href: String?

    private enum Element: String {
        case identifier = "id"
        case title = "title"
        case updated = "updated"
    }

    override init() {
        self.currentValue = ""
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {}

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard self.style == nil else { return }

        self.currentValue = self.currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let element = Element(rawValue: elementName) {
            switch element {
            case .identifier:
                self.href = self.currentValue
                self.identifier = String(self.currentValue[self.currentValue.index(self.currentValue.startIndex, offsetBy: StyleParserDelegate.idPrefix.count)...])
            case .title:
                self.title = self.currentValue
            case .updated:
                self.updated = Formatter.iso8601.date(from: self.currentValue)
            }
        }

        self.currentValue = ""

        if let identifier = self.identifier, let title = self.title, let updated = self.updated, let href = self.href {
            self.style = CitationStyle(identifier: identifier, title: title, updated: updated, href: href)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard self.style == nil else { return }
        self.currentValue += string
    }
}
