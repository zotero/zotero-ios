//
//  SpeechVoiceComponents.swift
//  Zotero
//
//  Created by Michal Rentka on 19.03.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import SwiftUI

import RxSwift

// MARK: - Types

enum SpeechLanguageChoice: Identifiable, Equatable {
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

// MARK: - Language Section

struct SpeechLanguageSection: View {
    @Binding var language: SpeechLanguageChoice
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

// MARK: - Local Voices Section

struct SpeechLocalVoicesSection: View {
    let groups: [LocaleLocalVoiceGroup]
    @Binding var selectedVoice: SpeechVoice?
    let language: String

    private let synthesizer: AVSpeechSynthesizer

    init(groups: [LocaleLocalVoiceGroup], selectedVoice: Binding<SpeechVoice?>, language: String) {
        self.groups = groups
        self._selectedVoice = selectedVoice
        self.language = language
        self.synthesizer = .init()
    }

    var body: some View {
        if groups.isEmpty {
            SpeechNoVoicesSection(language: language)
        } else {
            ForEach(groups) { group in
                Section(group.displayName.uppercased()) {
                    ForEach(group.voices) { voice in
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

struct SpeechRemoteVoicesSection: View {
    let groups: [LocaleRemoteVoiceGroup]
    @Binding var selectedVoice: SpeechVoice?
    let creditsRemaining: Int?
    unowned let remoteVoicesController: RemoteVoicesController

    @State private var player: AVAudioPlayer?
    @State private var loadingVoiceId: String?

    private let disposeBag = DisposeBag()

    var body: some View {
        ForEach(groups) { group in
            Section(group.displayName.uppercased()) {
                ForEach(group.voices) { voice in
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

struct SpeechLoadErrorSection: View {
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

struct SpeechNoVoicesSection: View {
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
