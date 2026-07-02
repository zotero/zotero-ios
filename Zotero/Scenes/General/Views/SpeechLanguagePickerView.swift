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
    @Binding private var selectedLanguage: String
    @Binding private var navigationPath: NavigationPath

    init(selectedLanguage: Binding<String>, navigationPath: Binding<NavigationPath>) {
        _selectedLanguage = selectedLanguage
        _navigationPath = navigationPath
        let voices = AVSpeechSynthesisVoice.speechVoices()
        languages = Locale.availableIdentifiers
            .filter({ languageId in !languageId.contains("_") && voices.contains(where: { $0.language.contains(languageId) }) })
            .map({ Language(id: $0, name: Locale.current.localizedString(forIdentifier: $0) ?? $0) })
            .sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
    }

    var body: some View {
        List {
            Section {
                ForEach(languages) { language in
                    HStack {
                        Text(language.name)
                        Spacer()
                        if selectedLanguage == language.id {
                            Image(systemName: "checkmark").foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedLanguage = language.id
                        navigationPath.removeLast()
                    }
                }
            }
        }
    }
}

#Preview {
    SpeechLanguagePickerView(selectedLanguage: .constant("en"), navigationPath: .constant(.init()))
}
