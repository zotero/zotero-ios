//
//  LanguageDetector.swift
//  Zotero
//
//  Created by Michal Rentka on 19.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import NaturalLanguage

/// Detects language with regional variation from text.
/// NLLanguageRecognizer only detects base language (e.g., "en"), not regional variations (e.g., "en-US").
/// This utility adds variation detection using device locale fallback and prominent variation defaults.
enum LanguageDetector {
    /// Returns the canonical variation for a base language using CLDR likely subtags.
    /// e.g., "en" -> "en-US", "pt" -> "pt-BR", "zh" -> "zh-CN"
    static func canonicalVariation(for baseLanguage: String) -> String? {
        let language = Locale.Language(identifier: baseLanguage)
        let maximal = Locale.Language(identifier: language.maximalIdentifier)
        guard let region = maximal.region else { return nil }
        return "\(baseLanguage)-\(region.identifier)"
    }

    /// Device locale formatted with dashes (e.g. "en-US").
    static var deviceLocale: String {
        Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    /// Detects language with variation from the given text.
    /// - Parameter text: The text to analyze
    /// - Returns: A locale string with variation (e.g., "en-US")
    static func detectLanguage(from text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let baseLanguage = recognizer.dominantLanguage?.rawValue ?? "en"
        return resolveVariation(for: baseLanguage)
    }
    
    /// Resolves a base language to a specific variation.
    /// Uses device locale if it matches the base language, otherwise falls back to prominent variations,
    /// then to the first available system locale for that language.
    /// - Parameter baseLanguage: The base language code (e.g., "en")
    /// - Returns: A locale string with variation (e.g., "en-US")
    static func resolveVariation(for baseLanguage: String) -> String {
        // Get all available variations for this language from known system locales
        let availableVariations = Locale.availableIdentifiers
            .map { $0.replacingOccurrences(of: "_", with: "-") }
            .filter { $0.hasPrefix(baseLanguage + "-") }
        
        // If no variations available, fall back to en-US
        guard !availableVariations.isEmpty else {
            return "en-US"
        }
        
        // If only one variation exists, return it directly
        if availableVariations.count == 1 {
            return availableVariations[0]
        }
        
        // Check if device locale matches the base language - if so, use device's variation
        let deviceLocale = self.deviceLocale
        let deviceBaseLanguage = String(deviceLocale.prefix(2))
        if deviceBaseLanguage == baseLanguage, availableVariations.contains(deviceLocale) {
            return deviceLocale
        }

        // Use canonical variation if available
        if let canonicalVariation = canonicalVariation(for: baseLanguage), availableVariations.contains(canonicalVariation) {
            return canonicalVariation
        }
        
        // Fall back to first available variation
        return availableVariations[0]
    }
}
