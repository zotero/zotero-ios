//
//  StyleParserDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 03.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

final class StyleParserDelegate: NSObject, XMLParserDelegate {
    private let filename: String?

    private(set) var style: Style?
    private var currentValue: String
    private var identifier: String?
    private var title: String?
    private var updated: Date?
    private var href: URL?
    private(set) var dependencyHref: String?
    private var supportsCitation: Bool
    private var supportsBibliography: Bool

    private enum Element: String {
        case identifier = "id"
        case title = "title"
        case updated = "updated"
        case link = "link"
        case citation = "citation"
        case bibliography = "bibliography"
    }

    init(filename: String?) {
        self.filename = filename
        self.supportsCitation = false
        self.supportsBibliography = false
        self.currentValue = ""
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        guard Element(rawValue: elementName) == .link, let rel = attributeDict["rel"] else { return }

        switch rel {
        case "self":
            if self.href == nil, let href = attributeDict["href"] {
                self.href = URL(string: href)
            }
        case "independent-parent":
            self.dependencyHref = attributeDict["href"]
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let element = Element(rawValue: elementName) else {
            self.currentValue = ""
            return
        }

        self.currentValue = self.currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch element {
        case .identifier:
            self.identifier = self.currentValue
        case .title:
            self.title = self.currentValue
        case .updated:
            self.updated = Formatter.iso8601.date(from: self.currentValue)
        case .citation:
            self.supportsCitation = true
        case .bibliography:
            self.supportsBibliography = true
        case .link: break
        }

        self.currentValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        self.currentValue += string
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        guard self.supportsCitation else {
            DDLogError("Style \"\(self.identifier ?? "unknown id")\"; \"\(self.filename ?? self.href?.lastPathComponent ?? "unknown filename")\" doesn't support citation")
            return
        }
        guard let identifier = self.identifier, let title = self.title, let updated = self.updated, let href = self.href else { return }
        self.style = Style(identifier: identifier, title: title, updated: updated, href: href, filename: (self.filename ?? href.lastPathComponent), supportsBibliography: self.supportsBibliography)
    }
}
