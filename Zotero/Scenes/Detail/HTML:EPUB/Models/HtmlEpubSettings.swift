//
//  HtmlEpubSettings.swift
//  Zotero
//
//  Created by Michal Rentka on 15.11.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct HtmlEpubSettings {
    var appearance: ReaderSettingsState.Appearance
    var idleTimerDisabled: Bool

    static var `default`: HtmlEpubSettings {
        return HtmlEpubSettings(appearance: .automatic, idleTimerDisabled: false)
    }
}

extension HtmlEpubSettings: Codable {
    enum Keys: String, CodingKey {
        case appearance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let appearanceRaw = try container.decode(UInt.self, forKey: .appearance)
        self.appearance = ReaderSettingsState.Appearance(rawValue: appearanceRaw) ?? .automatic
        // This setting is not persisted, always defaults to false
        self.idleTimerDisabled = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(self.appearance.rawValue, forKey: .appearance)
    }
}
