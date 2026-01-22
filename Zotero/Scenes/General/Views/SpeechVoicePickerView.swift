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

//    private unowned let apiClient: ApiClient
    private let detectedLanguage: String
    private let dismiss: (SpeechVoice, String?) -> Void

    @State private var type: VoiceType
    @State private var language: Language
    @State private var selectedVoice: SpeechVoice
    @State private var localVoices: [AVSpeechSynthesisVoice]
    @State private var remoteVoices: [RemoteVoice]
    @State private var navigationPath: NavigationPath

    init(selectedVoice: SpeechVoice, language: String?, detectedLanguage: String, dismiss: @escaping (SpeechVoice, String?) -> Void) {
        self.selectedVoice = selectedVoice
        self.language = language.flatMap({ .language($0) }) ?? .auto
        self.detectedLanguage = detectedLanguage
        self.dismiss = dismiss
        navigationPath = NavigationPath()
        localVoices = Self.localVoices(for: language ?? detectedLanguage)
        remoteVoices = []
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
                LanguageSection(language: $language, navigationPath: $navigationPath)
                switch type {
                case .local:
                    LocalVoicesSection(voices: $localVoices, selectedVoice: $selectedVoice)
                    
                case .remote:
                    RemoteVoicesSection(voices: $remoteVoices, selectedVoice: $selectedVoice)
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
                localVoices = Self.localVoices(for: newValue.code(detectedLanguage: detectedLanguage))
                // TODO: - remoteVoices = allRemoteVoices[newValue.code(detectedLanguage: detectedLanguage)] ?? []
                
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
                        dismiss(selectedVoice, selectedCode)
                    } label: {
                        Text("Close")
                    }
                }
            }
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
            .filter({ $0.language == language })
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
    private let synthetizer: AVSpeechSynthesizer = .init()

    @Binding var voices: [AVSpeechSynthesisVoice]
    @Binding var selectedVoice: SpeechVoice

    var body: some View {
        Section("VOICES") {
            ForEach(voices) { voice in
                HStack {
                    Text(voice.name)
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

    var body: some View {
        Section("VOICES") {
            ForEach(voices) { voice in
                HStack {
                    Text(voice.label)
                    Spacer()
                    if case .remote(let remoteVoice) = selectedVoice, remoteVoice == voice {
                        Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedVoice = .remote(voice)
                    playSample(withVoice: voice)
                }
            }
        }
    }

    private func playSample(withVoice voice: RemoteVoice) {
        // TODO: - Add speech manager sample
    }
}
// swiftlint:enable private_over_fileprivate

#Preview {
    SpeechVoicePickerView(
        selectedVoice: .local(AVSpeechSynthesisVoice.speechVoices().first!),
        language: nil,
        detectedLanguage: "en",
//        apiClient: ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: .default),
        dismiss: { _, _ in }
    )
}

extension AVSpeechSynthesisVoice: @retroactive Identifiable {
    public var id: String { identifier }
}
