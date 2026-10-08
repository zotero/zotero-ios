//
//  DebugResponseParserDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 02.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class DebugResponseParserDelegate: NSObject, XMLParserDelegate {
    private(set) var reportId: String

    override init() {
        self.reportId = ""
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "reported":
            guard let reportId = attributeDict["reportID"] else { return }
            self.reportId = reportId

        default: break
        }
    }
}
