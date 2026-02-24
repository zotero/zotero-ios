//
//  ReadAloudOnboardingView.swift
//  Zotero
//
//  Created by Michal Rentka on 24.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import SwiftUI

import RxSwift

struct ReadAloudOnboardingView: View {
    fileprivate enum VoiceTier: CaseIterable {
        case premium, standard, local
        
        var title: String {
            switch self {
            case .premium:
                return L10n.Accessibility.Speech.Onboarding.tierPremium
                
            case .standard:
                return L10n.Accessibility.Speech.Onboarding.tierStandard
                
            case .local:
                return L10n.Accessibility.Speech.Onboarding.tierLocal
            }
        }
        
        var description: String {
            switch self {
            case .premium:
                return L10n.Accessibility.Speech.Onboarding.descriptionPremium
                
            case .standard:
                return L10n.Accessibility.Speech.Onboarding.descriptionStandard
                
            case .local:
                return L10n.Accessibility.Speech.Onboarding.descriptionLocal
            }
        }
    }
    
    private unowned let remoteVoicesController: RemoteVoicesController
    private let language: String
    private let dismiss: (SpeechVoice?) -> Void
    private let disposeBag: DisposeBag
    
    @State private var selectedTier: VoiceTier = .standard
    @State private var selectedVoice: SpeechVoice?
    @State private var remoteVoices: [RemoteVoice] = []
    @State private var localVoices: [AVSpeechSynthesisVoice] = []
    @State private var isLoading: Bool = false
    @State private var loadError: Bool = false
    
    private var voicesForSelectedTier: [VoiceItem] {
        switch selectedTier {
        case .premium:
            return VoiceFinder.remoteVoices(for: language, tier: .premium, from: remoteVoices).map { .remote($0) }
            
        case .standard:
            return VoiceFinder.remoteVoices(for: language, tier: .standard, from: remoteVoices).map { .remote($0) }
            
        case .local:
            return localVoices.map { .local($0) }
        }
    }
    
    init(
        language: String,
        remoteVoicesController: RemoteVoicesController,
        dismiss: @escaping (SpeechVoice?) -> Void
    ) {
        self.language = language
        self.remoteVoicesController = remoteVoicesController
        self.dismiss = dismiss
        self.disposeBag = DisposeBag()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(L10n.Accessibility.Speech.Onboarding.title)
                    .font(.headline)
                    .padding(.top, 30)
                
                // Segmented control for tier selection
                Picker("", selection: $selectedTier) {
                    ForEach(VoiceTier.allCases, id: \.self) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                List {
                    // Description section
                    Section {
                        Text(selectedTier.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Voices section
                    if selectedTier == .local || !remoteVoices.isEmpty {
                        VoicesSection(
                            voices: voicesForSelectedTier,
                            selectedVoice: $selectedVoice,
                            remoteVoicesController: remoteVoicesController,
                            language: language
                        )
                    } else if isLoading {
                        Section(L10n.Accessibility.Speech.voices.uppercased()) {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                    } else if loadError {
                        Section(L10n.Accessibility.Speech.voices.uppercased()) {
                            VStack(spacing: 16) {
                                Text(L10n.Errors.Shareext.cantLoadData)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Button(action: loadVoices) {
                                    Text(L10n.retry)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                    }
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
                        if let selectedVoice {
                            saveVoicePreference(selectedVoice)
                        }
                        dismiss(selectedVoice)
                    }
                }
            }
            .onChange(of: selectedTier) { _ in
                updateSelectedVoiceForTier()
            }
            .onAppear {
                localVoices = VoiceFinder.localVoices(for: language)
                loadVoices()
            }
        }
    }
    
    private func loadVoices() {
        isLoading = true
        loadError = false
        remoteVoicesController.loadVoices()
            .subscribe(
                onSuccess: { result in
                    remoteVoices = result.voices
                    isLoading = false
                    updateSelectedVoiceForTier()
                },
                onFailure: { _ in
                    isLoading = false
                    loadError = true
                }
            )
            .disposed(by: disposeBag)
    }
    
    private func updateSelectedVoiceForTier() {
        switch selectedTier {
        case .premium:
            if let voice = VoiceFinder.findRemoteVoice(for: language, tier: .premium, from: remoteVoices) {
                selectedVoice = .remote(voice)
            }
            
        case .standard:
            if let voice = VoiceFinder.findRemoteVoice(for: language, tier: .standard, from: remoteVoices) {
                selectedVoice = .remote(voice)
            }
            
        case .local:
            if let voice = VoiceFinder.findLocalVoice(for: language, from: localVoices) {
                selectedVoice = .local(voice)
            }
        }
    }
    
    private func saveVoicePreference(_ voice: SpeechVoice) {
        switch voice {
        case .local(let avVoice):
            Defaults.shared.defaultLocalVoiceForLanguage[language] = avVoice.identifier
            Defaults.shared.remoteVoiceTier = nil
            
        case .remote(let remoteVoice):
            switch remoteVoice.tier {
            case .premium:
                Defaults.shared.defaultPremiumRemoteVoiceForLanguage[language] = remoteVoice
                
            case .standard:
                Defaults.shared.defaultStandardRemoteVoiceForLanguage[language] = remoteVoice
            }
            Defaults.shared.remoteVoiceTier = remoteVoice.tier
        }
    }
}

// MARK: - Voice Item

private enum VoiceItem: Identifiable {
    case local(AVSpeechSynthesisVoice)
    case remote(RemoteVoice)
    
    var id: String {
        switch self {
        case .local(let voice):
            return voice.identifier
            
        case .remote(let voice):
            return voice.id
        }
    }
    
    var name: String {
        switch self {
        case .local(let voice):
            return voice.name
            
        case .remote(let voice):
            return voice.label
        }
    }
    
    func matches(_ speechVoice: SpeechVoice?) -> Bool {
        guard let speechVoice else { return false }
        switch (self, speechVoice) {
        case (.local(let item), .local(let selected)):
            return item.identifier == selected.identifier
            
        case (.remote(let item), .remote(let selected)):
            return item.id == selected.id
            
        default:
            return false
        }
    }
    
    func toSpeechVoice() -> SpeechVoice {
        switch self {
        case .local(let voice):
            return .local(voice)
            
        case .remote(let voice):
            return .remote(voice)
        }
    }
}

// MARK: - Voices Section

private struct VoicesSection: View {
    let voices: [VoiceItem]
    @Binding var selectedVoice: SpeechVoice?
    unowned let remoteVoicesController: RemoteVoicesController
    let language: String
    
    @State private var player: AVAudioPlayer?
    @State private var loadingVoiceId: String?
    
    private let synthesizer = AVSpeechSynthesizer()
    private let disposeBag = DisposeBag()
    
    var body: some View {
        Section(L10n.Accessibility.Speech.voices.uppercased()) {
            if voices.isEmpty {
                Text(L10n.Accessibility.Speech.noVoicesForTier(Locale.current.localizedString(forIdentifier: language) ?? language))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(voices) { voice in
                    HStack {
                        Text(voice.name)
                        Spacer()
                        if voice.matches(selectedVoice) {
                            if loadingVoiceId == voice.id {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Asset.Colors.zoteroBlueWithDarkMode.swiftUIColor)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectVoice(voice)
                    }
                }
            }
        }
        .onDisappear {
            player?.stop()
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    private func selectVoice(_ voice: VoiceItem) {
        guard loadingVoiceId == nil else { return }
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        selectedVoice = voice.toSpeechVoice()
        playSample(for: voice)
    }
    
    private func playSample(for voice: VoiceItem) {
        switch voice {
        case .local(let avVoice):
            let utterance = AVSpeechUtterance(string: L10n.Accessibility.Speech.localSample(avVoice.name))
            utterance.voice = avVoice
            synthesizer.speak(utterance)
            
        case .remote(let remoteVoice):
            loadingVoiceId = voice.id
            remoteVoicesController.downloadSample(voiceId: remoteVoice.id, language: "en-US")
                .subscribe(
                    onSuccess: { data in
                        loadingVoiceId = nil
                        do {
                            player = try AVAudioPlayer(data: data)
                            player?.prepareToPlay()
                            player?.play()
                        } catch {
                            // Ignore playback errors
                        }
                    },
                    onFailure: { _ in
                        loadingVoiceId = nil
                    }
                )
                .disposed(by: disposeBag)
        }
    }
}
