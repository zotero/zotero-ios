//
//  VoiceFinder.swift
//  Zotero
//
//  Created by Michal Rentka on 20.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFoundation

/// Utility for finding voices based on language and user preferences.
/// Centralizes voice lookup logic used by both SpeechManager and SpeechVoicePickerView.
enum VoiceFinder {
    // MARK: - Local Voices

    /// Finds a local voice for the given language.
    /// Priority: 1. User's saved default voice, 2. Exact locale match, 3. Base language match, 4. en-US fallback
    static func findLocalVoice(for language: String, from voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()) -> AVSpeechSynthesisVoice? {
        // First check if user has a saved voice for this exact language
        if let voiceId = Defaults.shared.defaultLocalVoiceForLanguage[language],
           let savedVoice = voices.first(where: { $0.identifier == voiceId }) {
            return savedVoice
        }
        
        // Try to find exact locale match
        if let exactMatch = voices.first(where: { $0.language == language }) {
            return exactMatch
        }
        
        // Fall back to any voice matching the base language
        let baseLanguage = String(language.prefix(2))
        if let baseMatch = voices.first(where: { $0.language.hasPrefix(baseLanguage) }) {
            return baseMatch
        }
        
        // Ultimate fallback to en-US or first available
        return voices.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - Remote Voices

    /// Finds a remote voice for the given language and tier.
    /// Priority: 1. User's saved default voice for tier, 2. Exact locale match, 3. Base language match, 4. First available
    static func findRemoteVoice(for language: String, tier: RemoteVoice.Tier, from voices: [RemoteVoice]) -> RemoteVoice? {
        // Check if user has a saved voice for this language and tier
        let savedVoices = tier == .premium
            ? Defaults.shared.defaultPremiumRemoteVoiceForLanguage
            : Defaults.shared.defaultStandardRemoteVoiceForLanguage
        if let savedVoice = savedVoices[language], savedVoice.tier == tier, voices.contains(where: { $0.id == savedVoice.id }) {
            return savedVoice
        }
        
        // Try to find exact locale match
        if let exactMatch = voices.first(where: { $0.tier == tier && $0.locales.contains(language) }) {
            return exactMatch
        }
        
        // Fall back to any voice matching the base language
        let baseLanguage = String(language.prefix(2))
        if let baseMatch = voices.first(where: { voice in
            return voice.tier == tier && voice.locales.contains(where: { $0.hasPrefix(baseLanguage) })
        }) {
            return baseMatch
        }
        
        // Ultimate fallback to first available voice in tier
        return voices.first(where: { $0.tier == tier })
    }

    /// Filters remote voices by language and tier.
    static func remoteVoices(for language: String, tier: RemoteVoice.Tier, from voices: [RemoteVoice]) -> [RemoteVoice] {
        return voices.filter { voice in
            voice.tier == tier && voice.locales.contains(where: { $0 == language })
        }
    }

    /// Filters local voices by language.
    static func localVoices(for language: String) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
