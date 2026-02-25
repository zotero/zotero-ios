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
    /// Uses a unified 6-step priority chain: stored default, exact match, canonical variation, device locale, canonical device locale, en-US fallback.
    static func findLocalVoice(for language: String, from voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()) -> AVSpeechSynthesisVoice? {
        return findVoice(
            for: language,
            from: voices,
            storedDefault: { language, voices in
                guard let voiceId = Defaults.shared.defaultLocalVoiceForLanguage[language] else { return nil }
                return voices.first(where: { $0.identifier == voiceId })
            },
            matchesLocale: { voice, locale in
                voice.language == locale
            }
        )
    }

    // MARK: - Remote Voices

    /// Finds a remote voice for the given language and tier.
    /// Uses a unified 6-step priority chain: stored default, exact match, canonical variation, device locale, canonical device locale, en-US fallback.
    static func findRemoteVoice(for language: String, tier: RemoteVoice.Tier, from voices: [RemoteVoice]) -> RemoteVoice? {
        let tierVoices = voices.filter { $0.tier == tier }
        return findVoice(
            for: language,
            from: tierVoices,
            storedDefault: { language, voices in
                let savedVoices = tier == .premium
                    ? Defaults.shared.defaultPremiumRemoteVoiceForLanguage
                    : Defaults.shared.defaultStandardRemoteVoiceForLanguage
                guard let savedVoice = savedVoices[language], savedVoice.tier == tier, voices.contains(where: { $0.id == savedVoice.id }) else { return nil }
                return savedVoice
            },
            matchesLocale: { voice, locale in
                voice.locales.contains(locale)
            }
        )
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

    // MARK: - Private

    /// Unified 6-step voice selection chain.
    /// 1. Stored default
    /// 2. Exact variation match
    /// 3. Canonical variation (CLDR likely subtags)
    /// 4. Device locale
    /// 5. Canonical variation of device locale's base language
    /// 6. en-US fallback
    private static func findVoice<V>(
        for language: String,
        from voices: [V],
        storedDefault: (String, [V]) -> V?,
        matchesLocale: (V, String) -> Bool
    ) -> V? {
        // 1. Stored default
        if let voice = storedDefault(language, voices) {
            return voice
        }

        let baseLanguage = String(language.prefix(while: { $0 != "-" }))

        // 2. Exact variation match
        if let voice = voices.first(where: { matchesLocale($0, language) }) {
            return voice
        }

        // 3. Canonical variation
        if let canonical = LanguageDetector.canonicalVariation(for: baseLanguage), canonical != language,
           let voice = voices.first(where: { matchesLocale($0, canonical) }) {
            return voice
        }

        // 4. Device locale
        let deviceLocale = LanguageDetector.deviceLocale
        if deviceLocale != language, let voice = voices.first(where: { matchesLocale($0, deviceLocale) }) {
            return voice
        }

        // 5. Canonical variation of device locale's base language
        let deviceBase = String(deviceLocale.prefix(while: { $0 != "-" }))
        if deviceBase != baseLanguage,
           let canonicalDevice = LanguageDetector.canonicalVariation(for: deviceBase), canonicalDevice != deviceLocale,
           let voice = voices.first(where: { matchesLocale($0, canonicalDevice) }) {
            return voice
        }

        // 6. en-US fallback
        return voices.first(where: { matchesLocale($0, "en-US") })
    }
}
