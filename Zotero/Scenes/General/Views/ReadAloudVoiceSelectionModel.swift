//
//  ReadAloudVoiceSelectionModel.swift
//  Zotero
//
//  Created by Michal Rentka on 2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import SwiftUI

import CocoaLumberjackSwift
import RxSwift

enum ReadAloudVoiceType: CaseIterable, Equatable {
    case premium, standard, local

    var remoteTier: RemoteVoice.Tier? {
        switch self {
        case .premium:
            return .premium

        case .standard:
            return .standard

        case .local:
            return nil
        }
    }

    var title: String {
        switch self {
        case .premium:
            return L10n.Speech.Onboarding.tierPremium

        case .standard:
            return L10n.Speech.Onboarding.tierStandard

        case .local:
            return L10n.Speech.Onboarding.tierLocal
        }
    }

    var descriptionBulletPoints: [String] {
        let prefix: String
        switch self {
        case .premium:
            prefix = "speech.onboarding.description_premium"

        case .standard:
            prefix = "speech.onboarding.description_standard"

        case .local:
            prefix = "speech.onboarding.description_local"
        }
        let bundle = Bundle(for: AppDelegate.self)
        var results: [String] = []
        var index = 1
        while true {
            let key = "\(prefix)_\(index)"
            let localized = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            guard localized != key && !localized.isEmpty else { break }
            results.append(localized.replacingAppName.replacingSubscriptionName)
            index += 1
        }
        return results
    }
}

@MainActor
final class ReadAloudVoiceSelectionModel: ObservableObject {
    @Published var type: ReadAloudVoiceType
    @Published var language: ReadAloudLanguageChoice
    @Published var selectedVoice: SpeechVoice?
    @Published var selectedRegionLocale: String?
    @Published private(set) var localVoices: [AVSpeechSynthesisVoice]
    @Published private(set) var groupedLocalVoices: [LocaleLocalVoiceGroup] = []
    @Published private(set) var groupedRemoteVoices: [LocaleRemoteVoiceGroup] = []
    @Published private(set) var voicesResponse: VoicesResponse?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: Bool = false

    let detectedLanguage: String
    unowned let remoteVoicesController: RemoteVoicesController

    private let savesOnVoiceChange: Bool
    private var standardCreditsRemaining: Int?
    private var premiumCreditsRemaining: Int?
    private let disposeBag = DisposeBag()

    var baseLanguage: String {
        language.baseLanguage(detectedLanguage: detectedLanguage)
    }

    var resolvedLocale: String {
        language.resolvedLocale(detectedLanguage: detectedLanguage)
    }

    var canShowLanguage: Bool {
        switch type {
        case .local:
            return true

        case .premium, .standard:
            return voicesResponse != nil
        }
    }

    var currentRegions: [(locale: String, displayName: String)] {
        switch type {
        case .local:
            return groupedLocalVoices.map { (locale: $0.locale, displayName: $0.displayName) }

        case .premium, .standard:
            return groupedRemoteVoices.map { (locale: $0.locale, displayName: $0.displayName) }
        }
    }

    var currentLocalVoices: [AVSpeechSynthesisVoice] {
        guard let locale = selectedRegionLocale else { return [] }
        return groupedLocalVoices.first(where: { $0.locale == locale })?.voices ?? []
    }

    var currentRemoteVoices: [RemoteVoice] {
        guard let locale = selectedRegionLocale else { return [] }
        return groupedRemoteVoices.first(where: { $0.locale == locale })?.voices ?? []
    }

    /// Credits available for the current tier, or `nil` if the picker shouldn't display them.
    var displayedCreditsRemaining: Int? {
        switch type {
        case .premium:
            return premiumCreditsRemaining

        case .standard:
            return standardCreditsRemaining

        case .local:
            return nil
        }
    }

    /// Preferred language to report back to callers on dismiss — nil for auto, otherwise the resolved locale.
    var preferredLanguageForDismiss: String? {
        switch language {
        case .auto:
            return nil

        case .language:
            return resolvedLocale
        }
    }

    init(
        initialVoice: SpeechVoice?,
        language: String?,
        detectedLanguage: String,
        remoteVoicesController: RemoteVoicesController,
        savesOnVoiceChange: Bool
    ) {
        self.detectedLanguage = detectedLanguage
        self.remoteVoicesController = remoteVoicesController
        self.savesOnVoiceChange = savesOnVoiceChange
        self.selectedVoice = initialVoice
        self.language = language.flatMap({ .language(String($0.prefix(while: { $0 != "-" }))) }) ?? .auto
        let baseLang = language.flatMap({ String($0.prefix(while: { $0 != "-" })) }) ?? String(detectedLanguage.prefix(while: { $0 != "-" }))
        self.localVoices = VoiceUtility.localVoices(forBaseLanguage: baseLang)

        switch initialVoice {
        case .local(let voice):
            self.type = .local
            self.selectedRegionLocale = voice.language

        case .remote(let voice):
            self.type = voice.tier == .premium ? .premium : .standard
            self.selectedRegionLocale = nil

        case .none:
            self.type = .standard
            self.selectedRegionLocale = nil
        }
    }

    // MARK: - View lifecycle

    func onAppear() {
        groupedLocalVoices = VoiceUtility.groupLocalVoices(localVoices, baseLanguage: baseLanguage)
        revalidateSelectedRegion()
        loadVoices()
    }

    // MARK: - View-driven change handlers

    /// Called when `type` changes. Reloads voices for the new tier and picks a voice that respects the current region.
    func handleTypeChange() {
        switch type {
        case .local:
            if let locale = selectedRegionLocale,
               let group = groupedLocalVoices.first(where: { $0.locale == locale }),
               let voice = preferredLocalVoice(in: group) {
                selectedVoice = .local(voice)
            } else if let voice = VoiceUtility.findLocalVoice(for: resolvedLocale, from: localVoices) {
                selectedVoice = .local(voice)
            }

        case .premium, .standard:
            reloadGroupedRemoteVoices()
            autoSelectRemoteVoice()
        }
    }

    func handleSelectedVoiceChange() {
        guard let voice = selectedVoice else { return }
        if savesOnVoiceChange {
            saveVoicePreference(voice)
        }
        updateSelectedRegionFromVoice(voice)
    }

    func handleSelectedRegionChange() {
        autoSelectVoiceForRegion(selectedRegionLocale)
    }

    func handleLanguageSelected(_ selectedLanguage: ReadAloudLanguagePickerView.Language?) {
        if let selectedLanguage {
            language = .language(selectedLanguage.id)
        } else {
            language = .auto
        }
        reloadLocalVoices()
        reloadGroupedRemoteVoices()
        switch type {
        case .local:
            if let voice = VoiceUtility.findLocalVoice(for: resolvedLocale, from: localVoices) {
                selectedVoice = .local(voice)
            }

        case .premium, .standard:
            autoSelectRemoteVoice()
        }
    }

    func createLanguages() -> [ReadAloudLanguagePickerView.Language] {
        switch type {
        case .local:
            return VoiceUtility.availableLocalLanguages()

        case .premium:
            return voicesResponse.flatMap({ VoiceUtility.availableRemoteLanguages(for: .premium, response: $0) }) ?? []

        case .standard:
            return voicesResponse.flatMap({ VoiceUtility.availableRemoteLanguages(for: .standard, response: $0) }) ?? []
        }
    }

    func saveCurrentVoicePreference() {
        guard let voice = selectedVoice else { return }
        saveVoicePreference(voice)
    }

    // MARK: - Voice loading

    func loadVoices() {
        isLoading = true
        loadError = false
        remoteVoicesController.loadVoices()
            .subscribe(
                onSuccess: { [weak self] result in
                    guard let self else { return }
                    voicesResponse = result.response
                    standardCreditsRemaining = result.credits.standard
                    premiumCreditsRemaining = result.credits.premium
                    reloadGroupedRemoteVoices()
                    isLoading = false
                },
                onFailure: { [weak self] error in
                    guard let self else { return }
                    DDLogError("ReadAloudVoiceSelectionModel: can't load remote voices - \(error)")
                    isLoading = false
                    loadError = true
                }
            )
            .disposed(by: disposeBag)
    }

    // MARK: - Voice reloading

    private func reloadLocalVoices() {
        localVoices = VoiceUtility.localVoices(forBaseLanguage: baseLanguage)
        groupedLocalVoices = VoiceUtility.groupLocalVoices(localVoices, baseLanguage: baseLanguage)
        revalidateSelectedRegion()
    }

    private func reloadGroupedRemoteVoices() {
        guard let response = voicesResponse, let tier = type.remoteTier else {
            groupedRemoteVoices = []
            return
        }
        let locales = VoiceUtility.remoteLocales(forBaseLanguage: baseLanguage, tier: tier, response: response)
        groupedRemoteVoices = VoiceUtility.groupRemoteVoices(locales: locales, tier: tier, baseLanguage: baseLanguage, response: response)
        revalidateSelectedRegion()
    }

    private func autoSelectRemoteVoice() {
        guard let response = voicesResponse, let tier = type.remoteTier else { return }
        // Prefer a voice from the currently-selected region's group of the new tier — `findRemoteVoice`'s broad fallback chain
        // (stored default keyed by `resolvedLocale`, canonical variation, device locale, en-US) can return a voice from a
        // different region, which would then cascade through `updateSelectedRegionFromVoice` and reset the region.
        if let locale = selectedRegionLocale,
           let group = groupedRemoteVoices.first(where: { $0.locale == locale }),
           let voice = preferredRemoteVoice(in: group, tier: tier) {
            selectedVoice = .remote(voice)
            return
        }
        if let voice = VoiceUtility.findRemoteVoice(for: resolvedLocale, tier: tier, response: response) {
            selectedVoice = .remote(voice)
        }
    }

    private func preferredRemoteVoice(in group: LocaleRemoteVoiceGroup, tier: RemoteVoice.Tier) -> RemoteVoice? {
        let savedVoices = tier == .premium
            ? Defaults.shared.defaultPremiumRemoteVoiceForLanguage
            : Defaults.shared.defaultStandardRemoteVoiceForLanguage
        if let savedVoice = savedVoices[group.locale], savedVoice.tier == tier, group.voices.contains(where: { $0.id == savedVoice.id }) {
            return savedVoice
        }
        return group.voices.first
    }

    private func preferredLocalVoice(in group: LocaleLocalVoiceGroup) -> AVSpeechSynthesisVoice? {
        if let savedIdentifier = Defaults.shared.defaultLocalVoiceForLanguage[group.locale],
           let voice = group.voices.first(where: { $0.identifier == savedIdentifier }) {
            return voice
        }
        return group.voices.first
    }

    // MARK: - Region selection

    /// Resets `selectedRegionLocale` after groups change. Prefers the locale of the currently selected voice,
    /// falling back to `resolvedLocale`, then the first available region.
    private func revalidateSelectedRegion() {
        let regions = currentRegions
        guard !regions.isEmpty else {
            selectedRegionLocale = nil
            return
        }
        if let locale = selectedRegionLocale, regions.contains(where: { $0.locale == locale }) { return }
        if let voiceLocale = selectedVoice.flatMap({ locale(for: $0) }), regions.contains(where: { $0.locale == voiceLocale }) {
            selectedRegionLocale = voiceLocale
        } else if regions.contains(where: { $0.locale == resolvedLocale }) {
            selectedRegionLocale = resolvedLocale
        } else {
            selectedRegionLocale = regions.first?.locale
        }
    }

    private func locale(for voice: SpeechVoice) -> String? {
        switch voice {
        case .local(let avVoice):
            return avVoice.language

        case .remote(let remoteVoice):
            // A multilingual remote voice can appear in several locale groups; prefer the currently-selected region
            // when the voice belongs to it so picking it (or auto-selecting it on tier switch) doesn't snap the region
            // to whichever group happens to be alphabetically first.
            if let locale = selectedRegionLocale,
               let group = groupedRemoteVoices.first(where: { $0.locale == locale }),
               group.voices.contains(where: { $0.id == remoteVoice.id }) {
                return locale
            }
            return groupedRemoteVoices.first(where: { $0.voices.contains(where: { $0.id == remoteVoice.id }) })?.locale
        }
    }

    private func updateSelectedRegionFromVoice(_ voice: SpeechVoice) {
        guard let voiceLocale = locale(for: voice), voiceLocale != selectedRegionLocale else { return }
        selectedRegionLocale = voiceLocale
    }

    private func autoSelectVoiceForRegion(_ locale: String?) {
        guard let locale else { return }
        // If the currently selected voice already belongs to this region, keep it.
        if let voice = selectedVoice, let currentLocale = self.locale(for: voice), currentLocale == locale { return }
        switch type {
        case .local:
            guard let avVoice = VoiceUtility.findLocalVoice(for: locale, from: localVoices) else { return }
            selectedVoice = .local(avVoice)

        case .premium, .standard:
            guard let response = voicesResponse, let tier = type.remoteTier,
                  let remoteVoice = VoiceUtility.findRemoteVoice(for: locale, tier: tier, response: response) else { return }
            selectedVoice = .remote(remoteVoice)
        }
    }

    // MARK: - Persistence

    private func saveVoicePreference(_ voice: SpeechVoice) {
        let storageKey = resolvedLocale
        switch voice {
        case .local(let avVoice):
            Defaults.shared.defaultLocalVoiceForLanguage[storageKey] = avVoice.identifier
            Defaults.shared.remoteVoiceTier = nil

        case .remote(let remoteVoice):
            switch remoteVoice.tier {
            case .premium:
                Defaults.shared.defaultPremiumRemoteVoiceForLanguage[storageKey] = remoteVoice

            case .standard:
                Defaults.shared.defaultStandardRemoteVoiceForLanguage[storageKey] = remoteVoice
            }
            Defaults.shared.remoteVoiceTier = remoteVoice.tier
        }
    }
}
