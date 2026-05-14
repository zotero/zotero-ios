//
//  ReadAloudOnboardingView.swift
//  Zotero
//
//  Created by Michal Rentka on 24.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import SwiftUI

struct ReadAloudOnboardingView: View {
    @StateObject private var model: ReadAloudVoiceSelectionModel
    @State private var navigationPath = NavigationPath()
    private let dismiss: (SpeechVoice?) -> Void

    init(
        language: String?,
        detectedLanguage: String,
        remoteVoicesController: RemoteVoicesController,
        dismiss: @escaping (SpeechVoice?) -> Void
    ) {
        _model = StateObject(wrappedValue: ReadAloudVoiceSelectionModel(
            initialVoice: nil,
            language: language,
            detectedLanguage: detectedLanguage,
            remoteVoicesController: remoteVoicesController,
            savesOnVoiceChange: false
        ))
        self.dismiss = dismiss
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                Text(L10n.Speech.Onboarding.title)
                    .font(.headline)
                    .padding(.top, 30)

                Picker("", selection: $model.type) {
                    ForEach([ReadAloudVoiceType.standard, .premium, .local], id: \.self) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 16)

                List {
                    descriptionSection

                    if model.canShowLanguage {
                        ReadAloudLanguageSection(language: $model.language, detectedLanguage: model.detectedLanguage, navigationPath: $navigationPath)
                    }
                    if model.currentRegions.count > 1 {
                        ReadAloudRegionSection(regions: model.currentRegions, selectedLocale: $model.selectedRegionLocale)
                    }
                    ReadAloudVoicesSection(model: model, selectedVoice: $model.selectedVoice)
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.cancel) {
                        dismiss(nil)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.done) {
                        model.saveCurrentVoicePreference()
                        dismiss(model.selectedVoice)
                    }
                }
            }
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
            .onAppear { model.onAppear() }
        }
    }

    private var descriptionSection: some View {
        Section {
            let bulletPoints = model.type.descriptionBulletPoints
            ForEach(Array(bulletPoints.enumerated()), id: \.element) { index, point in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(point)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: index == 0 ? 16 : 0,
                    leading: 20,
                    bottom: index == bulletPoints.count - 1 ? 16 : 0,
                    trailing: 20
                ))
            }
        }
    }
}
