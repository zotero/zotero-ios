//
//  RepoParserDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 26/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class RepoParserDelegate: NSObject, XMLParserDelegate {
    private(set) var translators: [Translator]
    private(set) var styles: [(String, String)]
    private(set) var timestamp: Int
    private var currentTranslator: Translator?
    private var currentValue: String
    private var currentStyleId: String?

    private enum Element: String {
        case timestamp = "currentTime"
        case translator = "translator"
        case priority = "priority"
        case label = "label"
        case creator = "creator"
        case target = "target"
        case code = "code"
        case style = "style"

        var isTranslatorMetadata: Bool {
            switch self {
            case .timestamp, .translator, .style:
                return false
            case .priority, .label, .creator, .target, .code:
                return true
            }
        }
    }

    override init() {
        self.translators = []
        self.styles = []
        self.timestamp = 0
        self.currentValue = ""
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard let element = Element(rawValue: elementName) else { return }
        switch element {
        case .translator:
            self.currentTranslator = Translator(metadata: attributeDict, code: "")
        case .style:
            self.currentStyleId = attributeDict["id"]
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let element = Element(rawValue: elementName) {
            switch element {
            case .timestamp:
                self.timestamp = Int(self.currentValue) ?? 0
            case .translator:
                if let translator = self.currentTranslator {
                    self.translators.append(translator)
                    self.currentTranslator = nil
                }
            case .code:
                self.currentTranslator = self.currentTranslator?.withCode(self.currentValue)
            case .creator, .label, .priority, .target:
                self.currentTranslator = self.currentTranslator?.withMetadata(key: element.rawValue, value: self.currentValue)
            case .style:
                if let id = self.currentStyleId {
                    self.styles.append((id, self.currentValue))
                }
            }
        }

        self.currentValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        self.currentValue += string
    }
}
