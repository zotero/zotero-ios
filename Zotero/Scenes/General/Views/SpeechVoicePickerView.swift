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
    fileprivate struct Variation: Identifiable {
        var id: String
        let name: String
    }

    private let dismiss: (AVSpeechSynthesisVoice) -> Void

    @State private var language: String
    @State private var selectedVariation: String
    @State private var variations: [Variation]
    @State private var selectedVoice: AVSpeechSynthesisVoice
    @State private var voices: [AVSpeechSynthesisVoice]
    @State private var navigationPath: NavigationPath

    init(selectedVoice: AVSpeechSynthesisVoice, dismiss: @escaping (AVSpeechSynthesisVoice) -> Void) {
        var language = selectedVoice.language
        var variation = selectedVoice.language
        if language.contains("-") {
            let split = language.split(separator: "-")
            language = String(split[0])
            variation = split[0] + "_" + split[1]
        }
        self.selectedVoice = selectedVoice
        self.language = language
        self.dismiss = dismiss
        navigationPath = NavigationPath()
        selectedVariation = variation
        (variations, voices) = Self.voicesAndVariations(for: language, voicesForVariation: selectedVoice.language)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                LanguageSection(language: $language, navigationPath: $navigationPath)
                if variations.count > 1 {
                    VariationsSection(variations: $variations, selectedVariation: $selectedVariation)
                }
                VoicesSection(voices: $voices, selectedVoice: $selectedVoice)
            }
            .listStyle(.grouped)
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self, destination: { value in
                if value == "languages" {
                    SpeechLanguagePickerView(selectedLanguage: $language, navigationPath: $navigationPath)
                }
            })
            .onChange(of: language) { newValue in
                (variations, voices) = Self.voicesAndVariations(for: newValue)
                selectedVariation = variations.first?.id ?? selectedVariation
                selectedVoice = voices.first ?? selectedVoice
            }
            .onChange(of: selectedVariation) { variation in
                voices = Self.voices(for: variation.replacingOccurrences(of: "_", with: "-"))
                selectedVoice = voices.first ?? selectedVoice
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss(selectedVoice)
                    } label: {
                        Text("Close")
                    }
                }
            }
        }
    }

    private static func voicesAndVariations(for language: String, voicesForVariation variation: String? = nil) -> (variations: [Variation], voices: [AVSpeechSynthesisVoice]) {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let locale = Locale.current
        let variations = Locale.availableIdentifiers
            .filter({ variation in variation.hasPrefix(language) && allVoices.contains(where: { $0.language == variation.replacingOccurrences(of: "_", with: "-") }) })
            .map({ Variation(id: $0, name: convertVariationName(for: $0)) })
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        let voices = allVoices.filter({ $0.language == (variation ?? variations.first?.id) }).sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        return (variations, voices)

        func convertVariationName(for identifier: String) -> String {
            guard let localized = locale.localizedString(forIdentifier: identifier) else { return identifier }
            guard let localizedLanguage = locale.localizedString(forLanguageCode: language), localized.contains(localizedLanguage) else { return localized }
            return localized.replacingOccurrences(of: localizedLanguage, with: "").trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
        }
    }

    private static func voices(for variation: String) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
            .filter({ $0.language == variation })
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }
}

// swiftlint:disable private_over_fileprivate
fileprivate struct LanguageSection: View {
    @Binding var language: String
    @Binding var navigationPath: NavigationPath

    var body: some View {
        Section {
            HStack {
                Text("Language")
                Spacer()
                Text(Locale.current.localizedString(forLanguageCode: language) ?? "Unknown").foregroundColor(.gray)
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

fileprivate struct VariationsSection: View {
    @Binding var variations: [SpeechVoicePickerView.Variation]
    @Binding var selectedVariation: String

    var body: some View {
        Section("VARIATIONS") {
            ForEach(variations) { variation in
                HStack {
                    Text(variation.name)
                    Spacer()
                    if selectedVariation == variation.id {
                        Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedVariation = variation.id
                }
            }
        }
    }
}

fileprivate struct VoicesSection: View {
    private let synthetizer: AVSpeechSynthesizer = .init()

    @Binding var voices: [AVSpeechSynthesisVoice]
    @Binding var selectedVoice: AVSpeechSynthesisVoice

    var body: some View {
        Section("VOICES") {
            ForEach(voices) { voice in
                HStack {
                    Text(voice.name)
                    Spacer()
                    if selectedVoice == voice {
                        Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedVoice = voice
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
// swiftlint:enable private_over_fileprivate

#Preview {
    SpeechVoicePickerView(selectedVoice: AVSpeechSynthesisVoice.speechVoices().first!, dismiss: { _ in })
}

extension AVSpeechSynthesisVoice: @retroactive Identifiable {
    public var id: String { identifier }
}
