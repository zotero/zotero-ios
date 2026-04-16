//
//  FontPreferences.swift
//  Zotero
//
//  Created by Basil on 18.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

/// Manages font preferences globally and per-document
struct FontPreferences: Codable {
    /// Default font to use for all ebooks
    var defaultFont: String?
    
    /// Per-document font overrides (keyed by document identifier)
    var documentOverrides: [String: String]
    
    /// Default typesetting settings
    var defaultTypesetting: TypesettingSettings
    
    /// Per-document typesetting overrides
    var documentTypesettingOverrides: [String: TypesettingSettings]
    
    init() {
        self.defaultFont = nil
        self.documentOverrides = [:]
        self.defaultTypesetting = .default
        self.documentTypesettingOverrides = [:]
    }
    
    /// Get the font for a specific document
    func font(for documentKey: String) -> String? {
        return documentOverrides[documentKey] ?? defaultFont
    }
    
    /// Set font for a specific document
    mutating func setFont(_ font: String?, for documentKey: String) {
        if let font = font {
            documentOverrides[documentKey] = font
        } else {
            documentOverrides.removeValue(forKey: documentKey)
        }
    }
    
    /// Get typesetting settings for a specific document
    func typesettingSettings(for documentKey: String) -> TypesettingSettings {
        return documentTypesettingOverrides[documentKey] ?? defaultTypesetting
    }
    
    /// Set typesetting settings for a specific document
    mutating func setTypesettingSettings(_ settings: TypesettingSettings, for documentKey: String) {
        documentTypesettingOverrides[documentKey] = settings
    }
    
    /// Clear document-specific overrides
    mutating func clearOverrides(for documentKey: String) {
        documentOverrides.removeValue(forKey: documentKey)
        documentTypesettingOverrides.removeValue(forKey: documentKey)
    }
}
