//
//  ExportState.swift
//  Zotero
//
//  Created by Michal Rentka on 11.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ExportState: ViewModelState {
    var selectedStyle: String
    var selectedLanguage: String
    var languagePickerEnabled: Bool
    var copyAsHtml: Bool

    init(style: String, language: String, languagePickerEnabled: Bool, copyAsHtml: Bool) {
        self.selectedStyle = style
        self.selectedLanguage = language
        self.languagePickerEnabled = languagePickerEnabled
        self.copyAsHtml = copyAsHtml
    }

    func cleanup() {}
}
