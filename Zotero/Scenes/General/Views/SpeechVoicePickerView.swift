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
    private struct Variation: Identifiable {
        var id: String
        let name: String
    }

    private let selectionChanged: (AVSpeechSynthesisVoice) -> Void

    @State private var language: String
    @State private var selectedVariation: String
    @State private var variations: [Variation]
    @State private var selectedVoice: AVSpeechSynthesisVoice
    @State private var voices: [AVSpeechSynthesisVoice]

    init(selectedVoice: AVSpeechSynthesisVoice, selectionChanged: @escaping (AVSpeechSynthesisVoice) -> Void) {
        var language = selectedVoice.language
        var variation = selectedVoice.language
        if language.contains("-") {
            let split = language.split(separator: "-")
            language = String(split[0])
            variation = split[0] + "_" + split[1]
        }
        self.selectedVoice = selectedVoice
        self.selectionChanged = selectionChanged
        self.language = language
        selectedVariation = variation
        (variations, voices) = Self.voicesAndVariations(for: language, voicesForVariation: selectedVoice.language)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Language")
                    Spacer()
                    Text(Locale.current.localizedString(forLanguageCode: language) ?? "Unknown").foregroundColor(.gray)
                    Image(systemName: "chevron.right").foregroundColor(.gray)
                }
            }

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
                        voices = Self.voices(for: variation.id.replacingOccurrences(of: "_", with: "-"))
                        selectedVoice = voices.first ?? selectedVoice
                    }
                }
            }

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
                    }
                }
            }
        }
        .listStyle(.grouped)
    }

    private static func voicesAndVariations(for language: String, voicesForVariation variation: String) -> (variations: [Variation], voices: [AVSpeechSynthesisVoice]) {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let locale = Locale.current
        let variations = Locale.availableIdentifiers
            .filter({ variation in variation.hasPrefix(language) && allVoices.contains(where: { $0.language == variation.replacingOccurrences(of: "_", with: "-") }) })
            .map({ Variation(id: $0, name: locale.localizedString(forIdentifier: $0) ?? $0) })
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        let voices = allVoices.filter({ $0.language == variation }).sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        return (variations, voices)
    }

    private static func voices(for variation: String) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
            .filter({ $0.language == variation })
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }
}

#Preview {
    SpeechVoicePickerView(selectedVoice: AVSpeechSynthesisVoice.speechVoices().first!, selectionChanged: { _ in })
}

extension AVSpeechSynthesisVoice: @retroactive Identifiable {
    public var id: String { identifier }
}
