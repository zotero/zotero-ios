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
        case remote, local
    }

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
    @State private var remainingCredits: Int?
    
    private var languageCode: String {
        return language.code(detectedLanguage: detectedLanguage)
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
        localVoices = Self.localVoices(for: language ?? detectedLanguage)
        remoteVoices = []
        allRemoteVoices = []
        supportedRemoteLanguages = []
        disposeBag = .init()
        switch selectedVoice {
        case .local:
            type = .local
            
        case .remote:
            type = .remote
        }
        
        // TODO: Load remote voices
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                TypeSection(type: $type)
                if canShowLanguage {
                    LanguageSection(language: $language, navigationPath: $navigationPath)
                }
                switch type {
                case .local:
                    LocalVoicesSection(voices: $localVoices, selectedVoice: $selectedVoice)
                    
                case .remote:
                    if !allRemoteVoices.isEmpty {
                        RemoteVoicesSection(voices: $remoteVoices, selectedVoice: $selectedVoice, language: languageCode, remoteVoicesController: remoteVoicesController)
                    } else {
                        ActivityIndicatorView(style: .large, isAnimating: .constant(true))
                    }
                }
            }
            .listStyle(.grouped)
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self, destination: { value in
                if value == "languages" {
                    SpeechLanguagePickerView(selectedLanguage: $language, languages: createLanguages(), navigationPath: $navigationPath)
                }
            })
            .onChange(of: language) { newValue in
                let language = newValue.code(detectedLanguage: detectedLanguage)
                localVoices = Self.localVoices(for: language)
                remoteVoices = allRemoteVoices.filter({ voice in voice.locales.contains(where: { $0.contains(language) }) })
                
                switch type {
                case .local:
                    selectedVoice = localVoices.first.flatMap({ .local($0) }) ?? selectedVoice
                    
                case .remote:
                    selectedVoice = remoteVoices.first.flatMap({ .remote($0) }) ?? selectedVoice
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
                        dismiss(AccessibilityPopupVoiceChange(voice: selectedVoice, voiceLanguage: (selectedCode ?? detectedLanguage), preferredLanguage: selectedCode, remainingCredits: remainingCredits))
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
        remoteVoicesController.loadVoices()
            .subscribe(
                onSuccess: { (voices, credits) in
                    allRemoteVoices = voices
                    remainingCredits = credits
                    supportedRemoteLanguages.removeAll()
                    voices.forEach({ supportedRemoteLanguages.formUnion($0.locales) })
                    remoteVoices = allRemoteVoices.filter({ voice in voice.locales.contains(where: { $0.contains(languageCode) }) })
                }, onFailure: { error in
                    DDLogError("SpeechVoicePickerView: can't load remote voices - \(error)")
                }
            )
            .disposed(by: disposeBag)
    }
    
    private var canShowLanguage: Bool {
        switch type {
        case .local:
            return true
            
        case .remote:
            return !allRemoteVoices.isEmpty
        }
    }
    
    private func createLanguages() -> [String] {
        switch type {
        case .local:
            let voices = AVSpeechSynthesisVoice.speechVoices()
            return Locale.availableIdentifiers
                .filter({ languageId in !languageId.contains("_") && voices.contains(where: { $0.language.contains(languageId) }) })
            
        case .remote:
            return []
        }
    }

    private static func localVoices(for language: String) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
            .filter({ $0.language.contains(language) })
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }
}

// swiftlint:disable private_over_fileprivate
fileprivate struct TypeSection: View {
    @Binding var type: SpeechVoicePickerView.VoiceType

    var body: some View {
        Section {
            HStack {
                Text("Zotero Voices")
                Spacer()
                if case .remote = type {
                    Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                type = .remote
            }
            
            HStack {
                Text("Local Voices")
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
    @Binding var navigationPath: NavigationPath

    var body: some View {
        Section {
            HStack {
                Text("Language")
                Spacer()
                switch language {
                case .auto:
                    Text("Auto").foregroundColor(.gray)
                    
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

fileprivate struct LocalVoicesSection: View {
    private let synthetizer: AVSpeechSynthesizer
    private let shouldShowVariation: Bool

    @Binding var voices: [AVSpeechSynthesisVoice]
    @Binding var selectedVoice: SpeechVoice

    init(voices: Binding<[AVSpeechSynthesisVoice]>, selectedVoice: Binding<SpeechVoice>) {
        self._voices = voices
        self._selectedVoice = selectedVoice
        synthetizer = .init()
        shouldShowVariation = voices.count > 1 && Set(voices.wrappedValue.map({ $0.languageVariation })).count > 1
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
