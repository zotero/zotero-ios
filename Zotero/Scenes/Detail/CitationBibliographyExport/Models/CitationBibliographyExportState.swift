//
//  CitationBibliographyExportState.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CitationBibliographyExportState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let finished = Changes(rawValue: 1 << 0)
    }

    enum Error: Swift.Error {
        case cantCreateData
    }

    enum Kind: Int {
        case cite
        case export
    }

    enum OutputMode: Int, Codable {
        case citation
        case bibliography
    }

    enum OutputMethod: Int, Identifiable, Codable {
        case html
        case copy

        var id: Int {
            return self.rawValue
        }
    }

    static let methods: [OutputMethod] = [.copy, .html]
    let itemIds: Set<String>
    let libraryId: LibraryIdentifier

    var type: Kind
    var isLoading: Bool
    var changes: Changes
    var error: Swift.Error?
    var outputFile: File?

    // Cite
    var citationSession: CitationController.Session?
    var localeId: String
    var localeName: String
    var languagePickerEnabled: Bool
    var style: Style
    var mode: OutputMode
    var method: OutputMethod

    // Export

    init(itemIds: Set<String>, libraryId: LibraryIdentifier, selectedStyle: Style, selectedLocaleId: String, languagePickerEnabled: Bool, selectedMode: OutputMode, selectedMethod: OutputMethod) {
        self.itemIds = itemIds
        self.libraryId = libraryId
        self.type = .cite
        self.localeId = selectedLocaleId
        self.localeName = Locale.current.localizedString(forIdentifier: selectedLocaleId) ?? selectedLocaleId
        self.languagePickerEnabled = languagePickerEnabled
        self.style = selectedStyle
        self.mode = selectedMode
        self.method = selectedMethod
        self.isLoading = false
        self.changes = []
    }

    mutating func cleanup() {
        self.error = nil
        self.changes = []
        self.outputFile = nil
    }
}
