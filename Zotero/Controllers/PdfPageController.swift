//
//  PdfPageController.swift
//  Zotero
//
//  Created by Michal Rentka on 15/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

class PdfPageController {
    private static let pagesKey = "org.zotero.PdfPageController.Pages"
    private let defaults: UserDefaults

    private var pages: [String: Int]
    private var didChange: Bool
    
    init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        self.pages = (defaults.dictionary(forKey: PdfPageController.pagesKey) as? [String: Int]) ?? [:]
        self.didChange = false
    }
    
    func page(for key: String) -> Int {
        return self.pages[key] ?? 0
    }
    
    func store(page: Int, for key: String) {
        self.pages[key] = page
        self.didChange = true
    }
    
    func save() {
        guard self.didChange else { return }
        self.didChange = false
        self.defaults.set(self.pages, forKey: PdfPageController.pagesKey)
    }
}
