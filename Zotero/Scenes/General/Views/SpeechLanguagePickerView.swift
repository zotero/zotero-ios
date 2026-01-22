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
    private struct Language: Identifiable {
        let id: String
        let name: String
    }

    private let languages: [Language]
    @Binding private var selectedLanguage: SpeechVoicePickerView.Language
    @Binding private var navigationPath: NavigationPath

    init(selectedLanguage: Binding<SpeechVoicePickerView.Language>, languages: [String], navigationPath: Binding<NavigationPath>) {
        _selectedLanguage = selectedLanguage
        _navigationPath = navigationPath
        let voices = AVSpeechSynthesisVoice.speechVoices()
        self.languages = languages.map({ Language(id: $0, name: Locale.current.localizedString(forIdentifier: $0) ?? $0) })
            .sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Auto")
                    Spacer()
                    if case .auto = selectedLanguage {
                        Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedLanguage = .auto
                    navigationPath.removeLast()
                }
                
                ForEach(languages) { language in
                    HStack {
                        Text(language.name)
                        Spacer()
                        if case .language(let code) = selectedLanguage, code == language.id {
                            Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedLanguage = .language(language.id)
                        navigationPath.removeLast()
                    }
                }
            }
        }
    }
}

#Preview {
    SpeechLanguagePickerView(selectedLanguage: .constant(.auto), languages: ["en"], navigationPath: .constant(.init()))
}
