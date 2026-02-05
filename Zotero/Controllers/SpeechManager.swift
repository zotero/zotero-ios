//
//  SpeechManager.swift
//  Zotero
//
//  Created by Michal Rentka on 11.03.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFoundation
import NaturalLanguage

import CocoaLumberjackSwift
import RxCocoa

protocol SpeechManagerDelegate: AnyObject {
    associatedtype Index: Hashable

    func getCurrentPageIndex() -> Index
    func getNextPageIndex(from currentPageIndex: Index) -> Index?
    func getPreviousPageIndex(from currentPageIndex: Index) -> Index?
    func text(for indices: [Index], completion: @escaping ([Index: String]?) -> Void)
    func moved(to pageIndex: Index)
}

enum SpeechState {
    case speaking, paused, stopped, loading

    var isStopped: Bool {
        switch self {
        case .speaking, .loading, .paused:
            return false

        case .stopped:
            return true
        }
    }
    
    var isPaused: Bool {
        switch self {
        case .speaking, .loading, .stopped:
            return false

        case .paused:
            return true
        }
    }
    
    var isSpeaking: Bool {
        switch self {
        case .stopped, .loading, .paused:
            return false

        case .speaking:
            return true
        }
    }
}

enum SpeechVoice {
    case local(AVSpeechSynthesisVoice)
    case remote(RemoteVoice)
}

final class SpeechManager<Delegate: SpeechManagerDelegate>: NSObject, VoiceProcessorDelegate {
    private enum Error: Swift.Error {
        case cantGetText
    }
    
    struct SpeechData {
        let index: Delegate.Index
        let range: NSRange
        
        func copy(range: NSRange) -> SpeechData {
            return SpeechData(index: index, range: range)
        }
    }

    private var processor: VoiceProcessor!
    private var speechData: SpeechData?
    private var cachedPages: [Delegate.Index: String]
    private weak var delegate: Delegate?
    private lazy var paragraphRegex: NSRegularExpression? = {
        return try? NSRegularExpression(pattern: "[\r\n]{1,}")
    }()

    let state: BehaviorRelay<SpeechState>
    var voice: SpeechVoice? { processor.speechVoice }
    var language: String? { processor.preferredLanguage }
    var speechRateModifier: Float { processor.speechRateModifier }
    var detectedLanguage: String {
        guard let text = speechData.flatMap({ cachedPages[$0.index] }) else { return "en" }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }
    fileprivate var speechRange: NSRange? {
        return speechData?.range
    }

    init(delegate: Delegate, voiceLanguage: String?, useRemoteVoices: Bool) {
        self.delegate = delegate
        cachedPages = [:]
        state = BehaviorRelay(value: .loading)
        super.init()
        if useRemoteVoices {
            processor = RemoteVoiceProcessor(language: voiceLanguage, speechRateModifier: 1, delegate: self)
        } else {
            processor = LocalVoiceProcessor(language: voiceLanguage, speechRateModifier: 1, delegate: self)
        }
        processor.speechRateModifier = speechRateModifier
    }

    // MARK: - Actions

    func start() {
        guard let delegate else {
            DDLogError("SpeechManager: can't get delegate")
            return
        }

        let index = delegate.getCurrentPageIndex()
        if let page = cachedPages[index] {
            go(to: page, pageIndex: index, reportPageChange: false)
            return
        }

        state.accept(.loading)
        getData(for: [index], from: delegate) { [weak self] pages in
            guard let self, let pages, let page = pages[index] else {
                self?.state.accept(.stopped)
                return
            }
            cachedPages = pages
            guard state.value == .loading else { return }
            go(to: page, pageIndex: index, reportPageChange: false)
        }
    }
    
    func pause() {
        processor.pause()
    }

    func resume() {
        processor.resume()
    }

    func stop() {
        processor.stop()
    }

    func set(voice: SpeechVoice, voiceLanguage: String, preferredLanguage: String?) {
        switch voice {
        case .local(let voice):
            if let processor = processor as? LocalVoiceProcessor {
                processor.set(voice: voice, voiceLanguage: voiceLanguage, preferredLanguage: preferredLanguage)
            } else {
                let _processor = LocalVoiceProcessor(
                    language: preferredLanguage,
                    speechRateModifier: processor.speechRateModifier,
                    delegate: self
                )
                _processor.set(voice: voice, voiceLanguage: voiceLanguage, preferredLanguage: preferredLanguage)
                // TODO: - start speaking?
                processor = _processor
            }
            
        case .remote(let voice):
            if let processor = processor as? RemoteVoiceProcessor {
                processor.set(voice: voice, voiceLanguage: voiceLanguage, preferredLanguage: preferredLanguage)
            } else {
                let _processor = RemoteVoiceProcessor(
                    language: preferredLanguage,
                    speechRateModifier: processor.speechRateModifier,
                    delegate: self
                )
                _processor.set(voice: voice, voiceLanguage: voiceLanguage, preferredLanguage: preferredLanguage)
                // TODO: - start speaking?
                processor = _processor
            }
        }
    }

    func set(rateModifier: Float) {
        processor.speechRateModifier = rateModifier
    }

    private func getData(for indices: [Delegate.Index], from delegate: Delegate, completion: @escaping (([Delegate.Index: String])?) -> Void) {
        delegate.text(for: indices) { texts in
            guard let texts, texts.count == indices.count else {
                completion(nil)
                return
            }
            completion(texts)
        }
    }

    private func go(to page: String, pageIndex: Delegate.Index, speechStartIndex: Int? = nil, reportPageChange: Bool = true) {
        speechData = SpeechData(index: pageIndex, range: NSRange())
        processor.speak(text: page, startIndex: speechStartIndex ?? 0, shouldDetectVoice: true)

        guard let delegate else { return }

        if reportPageChange {
            delegate.moved(to: pageIndex)
        }

        // Cache next/previous page after page change if needed
        var indices: [Delegate.Index] = []
        if let index = delegate.getPreviousPageIndex(from: pageIndex), cachedPages[index] == nil {
            indices.append(index)
        }
        if let index = delegate.getNextPageIndex(from: pageIndex), cachedPages[index] == nil {
            indices.append(index)
        }
        if !indices.isEmpty {
            getData(for: indices, from: delegate) { [weak self] pages in
                guard let self else { return }
                for (index, page) in pages ?? [:] {
                    cachedPages[index] = page
                }
            }
        }
    }

    private func skip(to index: Int, on page: String) {
        processor.speak(text: page, startIndex: index, shouldDetectVoice: false)
    }

    func forward() {
        guard let speechData, let currentPage = cachedPages[speechData.index] else { return }

        if let index = findNextIndex(on: currentPage, speechRange: speechData.range) {
            DDLogInfo("SpeechManager: forward to \(index); \(speechData.range.location); \(speechData.range.length)")
            skip(to: index, on: currentPage)
        } else if let nextIndex = delegate?.getNextPageIndex(from: speechData.index), let page = cachedPages[nextIndex] {
            go(to: page, pageIndex: nextIndex)
        } else {
            stop()
        }

        func findNextIndex(on page: String, speechRange: NSRange) -> Int? {
            guard let paragraphRegex else { return nil }
            let matches = paragraphRegex.matches(in: page, range: NSRange(page.index(page.startIndex, offsetBy: speechRange.location + speechRange.length)..., in: page))
            guard let range = matches.first?.range else { return nil }
            return range.location + range.length
        }
    }

    func backward() {
        guard let speechData, let currentPage = cachedPages[speechData.index] else { return }
  
        if let index = findPreviousIndex(in: currentPage, endIndex: currentPage.index(currentPage.startIndex, offsetBy: speechData.range.location)) {
            DDLogInfo("SpeechManager: backward to \(index); \(speechData.range.location); \(speechData.range.length)")
            skip(to: index, on: currentPage)
        } else if speechData.range.location != 0 {
            skip(to: 0, on: currentPage)
        } else if let previousIndex = delegate?.getPreviousPageIndex(from: speechData.index),
                  let previousPage = cachedPages[previousIndex],
                  let speechIndex = findPreviousIndex(in: previousPage, endIndex: previousPage.endIndex) {
            go(to: previousPage, pageIndex: previousIndex, speechStartIndex: speechIndex)
        } else {
            stop()
        }

        func findPreviousIndex(in text: String, endIndex: String.Index) -> Int? {
            guard let paragraphRegex else { return nil }
            let range = NSRange(text.startIndex..<endIndex, in: text)
            let matches = paragraphRegex.matches(in: text, range: range)
            if matches.count > 1 {
                let matchRange = matches[matches.count - 2].range
                return matchRange.location + matchRange.length
            }
            return nil
        }
    }
    
    // MARK: - VoiceProcessorDelegate
    
    func didFinishSpeaking() {
        speechData = nil
        cachedPages = [:]
    }

    func goToNextPageIfAvailable() -> Bool {
        guard let speechData, let nextIndex = delegate?.getNextPageIndex(from: speechData.index), let page = cachedPages[nextIndex] else {
            return false
        }
        go(to: page, pageIndex: nextIndex)
        return true
    }
    
    func speechRangeWillChange(to range: NSRange) {
        guard let speechData else { return }
        self.speechData = speechData.copy(range: range)
    }
}

extension AVSpeechSynthesisVoice {
    var baseLanguage: String {
        if let index = language.firstIndex(of: "-") {
            return String(language[language.startIndex..<index])
        }
        return language
    }
}

private protocol VoiceProcessor {
    var speechVoice: SpeechVoice? { get }
    var preferredLanguage: String? { get }
    var speechRateModifier: Float { get set }
    
    func speak(text: String, startIndex: Int, shouldDetectVoice: Bool)
    func pause()
    func resume()
    func stop()
}

private protocol VoiceProcessorDelegate: AnyObject {
    var state: BehaviorRelay<SpeechState> { get }
    var speechRange: NSRange? { get }

    func goToNextPageIfAvailable() -> Bool
    func didFinishSpeaking()
    func speechRangeWillChange(to range: NSRange)
}

private final class LocalVoiceProcessor: NSObject, VoiceProcessor {
    private struct PageData {
        // Text to read
        let text: String
        // Voice used for this page
        let voice: AVSpeechSynthesisVoice
    }

    private let synthesizer: AVSpeechSynthesizer
    private unowned let delegate: VoiceProcessorDelegate

    private var text: String?
    private(set) var preferredLanguage: String?
    private var voice: AVSpeechSynthesisVoice?
    private var shouldReloadUtteranceOnResume = false
    private var ignoreFinishCallCount = 0
    var speechRateModifier: Float {
        didSet {
            utteranceChanged()
        }
    }
    var speechVoice: SpeechVoice? {
        return voice.flatMap({ .local($0) })
    }

    init(language: String?, speechRateModifier: Float, delegate: VoiceProcessorDelegate) {
        preferredLanguage = language
        self.speechRateModifier = speechRateModifier
        self.delegate = delegate
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, startIndex: Int, shouldDetectVoice: Bool) {
        if synthesizer.isSpeaking {
            ignoreFinishCallCount += 1
            synthesizer.stopSpeaking(at: .immediate)
        }

        self.text = text
        let remainingText = String(text[text.index(text.startIndex, offsetBy: startIndex)..<text.endIndex])

        if voice == nil || shouldDetectVoice {
            voice = voice(for: remainingText)
        }

        let utterance = AVSpeechUtterance(string: remainingText)
        utterance.voice = voice
        utterance.rate = 0.5 * speechRateModifier
        synthesizer.speak(utterance)
    }
    
    func pause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard synthesizer.isPaused else { return }

        if !shouldReloadUtteranceOnResume {
            synthesizer.continueSpeaking()
        } else {
            reloadUtterance()
        }
    }

    func stop() {
        guard synthesizer.isSpeaking || synthesizer.isPaused || delegate.state.value == .loading else { return }
        if delegate.state.value == .loading {
            finishSpeaking()
        } else {
            // Ignore finish delegate, which would move us to another page
            ignoreFinishCallCount = 1
            synthesizer.stopSpeaking(at: .immediate)
            finishSpeaking()
        }
    }

    func set(voice: AVSpeechSynthesisVoice, voiceLanguage: String, preferredLanguage: String?) {
        guard self.voice?.identifier != voice.identifier else { return }
        Defaults.shared.defaultLocalVoiceForLanguage[voiceLanguage] = voice.identifier
        Defaults.shared.isUsingRemoteVoice = false
        self.preferredLanguage = preferredLanguage
        self.voice = voice
        utteranceChanged()
    }

    private func utteranceChanged() {
        if synthesizer.isPaused {
            shouldReloadUtteranceOnResume = true
        } else if synthesizer.isSpeaking {
            reloadUtterance()
        }
    }

    private func reloadUtterance() {
        guard let text, let speechRange = delegate.speechRange else { return }
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        }
        speak(text: text, startIndex: speechRange.location, shouldDetectVoice: false)
    }

    private func voice(for text: String) -> AVSpeechSynthesisVoice {
        if let preferredLanguage {
            return findVoice(for: preferredLanguage)
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage?.rawValue ?? "en"
        return findVoice(for: language)
    }

    private func findVoice(for language: String) -> AVSpeechSynthesisVoice {
        let voiceId = Defaults.shared.defaultLocalVoiceForLanguage[language]
        return AVSpeechSynthesisVoice.speechVoices().first(where: isProperVoice) ?? AVSpeechSynthesisVoice(identifier: "en-US")!

        func isProperVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
            if let voiceId {
                return voice.identifier == voiceId
            }
            return voice.language.starts(with: language)
        }
    }
    
    private func finishSpeaking() {
        text = nil
        voice = nil
        shouldReloadUtteranceOnResume = false
        ignoreFinishCallCount = 0
        delegate.didFinishSpeaking()
        delegate.state.accept(.stopped)
    }
}

extension LocalVoiceProcessor: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeaking()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        delegate.state.accept(.paused)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        delegate.state.accept(.speaking)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        delegate.state.accept(.speaking)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard ignoreFinishCallCount <= 0 else {
            ignoreFinishCallCount -= 1
            return
        }

        if !delegate.goToNextPageIfAvailable() {
            finishSpeaking()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard characterRange.length > 0 else { return }
        delegate.speechRangeWillChange(to: characterRange)
    }
}

private final class RemoteVoiceProcessor: VoiceProcessor {
    private unowned let delegate: VoiceProcessorDelegate

    private var text: String?
    private(set) var preferredLanguage: String?
    private var voice: RemoteVoice?
    var speechRateModifier: Float
    var speechVoice: SpeechVoice? {
        return voice.flatMap({ .remote($0) })
    }

    init(language: String?, speechRateModifier: Float, delegate: VoiceProcessorDelegate) {
        preferredLanguage = language
        self.speechRateModifier = speechRateModifier
        self.delegate = delegate
    }

    func set(voice: RemoteVoice, voiceLanguage: String, preferredLanguage: String?) {
        self.preferredLanguage = preferredLanguage
        self.voice = voice
        Defaults.shared.defaultRemoteVoiceForLanguage[voiceLanguage] = voice
        Defaults.shared.isUsingRemoteVoice = true
    }

    func speak(text: String, startIndex: Int, shouldDetectVoice: Bool) {
        self.text = text
        delegate.state.accept(.speaking)
    }

    func pause() {
        delegate.state.accept(.paused)
    }

    func resume() {
        delegate.state.accept(.speaking)
    }

    func stop() {
        guard delegate.state.value == .loading else { return } // TODO: - check for active speaking
        if delegate.state.value == .loading {
            delegate.state.accept(.stopped)
        } else {
            delegate.state.accept(.stopped)
        }
    }
}
