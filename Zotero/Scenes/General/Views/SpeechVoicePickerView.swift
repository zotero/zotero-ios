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
        
        func code(detectedLanguage: String) -> String {
            switch self {
            case .auto:
                return detectedLanguage
                
            case .language(let code):
                return code
            }
        }
    }
    
    fileprivate enum VoiceType {
        case advanced, basic, local
        
        var isRemote: Bool {
            switch self {
            case .advanced, .basic:
                return true
                
            case .local:
                return false
            }
        }
    }

    /// Threshold in seconds below which the remaining time indicator turns red
    private static let warningThresholdSeconds: TimeInterval = 180
    
    private static let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()
    
    private unowned let remoteVoicesController: RemoteVoicesController
    private let detectedLanguage: String
    private let dismiss: (AccessibilityPopupVoiceChange) -> Void
    private let disposeBag: DisposeBag

    @State private var type: VoiceType
    @State private var language: Language
    @State private var selectedVoice: SpeechVoice
    @State private var localVoices: [AVSpeechSynthesisVoice]
    @State private var remoteVoices: [RemoteVoice]
    @State private var navigationPath: NavigationPath
    @State private var allRemoteVoices: [RemoteVoice]
    @State private var supportedRemoteLanguages: Set<String>
    @State private var basicCreditsRemaining: Int?
    @State private var advancedCreditsRemaining: Int?
    @State private var isLoading: Bool = false
    @State private var loadError: Bool = false
    
    private var languageCode: String {
        return language.code(detectedLanguage: detectedLanguage)
    }

    /// Calculates remaining time based on remaining credits and the selected voice's credits per minute.
    /// Returns nil if type is local, no remote voice is selected, or creditsPerMinute is 0.
    private var remainingTime: TimeInterval? {
        guard type.isRemote,
              case .remote(let voice) = selectedVoice,
              voice.creditsPerMinute > 0
        else {
            return nil
        }
        let credits: Int?
        switch voice.tier {
        case .basic:
            credits = basicCreditsRemaining

        case .advanced:
            credits = advancedCreditsRemaining
        }
        guard let credits else { return nil }
        // creditsPerMinute means credits consumed per minute of audio, so remaining time in seconds = (credits / creditsPerMinute) * 60
        return (TimeInterval(credits) / TimeInterval(voice.creditsPerMinute)) * 60
    }

    init(
        selectedVoice: SpeechVoice,
        language: String?,
        detectedLanguage: String,
        remoteVoicesController: RemoteVoicesController,
        dismiss: @escaping (AccessibilityPopupVoiceChange) -> Void
    ) {
        self.selectedVoice = selectedVoice
        self.language = language.flatMap({ .language($0) }) ?? .auto
        self.detectedLanguage = detectedLanguage
        self.remoteVoicesController = remoteVoicesController
        self.dismiss = dismiss
        navigationPath = NavigationPath()
        localVoices = VoiceFinder.localVoices(for: language ?? detectedLanguage)
        remoteVoices = []
        allRemoteVoices = []
        supportedRemoteLanguages = []
        basicCreditsRemaining = nil
        advancedCreditsRemaining = nil
        disposeBag = .init()
        switch selectedVoice {
        case .local:
            type = .local
            
        case .remote(let voice):
            type = voice.tier == .advanced ? .advanced : .basic
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                TypeSection(type: $type)
                if let remainingTime {
                    RemainingTimeSection(remainingTime: remainingTime, warningThreshold: Self.warningThresholdSeconds, formatter: Self.timeFormatter)
                }
                if canShowLanguage {
                    LanguageSection(language: $language, detectedLanguage: detectedLanguage, navigationPath: $navigationPath)
                }
                switch type {
                case .local:
                    LocalVoicesSection(voices: $localVoices, selectedVoice: $selectedVoice, language: languageCode)
                    
                case .advanced, .basic:
                    if loadError {
                        LoadErrorSection(retryAction: loadVoices)
                    } else if !allRemoteVoices.isEmpty {
                        if remoteVoices.isEmpty {
                            NoVoicesForLanguageSection(language: languageCode)
                        } else {
                            RemoteVoicesSection(voices: $remoteVoices, selectedVoice: $selectedVoice, language: languageCode, remoteVoicesController: remoteVoicesController)
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
                        selectedLanguage: $language,
                        detectedLanguage: detectedLanguage,
                        languages: createLanguages(),
                        navigationPath: $navigationPath
                    )
                }
            })
            .onChange(of: language) { newValue in
                let language = newValue.code(detectedLanguage: detectedLanguage)
                localVoices = VoiceFinder.localVoices(for: language)
                remoteVoices = VoiceFinder.remoteVoices(for: languageCode, tier: (type == .advanced ? .advanced : .basic), from: allRemoteVoices)

                switch type {
                case .local:
                    if let voice = VoiceFinder.findLocalVoice(for: language, from: localVoices) {
                        selectedVoice = .local(voice)
                    }
                    
                case .advanced, .basic:
                    if let voice = VoiceFinder.findRemoteVoice(for: language, tier: (type == .advanced ? .advanced : .basic), from: remoteVoices) {
                        selectedVoice = .remote(voice)
                    }
                }
            }
            .onChange(of: type) { newValue in
                switch newValue {
                case .local:
                    if let voice = VoiceFinder.findLocalVoice(for: languageCode, from: localVoices) {
                        selectedVoice = .local(voice)
                    }
                    
                case .advanced, .basic:
                    let tier: RemoteVoice.Tier = newValue == .advanced ? .advanced : .basic
                    remoteVoices = VoiceFinder.remoteVoices(for: languageCode, tier: tier, from: allRemoteVoices)
                    if let voice = VoiceFinder.findRemoteVoice(for: languageCode, tier: tier, from: remoteVoices) {
                        selectedVoice = .remote(voice)
                    }
                }
            }
            .onChange(of: selectedVoice) { newValue in
                switch newValue {
                case .local(let voice):
                    Defaults.shared.defaultLocalVoiceForLanguage[languageCode] = voice.identifier
                    Defaults.shared.remoteVoiceTier = nil
                    
                case .remote(let voice):
                    switch voice.tier {
                    case .advanced:
                        Defaults.shared.defaultAdvancedRemoteVoiceForLanguage[languageCode] = voice

                    case .basic:
                        Defaults.shared.defaultBasicRemoteVoiceForLanguage[languageCode] = voice
                    }
                    Defaults.shared.remoteVoiceTier = voice.tier
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let selectedCode: String?
                        switch language {
                        case .auto:
                            selectedCode = nil
                            
                        case .language(let code):
                            selectedCode = code
                        }
                        dismiss(AccessibilityPopupVoiceChange(voice: selectedVoice, voiceLanguage: (selectedCode ?? detectedLanguage), preferredLanguage: selectedCode))
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
                    allRemoteVoices = result.voices
                    supportedRemoteLanguages.removeAll()
                    result.voices.forEach({ supportedRemoteLanguages.formUnion($0.locales) })
                    basicCreditsRemaining = result.credits.basic
                    advancedCreditsRemaining = result.credits.advanced
                    remoteVoices = VoiceFinder.remoteVoices(for: languageCode, tier: (type == .advanced ? .advanced : .basic), from: allRemoteVoices)
                    isLoading = false
                }, onFailure: { error in
                    DDLogError("SpeechVoicePickerView: can't load remote voices - \(error)")
                    isLoading = false
                    loadError = true
                }
            )
            .disposed(by: disposeBag)
    }
    
    private var canShowLanguage: Bool {
        switch type {
        case .local:
            return true
            
        case .advanced, .basic:
            return !allRemoteVoices.isEmpty
        }
    }
    
    private func createLanguages() -> [SpeechLanguagePickerView.Language] {
        switch type {
        case .local:
            return createLocalLanguages()
            
        case .advanced:
            return createRemoteLanguages(for: .advanced)
            
        case .basic:
            return createRemoteLanguages(for: .basic)
        }
    }
    
    private func createLocalLanguages() -> [SpeechLanguagePickerView.Language] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        var languageVariations: [String: [SpeechLanguagePickerView.LanguageVariation]] = [:]
        
        for voice in voices {
            let baseCode = String(voice.language.prefix(2))
            let variationName = Self.variationName(for: voice.language, baseLanguage: baseCode)
            let variation = SpeechLanguagePickerView.LanguageVariation(id: voice.language, name: variationName)
            
            if languageVariations[baseCode] == nil {
                languageVariations[baseCode] = []
            }
            if !languageVariations[baseCode]!.contains(where: { $0.id == variation.id }) {
                languageVariations[baseCode]!.append(variation)
            }
        }
        
        return languageVariations.keys
            .compactMap { baseCode -> SpeechLanguagePickerView.Language? in
                guard let name = Locale.current.localizedString(forLanguageCode: baseCode) else { return nil }
                let variations = languageVariations[baseCode]?.sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }) ?? []
                return SpeechLanguagePickerView.Language(id: baseCode, name: name, variations: variations)
            }
            .sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
    }
    
    private func createRemoteLanguages(for tier: RemoteVoice.Tier) -> [SpeechLanguagePickerView.Language] {
        var languageVariations: [String: [SpeechLanguagePickerView.LanguageVariation]] = [:]
        
        for voice in allRemoteVoices where voice.tier == tier {
            for locale in voice.locales {
                let baseCode = String(locale.prefix(2))
                let variationName = Self.variationName(for: locale, baseLanguage: baseCode)
                let variation = SpeechLanguagePickerView.LanguageVariation(id: locale, name: variationName)
                
                if languageVariations[baseCode] == nil {
                    languageVariations[baseCode] = []
                }
                if !languageVariations[baseCode]!.contains(where: { $0.id == variation.id }) {
                    languageVariations[baseCode]!.append(variation)
                }
            }
        }
        
        return languageVariations.keys
            .compactMap { baseCode -> SpeechLanguagePickerView.Language? in
                guard let name = Locale.current.localizedString(forLanguageCode: baseCode) else { return nil }
                let variations = languageVariations[baseCode]?.sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }) ?? []
                return SpeechLanguagePickerView.Language(id: baseCode, name: name, variations: variations)
            }
            .sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
    }
    
    private static func variationName(for languageCode: String, baseLanguage: String) -> String {
        let locale = Locale.current
        guard let localized = locale.localizedString(forIdentifier: languageCode) else { return languageCode }
        guard let localizedLanguage = locale.localizedString(forLanguageCode: baseLanguage), localized.hasPrefix(localizedLanguage) else { return localized }
        let suffix = String(localized[localized.index(localized.startIndex, offsetBy: localizedLanguage.count)..<localized.endIndex])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
        return suffix.isEmpty ? localized : suffix
    }
}

// swiftlint:disable private_over_fileprivate
fileprivate struct TypeSection: View {
    @Binding var type: SpeechVoicePickerView.VoiceType

    var body: some View {
        Section {
            HStack {
                Text("Advanced")
                Spacer()
                if case .advanced = type {
                    Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                type = .advanced
            }
            
            HStack {
                Text("Basic")
                Spacer()
                if case .basic = type {
                    Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                type = .basic
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
                    Text(Locale.current.localizedString(forIdentifier: code) ?? "Unknown").foregroundColor(.gray)
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

fileprivate struct RemainingTimeSection: View {
    let remainingTime: TimeInterval
    let warningThreshold: TimeInterval
    let formatter: DateComponentsFormatter
    
    private var formattedTime: String {
        let roundedUpSeconds = ceil(remainingTime / 60) * 60
        if roundedUpSeconds == 0 {
            return "0m"
        } else if roundedUpSeconds < 60 {
            return "<1m"
        } else {
            return formatter.string(from: roundedUpSeconds) ?? ""
        }
    }
    
    private var timeColor: Color {
        remainingTime < warningThreshold ? .red : .secondary
    }
    
    var body: some View {
        Section {
            HStack {
                Text("Remaining Time")
                Spacer()
                Text(formattedTime)
                    .foregroundColor(timeColor)
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
        Section("VOICES") {
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
        let utterance = AVSpeechUtterance(string: "My name is \(voice.name) and this is my voice")
        utterance.voice = voice
        synthetizer.speak(utterance)
    }
}

extension RemoteVoice: Identifiable {}

fileprivate struct RemoteVoicesSection: View {
    @Binding var voices: [RemoteVoice]
    @Binding var selectedVoice: SpeechVoice
    @State private var player: AVAudioPlayer?
    @State private var isLoading: Bool = false

    let language: String
    unowned let remoteVoicesController: RemoteVoicesController
    private let disposeBag: DisposeBag = .init()

    var body: some View {
        Section("VOICES") {
            ForEach(voices) { voice in
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
        .onDisappear {
            player?.stop()
        }
    }

    private func playSample(withVoice voice: RemoteVoice) {
        isLoading = true
        remoteVoicesController.downloadSample(voiceId: voice.id, language: "en-US")
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
