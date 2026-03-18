//
//  SpeechLanguagePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 22.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import SwiftUI

struct SpeechLanguagePickerView: View {
    struct Language: Identifiable {
        let id: String
        let name: String
        let locales: [String]
    }

    private let languages: [Language]
    private let detectedLanguage: String
    private let currentLanguage: SpeechVoicePickerView.Language
    private let onLanguageSelected: (Language?) -> Void
    @Binding private var navigationPath: NavigationPath
    @State private var isAutoEnabled: Bool

    private var detectedLanguageName: String {
        Locale.current.localizedString(forIdentifier: detectedLanguage) ?? detectedLanguage
    }

    init(
        currentLanguage: SpeechVoicePickerView.Language,
        detectedLanguage: String,
        languages: [Language],
        navigationPath: Binding<NavigationPath>,
        onLanguageSelected: @escaping (Language?) -> Void
    ) {
        self.currentLanguage = currentLanguage
        self.detectedLanguage = detectedLanguage
        self.languages = languages
        _navigationPath = navigationPath
        self.onLanguageSelected = onLanguageSelected
        _isAutoEnabled = State(initialValue: currentLanguage == .auto)
    }

    private var selectedBaseLanguage: String? {
        guard case .language(let code) = currentLanguage else { return nil }
        return code
    }

    var body: some View {
        List {
            Section {
                Toggle("\(L10n.Speech.automatic) - \(detectedLanguageName)", isOn: $isAutoEnabled)
                    .tint(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
            }

            if !isAutoEnabled {
                Section(header: Text("LANGUAGE")) {
                    ForEach(languages) { language in
                        HStack {
                            Text(language.name)
                            Spacer()
                            if selectedBaseLanguage == language.id {
                                Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onLanguageSelected(language)
                            navigationPath.removeLast()
                        }
                    }
                }
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isAutoEnabled) { newValue in
            if newValue {
                onLanguageSelected(nil)
            }
        }
    }
}

#Preview {
    SpeechLanguagePickerView(
        currentLanguage: .language("en"),
        detectedLanguage: "en-US",
        languages: [
            .init(id: "en", name: "English", locales: ["en-US", "en-GB"]),
            .init(id: "cs", name: "Czech", locales: ["cs-CZ"]),
            .init(id: "de", name: "German", locales: ["de-DE", "de-AT"])
        ],
        navigationPath: .constant(.init()),
        onLanguageSelected: { _ in }
    )
}
