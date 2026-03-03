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

    /// Filters local voices by exact locale.
    static func localVoices(for language: String) -> [AVSpeechSynthesisVoice] {
        filterLocalVoices { $0.language == language }
    }

    /// Filters local voices by base language, matching all locales starting with that base.
    static func localVoices(forBaseLanguage baseLanguage: String) -> [AVSpeechSynthesisVoice] {
        filterLocalVoices { Self.baseLanguage(of: $0.language) == baseLanguage }
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
                guard let savedVoice = savedVoices[language], savedVoice.tier == tier, tierData.contains(where: { $0.voices[savedVoice.id] != nil }) else { return nil }
                return savedVoice
            },
            voiceForLocale: { locale in
                for data in tierData {
                    if let localeData = data.locales[locale], !localeData.default.isEmpty || !localeData.other.isEmpty {
                        let voiceId = localeData.default.first ?? localeData.other[0]
                        return data.makeVoice(id: voiceId, tier: tier)
                    }
                }
                return nil
            }
        )
    }

    /// Filters remote voices by exact locale and tier.
    /// Takes a full locale (e.g., "en-US") and matches that exact locale in the tier data.
    static func remoteVoices(for language: String, tier: RemoteVoice.Tier, fromResponse response: VoicesResponse) -> [RemoteVoice] {
        guard let tierData = response.tiers[tier] else { return [] }
        var seen: Set<String> = []
        var result: [RemoteVoice] = []
        for data in tierData {
            guard let localeData = data.locales[language] else { continue }
            for voiceId in (localeData.default + localeData.other) where !seen.contains(voiceId) {
                seen.insert(voiceId)
                result.append(data.makeVoice(id: voiceId, tier: tier))
            }
        }
        return result.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    // MARK: - Helpers

    /// Extracts the display name for a locale variation (e.g., "en-US" → "United States").
    static func variationName(for languageCode: String, baseLanguage: String) -> String {
        let locale = Locale.current
        guard let localized = locale.localizedString(forIdentifier: languageCode) else { return languageCode }
        guard let localizedLanguage = locale.localizedString(forLanguageCode: baseLanguage), localized.hasPrefix(localizedLanguage) else { return localized }
        let suffix = String(localized[localized.index(localized.startIndex, offsetBy: localizedLanguage.count)..<localized.endIndex])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
        return suffix.isEmpty ? localized : suffix
    }

    // MARK: - Private

    /// Extracts the base language code from a locale string (e.g., "en-US" → "en").
    private static func baseLanguage(of locale: String) -> String {
        String(locale.prefix(while: { $0 != "-" }))
    }

    /// Filters and sorts system local voices by a predicate.
    private static func filterLocalVoices(matching predicate: (AVSpeechSynthesisVoice) -> Bool) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter(predicate)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

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

        let base = baseLanguage(of: language)

        // 2. Exact variation match
        if let voice = voiceForLocale(language) {
            return voice
        }

        // 3. Canonical variation
        if let canonical = LanguageDetector.canonicalVariation(for: base), canonical != language,
           let voice = voiceForLocale(canonical) {
            return voice
        }

        // 4. Device locale
        let deviceLocale = LanguageDetector.deviceLocale
        if deviceLocale != language, let voice = voiceForLocale(deviceLocale) {
            return voice
        }

        // 5. Canonical variation of device locale's base language
        let deviceBase = baseLanguage(of: deviceLocale)
        if deviceBase != base,
           let canonicalDevice = LanguageDetector.canonicalVariation(for: deviceBase), canonicalDevice != deviceLocale,
           let voice = voiceForLocale(canonicalDevice) {
            return voice
        }

        // 6. en-US fallback
        return voiceForLocale("en-US")
    }
}

// MARK: - VoicesResponse.Data convenience

private extension VoicesResponse.Data {
    func makeVoice(id: String, tier: RemoteVoice.Tier) -> RemoteVoice {
        RemoteVoice(id: id, label: voices[id] ?? "", creditsPerMinute: creditsPerMinute, granularity: sentenceGranularity, sentenceDelay: sentenceDelay, tier: tier)
    }
}
