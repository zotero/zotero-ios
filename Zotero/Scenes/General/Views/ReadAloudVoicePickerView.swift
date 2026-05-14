//
//  ReadAloudVoicePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import SwiftUI

struct ReadAloudVoicePickerView: View {
    @StateObject private var model: ReadAloudVoiceSelectionModel
    @State private var navigationPath = NavigationPath()
    private let dismiss: (ReadAloudVoiceChange) -> Void

    init(
        selectedVoice: SpeechVoice,
        language: String?,
        detectedLanguage: String,
        remoteVoicesController: RemoteVoicesController,
        dismiss: @escaping (ReadAloudVoiceChange) -> Void
    ) {
        _model = StateObject(wrappedValue: ReadAloudVoiceSelectionModel(
            initialVoice: selectedVoice,
            language: language,
            detectedLanguage: detectedLanguage,
            remoteVoicesController: remoteVoicesController,
            savesOnVoiceChange: true
        ))
        self.dismiss = dismiss
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ReadAloudTypeSection(type: $model.type)
                if model.canShowLanguage {
                    ReadAloudLanguageSection(language: $model.language, detectedLanguage: model.detectedLanguage, navigationPath: $navigationPath)
                }
                if model.currentRegions.count > 1 {
                    ReadAloudRegionSection(regions: model.currentRegions, selectedLocale: $model.selectedRegionLocale)
                }
                ReadAloudVoicesSection(model: model, selectedVoice: $model.selectedVoice)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { value in
                if value == "languages" {
                    ReadAloudLanguagePickerView(
                        currentLanguage: model.language,
                        detectedLanguage: model.detectedLanguage,
                        languages: model.createLanguages(),
                        navigationPath: $navigationPath,
                        onLanguageSelected: { model.handleLanguageSelected($0) }
                    )
                }
            }
            .onChange(of: model.type) { _ in model.handleTypeChange() }
            .onChange(of: model.selectedVoice) { _ in model.handleSelectedVoiceChange() }
            .onChange(of: model.selectedRegionLocale) { _ in model.handleSelectedRegionChange() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        guard let voice = model.selectedVoice else { return }
                        dismiss(ReadAloudVoiceChange(voice: voice, preferredLanguage: model.preferredLanguageForDismiss))
                    } label: {
                        Text("Close")
                    }
                }
            }
            .onAppear { model.onAppear() }
        }
    }
}

#Preview {
    ReadAloudVoicePickerView(
        selectedVoice: .local(AVSpeechSynthesisVoice.speechVoices().first!),
        language: nil,
        detectedLanguage: "en",
        remoteVoicesController: RemoteVoicesController(apiClient: ZoteroApiClient(baseUrl: ApiConstants.baseUrlString, configuration: .default)),
        dismiss: { _ in }
    )
}
