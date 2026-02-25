//
//  SpeechVoicePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import SwiftUI

import CocoaLumberjackSwift
import RxSwift

struct SpeechVoicePickerView: View {
    fileprivate enum VoiceType {
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
    }

    private unowned let remoteVoicesController: RemoteVoicesController
    private let detectedLanguage: String
    private let dismiss: (AccessibilityPopupVoiceChange) -> Void
    private let disposeBag: DisposeBag

    @State private var type: VoiceType
    @State private var language: SpeechLanguageChoice
    @State private var selectedVoice: SpeechVoice
    @State private var localVoices: [AVSpeechSynthesisVoice]
    @State private var groupedLocalVoices: [LocaleLocalVoiceGroup] = []
    @State private var groupedRemoteVoices: [LocaleRemoteVoiceGroup] = []
    @State private var voicesResponse: VoicesResponse?
    @State private var navigationPath: NavigationPath
    @State private var standardCreditsRemaining: Int?
    @State private var premiumCreditsRemaining: Int?
    @State private var isLoading: Bool = false
    @State private var loadError: Bool = false

    private var baseLanguage: String {
        language.baseLanguage(detectedLanguage: detectedLanguage)
    }

    private var resolvedLocale: String {
        language.resolvedLocale(detectedLanguage: detectedLanguage)
    }

    private var canShowLanguage: Bool {
        switch type {
        case .local:
            return true

        case .premium, .standard:
            return voicesResponse != nil
        }
    }

    private var selectedVoiceBinding: Binding<SpeechVoice?> {
        Binding<SpeechVoice?>(
            get: { selectedVoice },
            set: { if let voice = $0 { selectedVoice = voice } }
        )
    }

    init(
        selectedVoice: SpeechVoice,
        language: String?,
        detectedLanguage: String,
        remoteVoicesController: RemoteVoicesController,
        dismiss: @escaping (AccessibilityPopupVoiceChange) -> Void
    ) {
        self.selectedVoice = selectedVoice
        self.language = language.flatMap({ .language(String($0.prefix(while: { $0 != "-" }))) }) ?? .auto
        self.detectedLanguage = detectedLanguage
        self.remoteVoicesController = remoteVoicesController
        self.dismiss = dismiss
        navigationPath = NavigationPath()
        let baseLang = language.flatMap({ String($0.prefix(while: { $0 != "-" })) }) ?? String(detectedLanguage.prefix(while: { $0 != "-" }))
        localVoices = VoiceUtility.localVoices(forBaseLanguage: baseLang)
        disposeBag = .init()
        switch selectedVoice {
        case .local:
            type = .local

        case .remote(let voice):
            type = voice.tier == .premium ? .premium : .standard
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                TypeSection(type: $type)
                if canShowLanguage {
                    SpeechLanguageSection(language: $language, detectedLanguage: detectedLanguage, navigationPath: $navigationPath)
                }
                switch type {
                case .local:
                    SpeechLocalVoicesSection(groups: groupedLocalVoices, selectedVoice: selectedVoiceBinding, language: baseLanguage)

                case .premium, .standard:
                    if loadError {
                        SpeechLoadErrorSection(retryAction: loadVoices)
                    } else if voicesResponse != nil {
                        if groupedRemoteVoices.isEmpty {
                            SpeechNoVoicesSection(language: baseLanguage)
                        } else {
                            SpeechRemoteVoicesSection(
                                groups: groupedRemoteVoices,
                                selectedVoice: selectedVoiceBinding,
                                creditsRemaining: type == .premium ? premiumCreditsRemaining : standardCreditsRemaining,
                                remoteVoicesController: remoteVoicesController
                            )
                        }
                    } else if isLoading {
                        ActivityIndicatorView(style: .large, isAnimating: .constant(true))
                    }
                }
            }
            .listStyle(.grouped)
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self, destination: { value in
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
            })
            .onChange(of: type) { newValue in
                switch newValue {
                case .local:
                    if let voice = VoiceUtility.findLocalVoice(for: resolvedLocale, from: localVoices) {
                        selectedVoice = .local(voice)
                    }

                case .premium, .standard:
                    reloadGroupedRemoteVoices()
                    autoSelectRemoteVoice()
                }
            }
            .onChange(of: selectedVoice) { newValue in
                saveVoicePreference(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let preferredLanguage: String?
                        switch language {
                        case .auto:
                            preferredLanguage = nil

                        case .language:
                            preferredLanguage = resolvedLocale
                        }
                        dismiss(AccessibilityPopupVoiceChange(voice: selectedVoice, preferredLanguage: preferredLanguage))
                    } label: {
                        Text("Close")
                    }
                }
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
                    standardCreditsRemaining = result.credits.standard
                    premiumCreditsRemaining = result.credits.premium
                    reloadGroupedRemoteVoices()
                    isLoading = false
                }, onFailure: { error in
                    DDLogError("SpeechVoicePickerView: can't load remote voices - \(error)")
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
        switch type {
        case .local:
            if let voice = VoiceUtility.findLocalVoice(for: resolvedLocale, from: localVoices) {
                selectedVoice = .local(voice)
            }

        case .premium, .standard:
            autoSelectRemoteVoice()
        }
    }

    private func createLanguages() -> [SpeechLanguagePickerView.Language] {
        switch type {
        case .local:
            return VoiceUtility.availableLocalLanguages()

        case .premium:
            return voicesResponse.flatMap({ VoiceUtility.availableRemoteLanguages(for: .premium, response: $0) }) ?? []

        case .standard:
            return voicesResponse.flatMap({ VoiceUtility.availableRemoteLanguages(for: .standard, response: $0) }) ?? []
        }
    }

    // MARK: - Voice reloading

    private func reloadLocalVoices() {
        localVoices = VoiceUtility.localVoices(forBaseLanguage: baseLanguage)
        groupedLocalVoices = VoiceUtility.groupLocalVoices(localVoices, baseLanguage: baseLanguage)
    }

    private func reloadGroupedRemoteVoices() {
        guard let response = voicesResponse, let tier = type.remoteTier else {
            groupedRemoteVoices = []
            return
        }
        let locales = VoiceUtility.remoteLocales(forBaseLanguage: baseLanguage, tier: tier, response: response)
        groupedRemoteVoices = VoiceUtility.groupRemoteVoices(locales: locales, tier: tier, baseLanguage: baseLanguage, response: response)
    }

    private func autoSelectRemoteVoice() {
        guard let response = voicesResponse, let tier = type.remoteTier else { return }
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

// MARK: - Type Section

// swiftlint:disable private_over_fileprivate
fileprivate struct TypeSection: View {
    @Binding var type: SpeechVoicePickerView.VoiceType

    var body: some View {
        Section {
            HStack {
                Text("Standard")
                Spacer()
                if case .standard = type {
                    Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                type = .standard
            }

            HStack {
                Text("Premium")
                Spacer()
                if case .premium = type {
                    Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                type = .premium
            }

            HStack {
                Text("Premium")
                Spacer()
                if case .premium = type {
                    Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                type = .premium
            }
            
            HStack {
                Text("Local")
                Spacer()
                if case .local = type {
                    Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                type = .local
            }
        }
    }
}
// swiftlint:enable private_over_fileprivate

#Preview {
    SpeechVoicePickerView(
        selectedVoice: .local(AVSpeechSynthesisVoice.speechVoices().first!),
        language: nil,
        detectedLanguage: "en",
        remoteVoicesController: RemoteVoicesController(apiClient: ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: .default)),
        dismiss: { _ in }
    )
}
