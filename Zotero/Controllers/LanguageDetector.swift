//
//  LanguageDetector.swift
//  Zotero
//
//  Created by Michal Rentka on 19.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import NaturalLanguage

/// Detects language with regional variation from text.
/// NLLanguageRecognizer only detects base language (e.g., "en"), not regional variations (e.g., "en-US").
/// This utility adds variation detection using device locale fallback and prominent variation defaults.
enum LanguageDetector {
    /// Default/prominent variations for languages that have multiple regional variants.
    /// These are commonly used variations that serve as reasonable defaults.
    private static let prominentVariations: [String: String] = [
        "en": "en-US",
        "es": "es-ES",
        "pt": "pt-BR",
        "zh": "zh-CN",
        "fr": "fr-FR",
        "de": "de-DE",
        "ar": "ar-SA",
        "nl": "nl-NL"
    ]
    
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
    /// then to the first available system voice locale for that language.
    /// - Parameter baseLanguage: The base language code (e.g., "en")
    /// - Returns: A locale string with variation (e.g., "en-US")
    static func resolveVariation(for baseLanguage: String) -> String {
        // Get all available variations for this language from system voices
        let systemLocales = AVSpeechSynthesisVoice.speechVoices().map { $0.language }
        let availableVariations = systemLocales.filter { $0.hasPrefix(baseLanguage) }
        
        // If no variations available, fall back to en-US
        guard !availableVariations.isEmpty else {
            return "en-US"
        }
        
        // If only one variation exists, return it directly
        if availableVariations.count == 1 {
            return availableVariations[0]
        }
        
        // Check if device locale matches the base language - if so, use device's variation
        let deviceLocale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        let deviceBaseLanguage = String(deviceLocale.prefix(2))
        if deviceBaseLanguage == baseLanguage, availableVariations.contains(deviceLocale) {
            return deviceLocale
        }
        
        // Use prominent variation if available
        if let prominentVariation = prominentVariations[baseLanguage], availableVariations.contains(prominentVariation) {
            return prominentVariation
        }
        
        // Fall back to first available variation
        return availableVariations[0]
    }
}
