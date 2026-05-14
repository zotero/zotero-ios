//
//  ReadAloudVoiceComponents.swift
//  Zotero
//
//  Created by Michal Rentka on 19.03.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import SwiftUI

import RxSwift

// MARK: - Types

enum ReadAloudLanguageChoice: Identifiable, Equatable {
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

    func baseLanguage(detectedLanguage: String) -> String {
        switch self {
        case .auto:
            return String(detectedLanguage.prefix(while: { $0 != "-" }))

        case .language(let code):
            return code
        }
    }

    func resolvedLocale(detectedLanguage: String) -> String {
        switch self {
        case .auto:
            return detectedLanguage

        case .language(let code):
            return LanguageDetector.canonicalVariation(for: code) ?? code
        }
    }
}

struct LocaleRemoteVoiceGroup: Identifiable {
    let locale: String
    let displayName: String
    let voices: [RemoteVoice]
    var id: String { locale }
}

struct LocaleLocalVoiceGroup: Identifiable {
    let locale: String
    let displayName: String
    let voices: [AVSpeechSynthesisVoice]
    var id: String { locale }
}

// MARK: - Type Section

struct ReadAloudTypeSection: View {
    @Binding var type: ReadAloudVoiceType

    var body: some View {
        Section {
            ForEach(ReadAloudVoiceType.allCases, id: \.self) { option in
                HStack {
                    Text(option.title)
                    Spacer()
                    if option == type {
                        Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    type = option
                }
            }
        }
    }
}

// MARK: - Voices Section (loading / error / no-voices / list)

struct ReadAloudVoicesSection: View {
    @ObservedObject var model: ReadAloudVoiceSelectionModel
    @Binding var selectedVoice: SpeechVoice?

    var body: some View {
        switch model.type {
        case .local:
            ReadAloudLocalVoicesSection(voices: model.currentLocalVoices, selectedVoice: $selectedVoice, language: model.baseLanguage)

        case .premium, .standard:
            if model.loadError {
                ReadAloudLoadErrorSection(retryAction: { model.loadVoices() })
            } else if model.voicesResponse != nil {
                if model.groupedRemoteVoices.isEmpty {
                    ReadAloudNoVoicesSection(language: model.baseLanguage)
                } else {
                    ReadAloudRemoteVoicesSection(
                        voices: model.currentRemoteVoices,
                        selectedVoice: $selectedVoice,
                        creditsRemaining: model.displayedCreditsRemaining,
                        remoteVoicesController: model.remoteVoicesController
                    )
                }
            } else if model.isLoading {
                Section(L10n.Speech.voices.uppercased()) {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
        }
    }
}

// MARK: - Language Section

struct ReadAloudLanguageSection: View {
    @Binding var language: ReadAloudLanguageChoice
    let detectedLanguage: String
    @Binding var navigationPath: NavigationPath

    private var detectedLanguageName: String {
        let baseLanguage = String(detectedLanguage.prefix(while: { $0 != "-" }))
        return Locale.current.localizedString(forLanguageCode: baseLanguage) ?? detectedLanguage
    }

    var body: some View {
        Section {
            HStack {
                Text("Language")
                Spacer()
                switch language {
                case .auto:
                    Text("\(L10n.Speech.automatic) - \(detectedLanguageName)").foregroundColor(.gray)

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

// MARK: - Region Section

struct ReadAloudRegionSection: View {
    let regions: [(locale: String, displayName: String)]
    @Binding var selectedLocale: String?

    var body: some View {
        Section(L10n.Speech.region.uppercased()) {
            ForEach(regions, id: \.locale) { region in
                HStack {
                    Text(region.displayName)
                    Spacer()
                    if selectedLocale == region.locale {
                        Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedLocale = region.locale
                }
            }
        }
    }
}

// MARK: - Local Voices Section

struct ReadAloudLocalVoicesSection: View {
    let voices: [AVSpeechSynthesisVoice]
    @Binding var selectedVoice: SpeechVoice?
    let language: String

    private let synthesizer: AVSpeechSynthesizer

    init(voices: [AVSpeechSynthesisVoice], selectedVoice: Binding<SpeechVoice?>, language: String) {
        self.voices = voices
        self._selectedVoice = selectedVoice
        self.language = language
        self.synthesizer = .init()
    }

    var body: some View {
        if voices.isEmpty {
            ReadAloudNoVoicesSection(language: language)
        } else {
            Section(L10n.Speech.voices.uppercased()) {
                ForEach(voices) { voice in
                    HStack {
                        Text(voice.name)
                        Spacer()
                        if case .local(let localVoice) = selectedVoice, localVoice.identifier == voice.identifier {
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
    }

    private func playSample(withVoice voice: AVSpeechSynthesisVoice) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: L10n.Speech.localSample(voice.name))
        utterance.voice = voice
        synthesizer.speak(utterance)
    }
}

// MARK: - Remote Voices Section

struct ReadAloudRemoteVoicesSection: View {
    let voices: [RemoteVoice]
    @Binding var selectedVoice: SpeechVoice?
    let creditsRemaining: Int?
    unowned let remoteVoicesController: RemoteVoicesController

    @State private var player: AVAudioPlayer?
    @State private var loadingVoiceId: String?

    private let disposeBag = DisposeBag()

    var body: some View {
        Section(L10n.Speech.voices.uppercased()) {
            ForEach(voices) { voice in
                HStack {
                    Text(voice.label)
                    Spacer()
                    if case .remote(let remoteVoice) = selectedVoice, remoteVoice.id == voice.id {
                        if loadingVoiceId == voice.id {
                            ProgressView()
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
                    guard loadingVoiceId == nil else { return }
                    player?.stop()
                    selectedVoice = .remote(voice)
                    playSample(for: voice)
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

    private func playSample(for voice: RemoteVoice) {
        loadingVoiceId = voice.id
        remoteVoicesController.downloadSample(voiceId: voice.id)
            .subscribe(
                onSuccess: { data in
                    loadingVoiceId = nil
                    do {
                        player = try AVAudioPlayer(data: data)
                        player?.prepareToPlay()
                        player?.play()
                    } catch {
                        // Ignore playback errors
                    }
                },
                onFailure: { _ in
                    loadingVoiceId = nil
                }
            )
            .disposed(by: disposeBag)
    }
}

// MARK: - Utility Sections

struct ReadAloudLoadErrorSection: View {
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

struct ReadAloudNoVoicesSection: View {
    let language: String

    private var languageName: String {
        Locale.current.localizedString(forIdentifier: language) ?? language
    }

    var body: some View {
        Section {
            Text(L10n.Speech.noVoicesForTier(languageName))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }
}

// MARK: - Extensions

extension RemoteVoice: Identifiable {}

extension AVSpeechSynthesisVoice: @retroactive Identifiable {
    public var id: String { identifier }

    var languageVariation: String {
        let locale = Locale.current
        guard let localized = locale.localizedString(forIdentifier: language) else { return name }
        guard let localizedLanguage = locale.localizedString(forLanguageCode: language), localized.starts(with: localizedLanguage) else { return name }
        return String(localized[localized.index(localized.startIndex, offsetBy: localizedLanguage.count)..<localized.endIndex])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
    }
}
