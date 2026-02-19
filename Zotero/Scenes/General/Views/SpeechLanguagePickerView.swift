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
    struct LanguageVariation: Identifiable {
        let id: String
        let name: String
    }
    
    struct Language: Identifiable {
        let id: String
        let name: String
        let variations: [LanguageVariation]
    }

    private let languages: [Language]
    private let detectedLanguage: String
    @Binding private var selectedLanguage: SpeechVoicePickerView.Language
    @Binding private var navigationPath: NavigationPath
    @State private var variations: [LanguageVariation]
    @State private var isAutoEnabled: Bool
    
    private var detectedLanguageName: String {
        Locale.current.localizedString(forIdentifier: detectedLanguage) ?? detectedLanguage
    }

    init(
        selectedLanguage: Binding<SpeechVoicePickerView.Language>,
        detectedLanguage: String,
        languages: [Language],
        navigationPath: Binding<NavigationPath>
    ) {
        _selectedLanguage = selectedLanguage
        self.detectedLanguage = detectedLanguage
        self.languages = languages
        _navigationPath = navigationPath
        
        let initialVariations: [LanguageVariation]
        if case .language(let code) = selectedLanguage.wrappedValue {
            let baseCode = String(code.prefix(2))
            initialVariations = languages.first(where: { $0.id == baseCode })?.variations ?? []
        } else {
            initialVariations = []
        }
        _variations = State(initialValue: initialVariations)
        _isAutoEnabled = State(initialValue: selectedLanguage.wrappedValue == .auto)
    }
    
    private var selectedBaseLanguage: String? {
        guard case .language(let code) = selectedLanguage else { return nil }
        return String(code.prefix(2))
    }

    var body: some View {
        List {
            Section {
                Toggle("Auto (\(detectedLanguageName))", isOn: $isAutoEnabled)
                    .tint(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
            }
            
            if !isAutoEnabled {
                if variations.count > 1 {
                    Section(header: Text("VARIATION")) {
                        ForEach(variations) { variation in
                            HStack {
                                Text(variation.name)
                                Spacer()
                                if case .language(let code) = selectedLanguage, code == variation.id {
                                    Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedLanguage = .language(variation.id)
                            }
                        }
                    }
                }
                
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
                            variations = language.variations
                            if let firstVariation = language.variations.first {
                                selectedLanguage = .language(firstVariation.id)
                            } else {
                                selectedLanguage = .language(language.id)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isAutoEnabled) { newValue in
            if newValue {
                selectedLanguage = .auto
                variations = []
            } else if let firstLanguage = languages.first {
                variations = firstLanguage.variations
                if let firstVariation = firstLanguage.variations.first {
                    selectedLanguage = .language(firstVariation.id)
                } else {
                    selectedLanguage = .language(firstLanguage.id)
                }
            }
        }
    }
}

#Preview {
    SpeechLanguagePickerView(
        selectedLanguage: .constant(.language("en-US")),
        detectedLanguage: "en-US",
        languages: [
            .init(id: "en", name: "English", variations: [
                .init(id: "en-US", name: "United States"),
                .init(id: "en-GB", name: "United Kingdom")
            ]),
            .init(id: "cs", name: "Czech", variations: []),
            .init(id: "de", name: "German", variations: [])
        ],
        navigationPath: .constant(.init())
    )
}
