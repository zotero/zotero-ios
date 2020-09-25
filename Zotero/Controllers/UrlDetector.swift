//
//  UrlDetector.swift
//  Zotero
//
//  Created by Michal Rentka on 26/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

class UrlDetector {
    private let detector: NSDataDetector?

    init() {
        do {
            self.detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch let error {
            DDLogError("UrlDetector: can't initialize - \(error)")
            self.detector = nil
        }
    }

    func isUrl(string: String) -> Bool {
        let utf16 = string.utf16
        if let match = self.detector?.firstMatch(in: string, options: [], range: NSRange(location: 0, length: utf16.count)) {
            // it is a link, if the match covers the whole string
            return match.range.length == utf16.count
        }
        return false
    }
}
