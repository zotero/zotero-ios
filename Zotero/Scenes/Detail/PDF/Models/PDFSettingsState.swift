//
//  PDFSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 04.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

#if PDFENABLED

import PSPDFKitUI

struct PDFSettingsState {
    var direction: ScrollDirection
    var transition: PageTransition
    var appearanceMode: PDFReaderState.AppearanceMode

    static var `default`: PDFSettingsState {
        return PDFSettingsState(direction: .horizontal, transition: .scrollContinuous, appearanceMode: .automatic)
    }
}

extension PDFSettingsState: Codable {
    enum Keys: String, CodingKey {
        case direction, transition, appearanceMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let directionRaw = try container.decode(UInt.self, forKey: .direction)
        let transitionRaw = try container.decode(UInt.self, forKey: .transition)
        let appearanceRaw = try container.decode(UInt.self, forKey: .appearanceMode)

        self.direction = ScrollDirection(rawValue: directionRaw) ?? .horizontal
        self.transition = PageTransition(rawValue: transitionRaw) ?? .scrollPerSpread
        self.appearanceMode = PDFReaderState.AppearanceMode(rawValue: appearanceRaw) ?? .automatic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(self.direction.rawValue, forKey: .direction)
        try container.encode(self.transition.rawValue, forKey: .transition)
        try container.encode(self.appearanceMode.rawValue, forKey: .appearanceMode)
    }
}

#endif
