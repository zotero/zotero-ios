//
//  ReadAloudOnboardingView.swift
//  Zotero
//
//  Created by Michal Rentka on 24.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import SwiftUI

import RxSwift

struct ReadAloudOnboardingView: View {
    fileprivate enum VoiceTier: CaseIterable {
        case premium, standard, local

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

    private unowned let remoteVoicesController: RemoteVoicesController
    private let detectedLanguage: String
    private let dismiss: (SpeechVoice?) -> Void
    private let disposeBag: DisposeBag

    @State private var selectedTier: VoiceTier = .standard
    @State private var selectedVoice: SpeechVoice?
    @State private var voicesResponse: VoicesResponse?
    @State private var localVoices: [AVSpeechSynthesisVoice]
    @State private var groupedRemoteVoices: [LocaleRemoteVoiceGroup] = []
    @State private var groupedLocalVoices: [LocaleLocalVoiceGroup] = []
    @State private var isLoading: Bool = false
    @State private var loadError: Bool = false
    @State private var language: SpeechLanguageChoice
    @State private var navigationPath = NavigationPath()

    private var baseLanguage: String {
        language.baseLanguage(detectedLanguage: detectedLanguage)
    }

    private var resolvedLocale: String {
        language.resolvedLocale(detectedLanguage: detectedLanguage)
    }

    private var canShowLanguage: Bool {
        switch selectedTier {
        case .local:
            return true

        case .premium, .standard:
            return voicesResponse != nil
        }
    }

    init(
        language: String?,
        detectedLanguage: String,
        remoteVoicesController: RemoteVoicesController,
        dismiss: @escaping (SpeechVoice?) -> Void
    ) {
        self.detectedLanguage = detectedLanguage
        self.remoteVoicesController = remoteVoicesController
        self.dismiss = dismiss
        self.disposeBag = DisposeBag()
        _language = State(initialValue: language.flatMap({ .language(String($0.prefix(while: { $0 != "-" }))) }) ?? .auto)
        let baseLang = language.flatMap({ String($0.prefix(while: { $0 != "-" })) }) ?? String(detectedLanguage.prefix(while: { $0 != "-" }))
        _localVoices = State(initialValue: VoiceUtility.localVoices(forBaseLanguage: baseLang))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                Text(L10n.Speech.Onboarding.title)
                    .font(.headline)
                    .padding(.top, 30)

                // Segmented control for tier selection
                Picker("", selection: $selectedTier) {
                    ForEach([VoiceTier.standard, VoiceTier.premium, VoiceTier.local], id: \.self) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 16)

                List {
                    // Description section
                    Section {
                        ForEach(selectedTier.descriptionBulletPoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text(point)
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }
                    }

                    // Language section
                    if canShowLanguage {
                        SpeechLanguageSection(language: $language, detectedLanguage: detectedLanguage, navigationPath: $navigationPath)
                    }

                    // Voices section
                    if isLoading {
                        Section(L10n.Speech.voices.uppercased()) {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                    } else if loadError {
                        SpeechLoadErrorSection(retryAction: loadVoices)
                    } else {
                        switch selectedTier {
                        case .premium, .standard:
                            if groupedRemoteVoices.isEmpty {
                                SpeechNoVoicesSection(language: baseLanguage)
                            } else {
                                SpeechRemoteVoicesSection(
                                    groups: groupedRemoteVoices,
                                    selectedVoice: $selectedVoice,
                                    creditsRemaining: nil,
                                    remoteVoicesController: remoteVoicesController
                                )
                            }

                        case .local:
                            SpeechLocalVoicesSection(groups: groupedLocalVoices, selectedVoice: $selectedVoice, language: baseLanguage)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.cancel) {
                        dismiss(nil)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.done) {
                        if let selectedVoice {
                            saveVoicePreference(selectedVoice)
                        }
                        dismiss(selectedVoice)
                    }
                }
            }
            .navigationDestination(for: String.self) { value in
                if value == "languages" {
                    SpeechLanguagePickerView(
                        currentLanguage: language,
                        detectedLanguage: detectedLanguage,
                        languages: createLanguages(),
                        navigationPath: $navigationPath,
                        onLanguageSelected: { selectedLanguage in
                            handleLanguageSelected(selectedLanguage)
                        }
                    )
                }
            }
            .onChange(of: selectedTier) { _ in
                reloadGroupedRemoteVoices()
                updateSelectedVoiceForTier()
            }
            .onAppear {
                groupedLocalVoices = VoiceUtility.groupLocalVoices(localVoices, baseLanguage: baseLanguage)
                loadVoices()
            }
        }
    }

    // MARK: - Voice loading

    private func loadVoices() {
        isLoading = true
        loadError = false
        remoteVoicesController.loadVoices()
            .subscribe(
                onSuccess: { result in
                    voicesResponse = result.response
                    reloadGroupedRemoteVoices()
                    isLoading = false
                    updateSelectedVoiceForTier()
                },
                onFailure: { _ in
                    isLoading = false
                    loadError = true
                }
            )
            .disposed(by: disposeBag)
    }

    // MARK: - Language selection

    private func handleLanguageSelected(_ selectedLanguage: SpeechLanguagePickerView.Language?) {
        if let selectedLanguage {
            language = .language(selectedLanguage.id)
        } else {
            language = .auto
        }
        reloadLocalVoices()
        reloadGroupedRemoteVoices()
        switch selectedTier {
        case .local:
            if let voice = VoiceUtility.findLocalVoice(for: resolvedLocale, from: localVoices) {
                selectedVoice = .local(voice)
            }

        case .premium, .standard:
            autoSelectRemoteVoice()
        }
    }

    private func createLanguages() -> [SpeechLanguagePickerView.Language] {
        switch selectedTier {
        case .local:
            return VoiceUtility.availableLocalLanguages()

        case .premium:
            return voicesResponse.flatMap({ VoiceUtility.availableRemoteLanguages(for: .premium, response: $0) }) ?? []

        case .standard:
            return voicesResponse.flatMap({ VoiceUtility.availableRemoteLanguages(for: .standard, response: $0) }) ?? []
        }
    }

    // MARK: - Voice reloading

    private func updateSelectedVoiceForTier() {
        switch selectedTier {
        case .premium, .standard:
            autoSelectRemoteVoice()

        case .local:
            if let voice = VoiceUtility.findLocalVoice(for: resolvedLocale, from: localVoices) {
                selectedVoice = .local(voice)
            }
        }
    }

    private func reloadLocalVoices() {
        localVoices = VoiceUtility.localVoices(forBaseLanguage: baseLanguage)
        groupedLocalVoices = VoiceUtility.groupLocalVoices(localVoices, baseLanguage: baseLanguage)
    }

    private func reloadGroupedRemoteVoices() {
        guard let response = voicesResponse, let tier = selectedTier.remoteTier else {
            groupedRemoteVoices = []
            return
        }
        let locales = VoiceUtility.remoteLocales(forBaseLanguage: baseLanguage, tier: tier, response: response)
        groupedRemoteVoices = VoiceUtility.groupRemoteVoices(locales: locales, tier: tier, baseLanguage: baseLanguage, response: response)
    }

    private func autoSelectRemoteVoice() {
        guard let response = voicesResponse, let tier = selectedTier.remoteTier else { return }
        if let voice = VoiceUtility.findRemoteVoice(for: resolvedLocale, tier: tier, response: response) {
            selectedVoice = .remote(voice)
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
