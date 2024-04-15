//
//  PDFSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 04.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKitUI

struct PDFSettings {
    var transition: PageTransition
    var pageMode: PageMode
    var direction: ScrollDirection
    var pageFitting: PDFConfiguration.SpreadFitting
    var appearanceMode: ReaderSettingsState.Appearance
    var idleTimerDisabled: Bool
    var isFirstPageAlwaysSingle: Bool

    static var `default`: PDFSettings {
        return PDFSettings(
            transition: .scrollContinuous,
            pageMode: .automatic,
            direction: .horizontal,
            pageFitting: .adaptive,
            appearanceMode: .automatic,
            idleTimerDisabled: false,
            isFirstPageAlwaysSingle: true
        )
    }
}

extension PDFSettings: Codable {
    enum Keys: String, CodingKey {
        case direction, transition, appearanceMode, pageMode, pageFitting, isFirstPageAlwaysSingle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let directionRaw = try container.decode(UInt.self, forKey: .direction)
        let transitionRaw = try container.decode(UInt.self, forKey: .transition)
        let appearanceRaw = try container.decode(UInt.self, forKey: .appearanceMode)
        let modeRaw = (try? container.decode(UInt.self, forKey: .pageMode)) ?? 2
        let fittingRaw = (try? container.decode(Int.self, forKey: .pageFitting)) ?? 2
        let isFirstPageAlwaysSingle = (try? container.decode(Bool.self, forKey: .isFirstPageAlwaysSingle)) ?? true

        self.direction = ScrollDirection(rawValue: directionRaw) ?? .horizontal
        self.transition = PageTransition(rawValue: transitionRaw) ?? .scrollPerSpread
        self.appearanceMode = ReaderSettingsState.Appearance(rawValue: appearanceRaw) ?? .automatic
        self.pageMode = PageMode(rawValue: modeRaw) ?? .automatic
        self.pageFitting = PDFConfiguration.SpreadFitting(rawValue: fittingRaw) ?? .adaptive
        self.isFirstPageAlwaysSingle = isFirstPageAlwaysSingle
        // This setting is not persisted, always defaults to false
        self.idleTimerDisabled = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(self.direction.rawValue, forKey: .direction)
        try container.encode(self.transition.rawValue, forKey: .transition)
        try container.encode(self.appearanceMode.rawValue, forKey: .appearanceMode)
        try container.encode(self.pageMode.rawValue, forKey: .pageMode)
        try container.encode(self.pageFitting.rawValue, forKey: .pageFitting)
        try container.encode(self.isFirstPageAlwaysSingle, forKey: .isFirstPageAlwaysSingle)
    }
}
