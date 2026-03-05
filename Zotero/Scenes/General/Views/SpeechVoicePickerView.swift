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
    struct LocaleVoiceGroup: Identifiable {
        let locale: String
        let displayName: String
        let voices: [RemoteVoice]
        var id: String { locale }
    }

    enum Language: Identifiable, Equatable {
        case auto
        case language(String)

        var id: String {
            switch self {
            case .auto:
                return "auto"

            case .language(let code):
                return code
            }
        }
    }

    fileprivate enum VoiceType {
        case premium, standard, local

        var isRemote: Bool {
            switch self {
            case .premium, .standard:
                return true

            case .local:
                return false
            }
        }
    }

    private unowned let remoteVoicesController: RemoteVoicesController
    private let detectedLanguage: String
    private let dismiss: (AccessibilityPopupVoiceChange) -> Void
    private let disposeBag: DisposeBag

    @State private var type: VoiceType
    @State private var language: Language
    @State private var selectedVoice: SpeechVoice
    @State private var localVoices: [AVSpeechSynthesisVoice]
    @State private var groupedVoices: [LocaleVoiceGroup]
    @State private var voicesResponse: VoicesResponse?
    @State private var navigationPath: NavigationPath
    @State private var standardCreditsRemaining: Int?
    @State private var premiumCreditsRemaining: Int?
    @State private var isLoading: Bool = false
    @State private var loadError: Bool = false

    private var baseLanguage: String {
        switch language {
        case .auto:
            return String(detectedLanguage.prefix(while: { $0 != "-" }))

        case .language(let code):
            return code
        }
    }

    private var resolvedLocale: String {
        switch language {
        case .auto:
            return detectedLanguage

        case .language(let code):
            return LanguageDetector.canonicalVariation(for: code) ?? code
        }
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
        localVoices = VoiceFinder.localVoices(forBaseLanguage: baseLang)
        groupedVoices = []
        voicesResponse = nil
        standardCreditsRemaining = nil
        premiumCreditsRemaining = nil
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
                    LanguageSection(language: $language, detectedLanguage: detectedLanguage, navigationPath: $navigationPath)
                }
                switch type {
                case .local:
                    LocalVoicesSection(voices: $localVoices, selectedVoice: $selectedVoice, language: baseLanguage)

                case .premium, .standard:
                    if loadError {
                        LoadErrorSection(retryAction: loadVoices)
                    } else if voicesResponse != nil {
                        if groupedVoices.isEmpty {
                            NoVoicesForLanguageSection(language: baseLanguage)
                        } else {
                            RemoteVoicesSection(
                                groups: groupedVoices,
                                selectedVoice: $selectedVoice,
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
                            let locales: [String]
                            if let selectedLanguage {
                                language = .language(selectedLanguage.id)
                                locales = selectedLanguage.locales
                            } else {
                                language = .auto
                                locales = remoteLocales(forBaseLanguage: baseLanguage)
                            }
                            reloadLocalVoices()
                            reloadGroupedVoices(locales: locales)
                            switch type {
                            case .local:
                                if let voice = VoiceFinder.findLocalVoice(for: resolvedLocale, from: localVoices) {
                                    selectedVoice = .local(voice)
                                }

                            case .premium, .standard:
                                autoSelectVoice()
                            }
                        }
                    )
                }
            })
            .onChange(of: type) { newValue in
                switch newValue {
                case .local:
                    if let voice = VoiceFinder.findLocalVoice(for: resolvedLocale, from: localVoices) {
                        selectedVoice = .local(voice)
                    }

                case .premium, .standard:
                    reloadGroupedVoices(locales: remoteLocales(forBaseLanguage: baseLanguage))
                    autoSelectVoice()
                }
            }
            .onChange(of: selectedVoice) { newValue in
                let storageKey = resolvedLocale
                switch newValue {
                case .local(let voice):
                    Defaults.shared.defaultLocalVoiceForLanguage[storageKey] = voice.identifier
                    Defaults.shared.remoteVoiceTier = nil

                case .remote(let voice):
                    switch voice.tier {
                    case .premium:
                        Defaults.shared.defaultPremiumRemoteVoiceForLanguage[storageKey] = voice

                    case .standard:
                        Defaults.shared.defaultStandardRemoteVoiceForLanguage[storageKey] = voice
                    }
                    Defaults.shared.remoteVoiceTier = voice.tier
                }
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
                loadVoices()
            }
        }
    }

    private func loadVoices() {
        isLoading = true
        loadError = false
        remoteVoicesController.loadVoices()
            .subscribe(
                onSuccess: { result in
                    voicesResponse = result.response
                    standardCreditsRemaining = result.credits.standard
                    premiumCreditsRemaining = result.credits.premium
                    reloadGroupedVoices(locales: remoteLocales(forBaseLanguage: baseLanguage))
                    isLoading = false
                }, onFailure: { error in
                    DDLogError("SpeechVoicePickerView: can't load remote voices - \(error)")
                    isLoading = false
                    loadError = true
                }
            )
            .disposed(by: disposeBag)
    }

    private func reloadGroupedVoices(locales: [String]) {
        guard let response = voicesResponse else {
            groupedVoices = []
            return
        }
        let tier: RemoteVoice.Tier = type == .premium ? .premium : .standard
        let base = baseLanguage
        groupedVoices = locales.compactMap { locale in
            let voices = VoiceFinder.remoteVoices(for: locale, tier: tier, fromResponse: response)
            guard !voices.isEmpty else { return nil }
            return LocaleVoiceGroup(locale: locale, displayName: VoiceFinder.variationName(for: locale, baseLanguage: base), voices: voices)
        }
    }

    private func remoteLocales(forBaseLanguage base: String) -> [String] {
        let tier: RemoteVoice.Tier = type == .premium ? .premium : .standard
        guard let tierData = voicesResponse?.tiers[tier] else { return [] }
        var locales: Set<String> = []
        for data in tierData {
            for locale in data.locales.keys where String(locale.prefix(while: { $0 != "-" })) == base {
                locales.insert(locale)
            }
        }
        return locales.sorted()
    }

    private func reloadLocalVoices() {
        localVoices = VoiceFinder.localVoices(forBaseLanguage: baseLanguage)
    }

    private func autoSelectVoice() {
        guard let response = voicesResponse else { return }
        let tier: RemoteVoice.Tier = type == .premium ? .premium : .standard
        if let voice = VoiceFinder.findRemoteVoice(for: resolvedLocale, tier: tier, response: response) {
            selectedVoice = .remote(voice)
        }
    }

    private var canShowLanguage: Bool {
        switch type {
        case .local:
            return true

        case .premium, .standard:
            return voicesResponse != nil
        }
    }

    private func createLanguages() -> [SpeechLanguagePickerView.Language] {
        switch type {
        case .local:
            return createLocalLanguages()

        case .premium:
            return createRemoteLanguages(for: .premium)

        case .standard:
            return createRemoteLanguages(for: .standard)
        }
    }

    private func createLocalLanguages() -> [SpeechLanguagePickerView.Language] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        var languageLocales: [String: Set<String>] = [:]
        for voice in voices {
            let baseCode = String(voice.language.prefix(while: { $0 != "-" }))
            languageLocales[baseCode, default: []].insert(voice.language)
        }
        return languageLocales.keys
            .compactMap { baseCode -> SpeechLanguagePickerView.Language? in
                guard let name = Locale.current.localizedString(forLanguageCode: baseCode) else { return nil }
                let locales = languageLocales[baseCode]?.sorted() ?? []
                return SpeechLanguagePickerView.Language(id: baseCode, name: name, locales: locales)
            }
            .sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private func createRemoteLanguages(for tier: RemoteVoice.Tier) -> [SpeechLanguagePickerView.Language] {
        guard let tierData = voicesResponse?.tiers[tier] else { return [] }
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
                let locales = languageLocales[baseCode]?.sorted() ?? []
                return SpeechLanguagePickerView.Language(id: baseCode, name: name, locales: locales)
            }
            .sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
    }
}

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

fileprivate struct LanguageSection: View {
    @Binding var language: SpeechVoicePickerView.Language
    let detectedLanguage: String
    @Binding var navigationPath: NavigationPath

    private var detectedLanguageName: String {
        Locale.current.localizedString(forIdentifier: detectedLanguage) ?? detectedLanguage
    }

    var body: some View {
        Section {
            HStack {
                Text("Language")
                Spacer()
                switch language {
                case .auto:
                    Text("\(L10n.Accessibility.Speech.automatic) - \(detectedLanguageName)").foregroundColor(.gray)

                case .language(let code):
                    Text(Locale.current.localizedString(forLanguageCode: code) ?? "Unknown").foregroundColor(.gray)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.system(size: 13, weight: .semibold))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                navigationPath.append("languages")
            }
        }
    }
}

fileprivate struct LoadErrorSection: View {
    let retryAction: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 16) {
                Text(L10n.Errors.Shareext.cantLoadData)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: retryAction) {
                    Text(L10n.retry)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

fileprivate struct NoVoicesForLanguageSection: View {
    let language: String

    private var languageName: String {
        Locale.current.localizedString(forIdentifier: language) ?? language
    }

    var body: some View {
        Section {
            Text(L10n.Accessibility.Speech.noVoicesForTier(languageName))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }
}

fileprivate struct LocalVoicesSection: View {
    private let synthetizer: AVSpeechSynthesizer
    private let shouldShowVariation: Bool
    private let language: String

    @Binding var voices: [AVSpeechSynthesisVoice]
    @Binding var selectedVoice: SpeechVoice

    init(voices: Binding<[AVSpeechSynthesisVoice]>, selectedVoice: Binding<SpeechVoice>, language: String) {
        self._voices = voices
        self._selectedVoice = selectedVoice
        synthetizer = .init()
        shouldShowVariation = voices.count > 1 && Set(voices.wrappedValue.map({ $0.languageVariation })).count > 1
        self.language = language
    }

    var body: some View {
        Section(L10n.Accessibility.Speech.voices.uppercased()) {
            ForEach(voices) { voice in
                HStack {
                    Text(voice.name)
                        .foregroundStyle(.primary)
                    if shouldShowVariation {
                        Text("(\(voice.languageVariation))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .local(let localVoice) = selectedVoice, localVoice == voice {
                        Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedVoice = .local(voice)
                    playSample(withVoice: voice)
                }
            }
        }
    }

    private func playSample(withVoice voice: AVSpeechSynthesisVoice) {
        if synthetizer.isSpeaking {
            synthetizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: L10n.Accessibility.Speech.localSample(voice.name))
        utterance.voice = voice
        synthetizer.speak(utterance)
    }
}

extension RemoteVoice: Identifiable {}

fileprivate struct RemoteVoicesSection: View {
    let groups: [SpeechVoicePickerView.LocaleVoiceGroup]
    @Binding var selectedVoice: SpeechVoice
    let creditsRemaining: Int?
    @State private var player: AVAudioPlayer?
    @State private var isLoading: Bool = false

    unowned let remoteVoicesController: RemoteVoicesController
    private let disposeBag: DisposeBag = .init()

    var body: some View {
        ForEach(groups) { group in
            Section(group.displayName.uppercased()) {
                ForEach(group.voices) { voice in
                    HStack {
                        Text(voice.label)
                        Spacer()
                        if case .remote(let remoteVoice) = selectedVoice, remoteVoice == voice {
                            if isLoading {
                                ActivityIndicatorView(style: .medium, isAnimating: .constant(true))
                            } else {
                                Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                            }
                        }
                        if let remainingTime = remainingTime(for: voice) {
                            Text(RemainingTimeFormatter.formatted(remainingTime))
                                .foregroundColor(RemainingTimeFormatter.isWarning(remainingTime) ? .red : .secondary)
                                .font(.subheadline)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isLoading else { return }
                        player?.stop()
                        selectedVoice = .remote(voice)
                        playSample(withVoice: voice)
                    }
                }
            }
        }
        .onDisappear {
            player?.stop()
        }
    }

    private func remainingTime(for voice: RemoteVoice) -> TimeInterval? {
        guard let creditsRemaining, voice.creditsPerMinute > 0 else { return nil }
        let time = (TimeInterval(creditsRemaining) / TimeInterval(voice.creditsPerMinute)) * 60
        guard RemainingTimeFormatter.shouldDisplay(time) else { return nil }
        return time
    }

    private func playSample(withVoice voice: RemoteVoice) {
        isLoading = true
        remoteVoicesController.downloadSample(voiceId: voice.id)
            .subscribe(onSuccess: { data in
                play(data: data)
            }, onFailure: { error in
                DDLogError("RemoteVoicesSection: can't load sample - \(error)")
                isLoading = false
            })
            .disposed(by: disposeBag)

        func play(data: Data) {
            do {
                player = try AVAudioPlayer(data: data)
                player?.prepareToPlay()
                player?.play()
            } catch let error {
                DDLogError("RemoteVoicesSection: can't play data - \(error)")
            }

            isLoading = false
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

extension AVSpeechSynthesisVoice: @retroactive Identifiable {
    public var id: String { identifier }

    fileprivate var languageVariation: String {
        let locale = Locale.current
        guard let localized = locale.localizedString(forIdentifier: language) else { return name }
        guard let localizedLanguage = locale.localizedString(forLanguageCode: language), localized.starts(with: localizedLanguage) else { return name }
        return String(localized[localized.index(localized.startIndex, offsetBy: localizedLanguage.count)..<localized.endIndex])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
    }
}
