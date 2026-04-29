//
//  VoiceUtility.swift
//  Zotero
//
//  Created by Michal Rentka on 20.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFoundation

/// Utility for finding, filtering, grouping voices and building language lists.
/// Centralizes voice logic used by SpeechManager, SpeechVoicePickerView, and ReadAloudOnboardingView.
enum VoiceUtility {
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
        return result
    }

    // MARK: - Grouping

    /// Groups remote voices by locale into display groups.
    static func groupRemoteVoices(locales: [String], tier: RemoteVoice.Tier, baseLanguage: String, response: VoicesResponse) -> [LocaleRemoteVoiceGroup] {
        locales.compactMap { locale in
            let voices = remoteVoices(for: locale, tier: tier, fromResponse: response)
            guard !voices.isEmpty else { return nil }
            return LocaleRemoteVoiceGroup(locale: locale, displayName: variationName(for: locale, baseLanguage: baseLanguage), voices: voices)
        }
    }

    /// Groups local voices by locale into display groups.
    static func groupLocalVoices(_ voices: [AVSpeechSynthesisVoice], baseLanguage: String) -> [LocaleLocalVoiceGroup] {
        var localeVoicesMap: [String: [AVSpeechSynthesisVoice]] = [:]
        for voice in voices {
            localeVoicesMap[voice.language, default: []].append(voice)
        }
        return localeVoicesMap.keys.sorted().compactMap { locale in
            guard let voices = localeVoicesMap[locale], !voices.isEmpty else { return nil }
            return LocaleLocalVoiceGroup(locale: locale, displayName: variationName(for: locale, baseLanguage: baseLanguage), voices: voices)
        }
    }

    /// Returns all locales for a base language within a given tier.
    static func remoteLocales(forBaseLanguage base: String, tier: RemoteVoice.Tier, response: VoicesResponse) -> [String] {
        guard let tierData = response.tiers[tier] else { return [] }
        var locales: Set<String> = []
        for data in tierData {
            for locale in data.locales.keys where String(locale.prefix(while: { $0 != "-" })) == base {
                locales.insert(locale)
            }
        }
        return locales.sorted()
    }

    /// Returns all available local languages for the language picker.
    static func availableLocalLanguages() -> [SpeechLanguagePickerView.Language] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        var languageLocales: [String: Set<String>] = [:]
        for voice in voices {
            let baseCode = String(voice.language.prefix(while: { $0 != "-" }))
            languageLocales[baseCode, default: []].insert(voice.language)
        }
        return languageLocales.keys
            .compactMap { baseCode -> SpeechLanguagePickerView.Language? in
                guard let name = Locale.current.localizedString(forLanguageCode: baseCode) else { return nil }
                return SpeechLanguagePickerView.Language(id: baseCode, name: name, locales: languageLocales[baseCode]?.sorted() ?? [])
            }
            .sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
    }

    /// Returns all available remote languages for a given tier.
    static func availableRemoteLanguages(for tier: RemoteVoice.Tier, response: VoicesResponse) -> [SpeechLanguagePickerView.Language] {
        guard let tierData = response.tiers[tier] else { return [] }
        var languageLocales: [String: Set<String>] = [:]
        for data in tierData {
            for locale in data.locales.keys {
                let baseCode = String(locale.prefix(while: { $0 != "-" }))
                languageLocales[baseCode, default: []].insert(locale)
            }
        }
        return languageLocales.keys
            .compactMap { baseCode -> SpeechLanguagePickerView.Language? in
                guard let name = Locale.current.localizedString(forLanguageCode: baseCode) else { return nil }
                return SpeechLanguagePickerView.Language(id: baseCode, name: name, locales: languageLocales[baseCode]?.sorted() ?? [])
            }
            .sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
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

    /// Filters and sorts system local voices by a predicate. Sorted by quality (premium > enhanced > other), then by name.
    private static func filterLocalVoices(matching predicate: (AVSpeechSynthesisVoice) -> Bool) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter(predicate)
            .sorted {
                let q0 = qualitySortOrder($0.quality)
                let q1 = qualitySortOrder($1.quality)
                if q0 != q1 { return q0 < q1 }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// Returns sort order for voice quality (lower = better).
    private static func qualitySortOrder(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium:
            return 0

        case .enhanced:
            return 1

        default:
            return 2
        }
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
