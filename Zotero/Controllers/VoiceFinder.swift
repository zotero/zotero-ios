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
            storedDefault: { language in
                guard let voiceId = Defaults.shared.defaultLocalVoiceForLanguage[language] else { return nil }
                return voices.first(where: { $0.identifier == voiceId })
            },
            voiceForLocale: { locale in
                voices.first(where: { $0.language == locale })
            }
        )
    }

    // MARK: - Remote Voices

    /// Finds a remote voice for the given language and tier.
    /// Uses a unified 6-step priority chain: stored default, exact match, canonical variation, device locale, canonical device locale, en-US fallback.
    static func findRemoteVoice(for language: String, tier: RemoteVoice.Tier, response: VoicesResponse) -> RemoteVoice? {
        guard let tierData = response.tiers[tier], !tierData.isEmpty else { return nil }
        return findVoice(
            for: language,
            storedDefault: { language in
                let savedVoices = tier == .premium
                    ? Defaults.shared.defaultPremiumRemoteVoiceForLanguage
                    : Defaults.shared.defaultStandardRemoteVoiceForLanguage
                guard let savedVoice = savedVoices[language], savedVoice.tier == tier, tierData.first(where: { $0.voices[savedVoice.id] != nil }) != nil else { return nil }
                return savedVoice
            },
            voiceForLocale: { locale in
                for data in tierData {
                    if let locale = data.locales[locale], (!locale.default.isEmpty || !locale.other.isEmpty) {
                        let voiceId: String
                        if !locale.default.isEmpty {
                            voiceId = locale.default[0]
                        } else {
                            voiceId = locale.other[0]
                        }
                        let label = data.voices[voiceId] ?? ""
                        return RemoteVoice(id: voiceId, label: label, creditsPerMinute: data.creditsPerMinute, granularity: data.sentenceGranularity, sentenceDelay: data.sentenceDelay, tier: tier)
                    }
                }
                return nil
            }
        )
    }

    /// Filters remote voices by language and tier.
    static func remoteVoices(for language: String, tier: RemoteVoice.Tier, from voices: [RemoteVoice]) -> [RemoteVoice] {
        // TODO: - remove
        return []
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
        storedDefault: (String) -> V?,
        voiceForLocale: (String) -> V?
    ) -> V? {
        // 1. Stored default
        if let voice = storedDefault(language) {
            return voice
        }

        let baseLanguage = String(language.prefix(while: { $0 != "-" }))

        // 2. Exact variation match
        if let voice = voiceForLocale(language) {
            return voice
        }

        // 3. Canonical variation
        if let canonical = LanguageDetector.canonicalVariation(for: baseLanguage), canonical != language,
           let voice = voiceForLocale(canonical) {
            return voice
        }

        // 4. Device locale
        let deviceLocale = LanguageDetector.deviceLocale
        if deviceLocale != language, let voice = voiceForLocale(deviceLocale) {
            return voice
        }

        // 5. Canonical variation of device locale's base language
        let deviceBase = String(deviceLocale.prefix(while: { $0 != "-" }))
        if deviceBase != baseLanguage,
           let canonicalDevice = LanguageDetector.canonicalVariation(for: deviceBase), canonicalDevice != deviceLocale,
           let voice = voiceForLocale(canonicalDevice) {
            return voice
        }

        // 6. en-US fallback
        return voiceForLocale("en-US")
    }
}
