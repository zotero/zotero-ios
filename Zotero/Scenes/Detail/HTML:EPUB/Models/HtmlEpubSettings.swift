//
//  HtmlEpubSettings.swift
//  Zotero
//
//  Created by Michal Rentka on 15.11.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKitUI

struct HtmlEpubSettings {
    var appearance: ReaderSettingsState.Appearance

    static var `default`: HtmlEpubSettings {
        return HtmlEpubSettings(appearance: .automatic)
    }
}

extension HtmlEpubSettings: ReaderSettings {
    var minimumPreferredContentSize: CGSize {
        return CGSize(width: 480, height: 92)
    }

    var rows: [ReaderSettingsViewController.Row] {
        return [.appearance]
    }

    // These don't apply to HTML/Epub, assign random values
    var transition: PageTransition {
        return .curl
    }
    
    var pageMode: PageMode {
        return .automatic
    }
    
    var direction: ScrollDirection {
        return .horizontal
    }
    
    var pageFitting: PDFConfiguration.SpreadFitting {
        return .adaptive
    }
    
    var isFirstPageAlwaysSingle: Bool {
        return true
    }
}

extension HtmlEpubSettings: Codable {
    enum Keys: String, CodingKey {
        case appearance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let appearanceRaw = try container.decode(UInt.self, forKey: .appearance)
        appearance = ReaderSettingsState.Appearance(rawValue: appearanceRaw) ?? .automatic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(appearance.rawValue, forKey: .appearance)
    }
}
