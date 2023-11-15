//
//  HtmlEpubSettings.swift
//  Zotero
//
//  Created by Michal Rentka on 15.11.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct HtmlEpubSettings {
    var interfaceStyle: UIUserInterfaceStyle
    var idleTimerDisabled: Bool

    static var `default`: HtmlEpubSettings {
        return HtmlEpubSettings(interfaceStyle: .unspecified, idleTimerDisabled: false)
    }
}

extension HtmlEpubSettings: Codable {
    enum Keys: String, CodingKey {
        case interfaceStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let interfaceStyleRaw = try container.decode(Int.self, forKey: .interfaceStyle)
        self.interfaceStyle = UIUserInterfaceStyle(rawValue: interfaceStyleRaw) ?? .unspecified
        // This setting is not persisted, always defaults to false
        self.idleTimerDisabled = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(self.interfaceStyle.rawValue, forKey: .interfaceStyle)
    }
}
