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
    private var dependencyHref: String?
    private var supportsCitation: Bool
    private var supportsBibliography: Bool
    private var isNoteStyle: Bool
    private var defaultLocale: String?

    private enum Element: String {
        case identifier = "id"
        case title = "title"
        case updated = "updated"
        case link = "link"
        case citation = "citation"
        case bibliography = "bibliography"
        case style = "style"
    }

    init(filename: String?) {
        self.filename = filename
        self.supportsCitation = false
        self.supportsBibliography = false
        self.isNoteStyle = false
        self.currentValue = ""
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard let element = Element(rawValue: elementName) else { return }

        switch element {
        case .link:
            if let rel = attributeDict["rel"] {
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

        case .style:
            if let locale = attributeDict["default-locale"] {
                self.defaultLocale = locale
            }
            if let classValue = attributeDict["class"] {
                self.isNoteStyle = classValue == "note"
            }

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

        case .link, .style: break
        }

        self.currentValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        self.currentValue += string
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        guard self.supportsCitation || self.dependencyHref != nil else {
            DDLogError("Style \"\(self.identifier ?? "unknown id")\"; \"\(self.filename ?? self.href?.lastPathComponent ?? "unknown filename")\" doesn't support citation")
            return
        }
        guard let identifier = self.identifier, let title = self.title, let updated = self.updated, let href = self.href else { return }
        self.style = Style(identifier: identifier, dependencyId: self.dependencyHref, title: title, updated: updated, href: href, filename: (self.filename ?? href.lastPathComponent),
                           supportsBibliography: self.supportsBibliography, isNoteStyle: self.isNoteStyle, defaultLocale: self.defaultLocale)
    }
}
