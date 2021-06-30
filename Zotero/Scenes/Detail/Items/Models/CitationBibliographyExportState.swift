//
//  CitationBibliographyExportState.swift
//  Zotero
//
//  Created by Michal Rentka on 29.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CitationBibliographyExportState: ViewModelState {
    enum Kind: Int {
        case cite
        case export
    }

    enum OutputMode: Int {
        case citation
        case bibliography
    }

    enum OutputMethod: Int, Identifiable {
        case html
        case copy

        var id: Int {
            return self.rawValue
        }
    }

    static let methods: [OutputMethod] = [.html, .copy]

    var type: Kind

    // Cite
    var localeId: String
    var style: Style
    var mode: OutputMode
    var method: OutputMethod

    // Export

    init(selectedStyle: Style, selectedLocaleId: String) {
        self.type = .cite
        self.localeId = selectedLocaleId
        self.style = selectedStyle
        self.mode = .bibliography
        self.method = .copy
    }

    func cleanup() {}
}
