//
//  CarPlayVoiceSettings.swift
//  Zotero
//
//  Created by Michal Rentka on 14.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import CarPlay
import Combine

import CocoaLumberjackSwift
import RxSwift

/// Read aloud voice settings in CarPlay. The same as `ReadAloudVoicePickerView`, built on the same `ReadAloudVoiceSelectionModel`:
/// a voice settings screen (type, language, region and voices) and a language screen.
@MainActor
final class CarPlayVoiceSettings {
    private unowned let interfaceController: CPInterfaceController
    private let model: ReadAloudVoiceSelectionModel
    private var cancellables: Set<AnyCancellable>
    private let sampleSynthesizer: AVSpeechSynthesizer
    private var samplePlayer: AVAudioPlayer?
    private var sampleDisposeBag: DisposeBag
    /// Remote voice whose sample is being downloaded.
    private var loadingSampleVoiceId: String?
    /// State of the "automatic" toggle in the language screen.
    private var isAutoLanguageEnabled: Bool
    /// Whether the language screen fits under the template depth limit.
    private let allowsLanguageScreen: Bool
    let settingsTemplate: CPListTemplate
    private(set) var languageTemplate: CPListTemplate?

    /// Voice and language selected in the settings, reported back like the picker does when it's closed.
    var voiceChange: ReadAloudVoiceChange? {
        return model.selectedVoice.flatMap({ ReadAloudVoiceChange(voice: $0, preferredLanguage: model.preferredLanguageForDismiss) })
    }

    private var detectedLanguageName: String {
        let baseLanguage = String(model.detectedLanguage.prefix(while: { $0 != "-" }))
        return Locale.current.localizedString(forLanguageCode: baseLanguage) ?? model.detectedLanguage
    }

    init(
        interfaceController: CPInterfaceController,
        selectedVoice: SpeechVoice,
        language: String?,
        detectedLanguage: String,
        remoteVoicesController: RemoteVoicesController,
        allowsLanguageScreen: Bool
    ) {
        self.interfaceController = interfaceController
        self.allowsLanguageScreen = allowsLanguageScreen
        model = ReadAloudVoiceSelectionModel(
            initialVoice: selectedVoice,
            language: language,
            detectedLanguage: detectedLanguage,
            remoteVoicesController: remoteVoicesController,
            savesOnVoiceChange: true
        )
        cancellables = []
        sampleSynthesizer = AVSpeechSynthesizer()
        sampleDisposeBag = DisposeBag()
        isAutoLanguageEnabled = model.language == .auto
        settingsTemplate = CPListTemplate(title: L10n.Settings.title, sections: [])

        observeModel()
        model.onAppear()
        reloadSettings()
    }

    /// Stops samples which might be playing, called when the settings are closed.
    func stopSamples() {
        sampleDisposeBag = DisposeBag()
        sampleSynthesizer.stopSpeaking(at: .immediate)
        samplePlayer?.stop()
        samplePlayer = nil
        loadingSampleVoiceId = nil
    }

    private func observeModel() {
        // Same as the `onChange` handlers of `ReadAloudVoicePickerView`. Published values are emitted before they're set, so
        // the handlers run afterwards on the main queue, like `onChange` does.
        model.$type
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.model.handleTypeChange()
            }
            .store(in: &cancellables)
        model.$selectedVoice
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.model.handleSelectedVoiceChange()
            }
            .store(in: &cancellables)
        model.$selectedRegionLocale
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.model.handleSelectedRegionChange()
            }
            .store(in: &cancellables)
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadSettings()
                self?.reloadLanguages()
            }
            .store(in: &cancellables)
    }

    // MARK: - Voice settings

    private func reloadSettings() {
        var sections: [CPListSection] = []
        if model.canShowLanguage && allowsLanguageScreen {
            sections.append(languageSection())
        }
        sections.append(typeSection())
        if model.currentRegions.count > 1 {
            sections.append(regionSection())
        }
        if let voicesSection = voicesSection() {
            sections.append(voicesSection)
        }
        settingsTemplate.updateSections(sections)
    }

    private func typeSection() -> CPListSection {
        let rows = ReadAloudVoiceType.allCases.map { type in
            let row = CPListItem(text: type.title, detailText: nil, image: nil, accessoryImage: checkmark(isVisible: type == model.type), accessoryType: .none)
            row.handler = { [weak self] _, completion in
                self?.model.type = type
                completion()
            }
            return row
        }
        return CPListSection(items: rows, header: L10n.Carplay.tiers, sectionIndexTitle: nil)
    }

    private func languageSection() -> CPListSection {
        let detail: String
        switch model.language {
        case .auto:
            detail = "\(L10n.Speech.automatic) - \(detectedLanguageName)"

        case .language(let code):
            detail = Locale.current.localizedString(forLanguageCode: code) ?? L10n.unknown
        }
        let row = CPListItem(text: L10n.Speech.language, detailText: detail, image: nil, accessoryImage: nil, accessoryType: .disclosureIndicator)
        row.handler = { [weak self] _, completion in
            self?.showLanguages()
            completion()
        }
        return CPListSection(items: [row])
    }

    private func regionSection() -> CPListSection {
        let rows = model.currentRegions.prefix(CPListTemplate.maximumItemCount).map { region in
            let row = CPListItem(text: region.displayName, detailText: nil, image: nil, accessoryImage: checkmark(isVisible: model.selectedRegionLocale == region.locale), accessoryType: .none)
            row.handler = { [weak self] _, completion in
                self?.model.selectedRegionLocale = region.locale
                completion()
            }
            return row
        }
        return CPListSection(items: Array(rows), header: L10n.Speech.region, sectionIndexTitle: nil)
    }

    /// Same states as `ReadAloudVoicesSection`: loading, load error, no voices and the list of voices.
    private func voicesSection() -> CPListSection? {
        switch model.type {
        case .local:
            let voices = model.currentLocalVoices
            guard !voices.isEmpty else { return noVoicesSection() }
            let rows = voices.prefix(CPListTemplate.maximumItemCount).map { voice in
                var isSelected = false
                if case .local(let localVoice) = model.selectedVoice {
                    isSelected = localVoice.identifier == voice.identifier
                }
                let row = CPListItem(text: voice.name, detailText: nil, image: nil, accessoryImage: checkmark(isVisible: isSelected), accessoryType: .none)
                row.handler = { [weak self] _, completion in
                    self?.model.selectedVoice = .local(voice)
                    self?.playSample(withVoice: voice)
                    completion()
                }
                return row
            }
            return CPListSection(items: Array(rows), header: L10n.Speech.voices, sectionIndexTitle: nil)

        case .premium, .standard:
            if model.loadError {
                let retry = CPListItem(text: L10n.retry, detailText: nil)
                retry.handler = { [weak self] _, completion in
                    self?.model.loadVoices()
                    completion()
                }
                return CPListSection(items: [messageRow(L10n.Errors.Shareext.cantLoadData), retry])
            }
            if model.voicesResponse != nil {
                guard !model.groupedRemoteVoices.isEmpty else { return noVoicesSection() }
                let rows = model.currentRemoteVoices.prefix(CPListTemplate.maximumItemCount).map { voice in
                    var isSelected = false
                    if case .remote(let remoteVoice) = model.selectedVoice {
                        isSelected = remoteVoice.id == voice.id
                    }
                    let detail = remainingTime(for: voice).map({ RemainingTimeFormatter.formatted($0) })
                    let row = CPListItem(text: voice.label, detailText: detail, image: nil, accessoryImage: checkmark(isVisible: isSelected), accessoryType: .none)
                    row.handler = { [weak self] _, completion in
                        guard let self, loadingSampleVoiceId == nil else {
                            completion()
                            return
                        }
                        samplePlayer?.stop()
                        model.selectedVoice = .remote(voice)
                        // CarPlay shows a loading indicator in the row until the sample is loaded.
                        playSample(for: voice, completion: completion)
                    }
                    return row
                }
                return CPListSection(items: Array(rows), header: L10n.Speech.voices, sectionIndexTitle: nil)
            }
            if model.isLoading {
                return CPListSection(items: [messageRow(L10n.Carplay.loading)], header: L10n.Speech.voices, sectionIndexTitle: nil)
            }
            return nil
        }
    }

    private func noVoicesSection() -> CPListSection {
        let languageName = Locale.current.localizedString(forIdentifier: model.baseLanguage) ?? model.baseLanguage
        return CPListSection(items: [messageRow(L10n.Speech.noVoicesForTier(languageName))])
    }

    private func remainingTime(for voice: RemoteVoice) -> TimeInterval? {
        guard let creditsRemaining = model.displayedCreditsRemaining, voice.creditsPerMinute > 0 else { return nil }
        let time = (TimeInterval(creditsRemaining) / TimeInterval(voice.creditsPerMinute)) * 60
        guard RemainingTimeFormatter.shouldDisplay(time) else { return nil }
        return time
    }

    // MARK: - Language

    private func showLanguages() {
        let template = CPListTemplate(title: L10n.Speech.language, sections: [])
        languageTemplate = template
        isAutoLanguageEnabled = model.language == .auto
        reloadLanguages()
        interfaceController.pushTemplate(template, animated: true) { _, error in
            if let error {
                DDLogError("CarPlayVoiceSettings: can't push language template - \(error)")
            }
        }
    }

    /// Same as `ReadAloudLanguagePickerView`: the automatic toggle and, when it's off, the list of languages.
    private func reloadLanguages() {
        guard let languageTemplate else { return }

        let automatic = CPListItem(
            text: "\(L10n.Speech.automatic) - \(detectedLanguageName)",
            detailText: nil,
            image: nil,
            accessoryImage: checkmark(isVisible: isAutoLanguageEnabled),
            accessoryType: .none
        )
        automatic.handler = { [weak self] _, completion in
            guard let self else {
                completion()
                return
            }
            isAutoLanguageEnabled.toggle()
            if isAutoLanguageEnabled {
                model.handleLanguageSelected(nil)
            }
            reloadLanguages()
            completion()
        }
        var sections = [CPListSection(items: [automatic])]

        if !isAutoLanguageEnabled {
            var selectedBaseLanguage: String?
            if case .language(let code) = model.language {
                selectedBaseLanguage = code
            }
            let rows = model.createLanguages().prefix(CPListTemplate.maximumItemCount).map { language in
                let row = CPListItem(text: language.name, detailText: nil, image: nil, accessoryImage: checkmark(isVisible: selectedBaseLanguage == language.id), accessoryType: .none)
                row.handler = { [weak self] _, completion in
                    guard let self else {
                        completion()
                        return
                    }
                    model.handleLanguageSelected(language)
                    if interfaceController.topTemplate === self.languageTemplate {
                        interfaceController.popTemplate(animated: true, completion: nil)
                    }
                    completion()
                }
                return row
            }
            sections.append(CPListSection(items: Array(rows), header: L10n.Speech.language, sectionIndexTitle: nil))
        }

        languageTemplate.updateSections(sections)
    }

    // MARK: - Samples

    private func playSample(withVoice voice: AVSpeechSynthesisVoice) {
        sampleSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: L10n.Speech.localSample(voice.name))
        utterance.voice = voice
        sampleSynthesizer.speak(utterance)
    }

    private func playSample(for voice: RemoteVoice, completion: @escaping () -> Void) {
        loadingSampleVoiceId = voice.id
        model.remoteVoicesController.downloadSample(voiceId: voice.id)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] data in
                    completion()
                    guard let self else { return }
                    loadingSampleVoiceId = nil
                    do {
                        samplePlayer = try AVAudioPlayer(data: data)
                        samplePlayer?.prepareToPlay()
                        samplePlayer?.play()
                    } catch {
                        // Ignore playback errors
                    }
                },
                onFailure: { [weak self] _ in
                    completion()
                    self?.loadingSampleVoiceId = nil
                }
            )
            .disposed(by: sampleDisposeBag)
    }

    // MARK: - Helpers

    private func checkmark(isVisible: Bool) -> UIImage? {
        return isVisible ? UIImage(systemName: "checkmark") : nil
    }

    private func messageRow(_ text: String) -> CPListItem {
        let row = CPListItem(text: text, detailText: nil)
        row.isEnabled = false
        return row
    }
}
