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
}

private struct SpeechData {
    let startIndex: Int
    let speakingRange: NSRange

    func copy(with localRange: NSRange) -> SpeechData {
        return SpeechData(startIndex: startIndex, speakingRange: localRange)
    }

    var globalRange: NSRange {
        return NSRange(location: startIndex + speakingRange.location, length: speakingRange.length)
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

    private var processor: VoiceProcessor!
    fileprivate var speech: SpeechData?
    private var cachedPages: [Delegate.Index: String]
    private var currentIndex: Delegate.Index?
    private weak var delegate: Delegate?
    private lazy var paragraphRegex: NSRegularExpression? = {
        return try? NSRegularExpression(pattern: "[\r\n]{1,}")
    }()
    
    let state: BehaviorRelay<SpeechState>
    var isSpeaking: Bool { processor.isSpeaking }
    var isPaused: Bool { processor.isPaused }
    var voice: SpeechVoice? { processor.speechVoice }
    var language: String? { processor.preferredLanguage }
    var speechRateModifier: Float { processor.speechRateModifier }
    var detectedLanguage: String {
        guard let text = currentPageText else { return "en" }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    init(delegate: Delegate, voiceLanguage: String?, useRemoteVoices: Bool) {
        self.delegate = delegate
        cachedPages = [:]
        state = BehaviorRelay(value: .loading)
        super.init()
        if useRemoteVoices {
            processor = RemoteVoiceProcessor(language: voiceLanguage, speechRateModifier: 1, state: state)
        } else {
            processor = LocalVoiceProcessor(language: voiceLanguage, speechRateModifier: 1, state: state, delegate: self)
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

    func set(voice: SpeechVoice, preferredLanguage: String?) {
        switch voice {
        case .local(let voice):
            if let processor = processor as? LocalVoiceProcessor {
                processor.set(voice: voice, preferredLanguage: preferredLanguage)
            } else {
                let _processor = LocalVoiceProcessor(
                    language: preferredLanguage,
                    speechRateModifier: processor.speechRateModifier,
                    state: state,
                    delegate: self
                )
                _processor.set(voice: voice, preferredLanguage: preferredLanguage)
                processor = _processor
            }
            
        case .remote(let voice):
            if let processor = processor as? RemoteVoiceProcessor {
                processor.set(voice: voice, preferredLanguage: preferredLanguage)
            } else {
                let _processor = RemoteVoiceProcessor(
                    language: preferredLanguage,
                    speechRateModifier: processor.speechRateModifier,
                    state: state
                )
                _processor.set(voice: voice, preferredLanguage: preferredLanguage)
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
        let text: String
        if let index = speechStartIndex {
            text = String(page[page.index(page.startIndex, offsetBy: index)..<page.endIndex])
        } else {
            text = page
        }
        currentIndex = pageIndex
        speech = SpeechData(startIndex: speechStartIndex ?? 0, speakingRange: NSRange(location: 0, length: 0))
        processor.speak(text: text, shouldDetectVoice: true)

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
        speech = SpeechData(startIndex: index, speakingRange: NSRange(location: 0, length: 0))
        let text = page[page.index(page.startIndex, offsetBy: index)..<page.endIndex]
        processor.speak(text: String(text), shouldDetectVoice: false)
    }

    func forward() {
        guard let currentIndex, let currentPage = cachedPages[currentIndex], let speech else { return }

        if let index = findNextIndex(on: currentPage, speechRange: speech.globalRange) {
            DDLogInfo("SpeechManager: forward to \(index); \(speech.startIndex); \(speech.speakingRange.location); \(speech.speakingRange.length)")
            skip(to: index, on: currentPage)
        } else if let nextIndex = delegate?.getNextPageIndex(from: currentIndex), let page = cachedPages[nextIndex] {
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
        guard let currentIndex, let currentPage = cachedPages[currentIndex], let speech else { return }
  
        if let index = findPreviousIndex(in: currentPage, endIndex: currentPage.index(currentPage.startIndex, offsetBy: speech.globalRange.location)) {
            DDLogInfo("SpeechManager: backward to \(index); \(speech.startIndex); \(speech.speakingRange.location); \(speech.speakingRange.length)")
            skip(to: index, on: currentPage)
        } else if speech.startIndex != 0 {
            skip(to: 0, on: currentPage)
        } else if let previousIndex = delegate?.getPreviousPageIndex(from: currentIndex),
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

    private func cleanup() {
        speech = nil
        currentIndex = nil
        cachedPages = [:]
    }
    
    // MARK: - VoiceProcessorDelegate
    
    var currentPageText: String? {
        return currentIndex.flatMap({ cachedPages[$0] })
    }
    
    var nextPageText: String? {
        return currentIndex.flatMap({ delegate?.getNextPageIndex(from: $0) }).flatMap({ cachedPages[$0] })
    }
    
    func didFinishSpeaking() {
        cleanup()
    }
    
    func goToNextPageIfAvailable() -> Bool {
        guard let currentIndex, let nextIndex = delegate?.getNextPageIndex(from: currentIndex), let page = cachedPages[nextIndex] else {
            return false
        }
        go(to: page, pageIndex: nextIndex)
        return true
    }
    
    func speechRangeWillChange(to range: NSRange) {
        guard currentIndex != nil else { return }
        speech = speech?.copy(with: range)
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
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    var state: BehaviorRelay<SpeechState> { get }
    var speechVoice: SpeechVoice? { get }
    var preferredLanguage: String? { get }
    var speechRateModifier: Float { get set }
    
    func speak(text: String, shouldDetectVoice: Bool)
    func pause()
    func resume()
    func stop()
}

private protocol VoiceProcessorDelegate: AnyObject {
    var currentPageText: String? { get }
    var nextPageText: String? { get }
    var speech: SpeechData? { get }

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

    let state: BehaviorRelay<SpeechState>
    private let synthesizer: AVSpeechSynthesizer
    private unowned let delegate: VoiceProcessorDelegate

    private(set) var preferredLanguage: String?
    private var voice: AVSpeechSynthesisVoice?
    private var shouldReloadUtteranceOnResume = false
    private var ignoreFinishCallCount = 0
    var speechRateModifier: Float {
        didSet {
            utteranceChanged()
        }
    }
    var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }
    var isPaused: Bool {
        return synthesizer.isPaused
    }
    var speechVoice: SpeechVoice? {
        return voice.flatMap({ .local($0) })
    }

    init(language: String?, speechRateModifier: Float, state: BehaviorRelay<SpeechState>, delegate: VoiceProcessorDelegate) {
        preferredLanguage = language
        self.speechRateModifier = speechRateModifier
        self.delegate = delegate
        self.state = state
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, shouldDetectVoice: Bool) {
        if synthesizer.isSpeaking {
            ignoreFinishCallCount += 1
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        if voice == nil || shouldDetectVoice {
            voice = voice(for: text)
        }

        let utterance = AVSpeechUtterance(string: text)
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
        guard synthesizer.isSpeaking || synthesizer.isPaused || state.value == .loading else { return }
        if state.value == .loading {
            state.accept(.stopped)
        } else {
            // Ignore finish delegate, which would move us to another page
            ignoreFinishCallCount = 1
            synthesizer.stopSpeaking(at: .immediate)
            state.accept(.stopped)
        }
    }

    func set(voice: AVSpeechSynthesisVoice, preferredLanguage: String?) {
        guard self.voice?.identifier != voice.identifier else { return }
        Defaults.shared.defaultLocalVoiceForLanguage[voice.baseLanguage] = voice.identifier
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
        guard let pageText = delegate.currentPageText, let speech = delegate.speech else { return }
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        }
        let text = String(pageText[pageText.index(pageText.startIndex, offsetBy: speech.globalRange.location)..<pageText.endIndex])
        speak(text: text, shouldDetectVoice: false)
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
}

extension LocalVoiceProcessor: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        delegate.didFinishSpeaking()
        state.accept(.stopped)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        state.accept(.paused)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        state.accept(.speaking)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        state.accept(.speaking)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard ignoreFinishCallCount <= 0 else {
            ignoreFinishCallCount -= 1
            return
        }

        if !delegate.goToNextPageIfAvailable() {
            delegate.didFinishSpeaking()
            state.accept(.stopped)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard characterRange.length > 0 else { return }
        delegate.speechRangeWillChange(to: characterRange)
    }
}

private final class RemoteVoiceProcessor: VoiceProcessor {
    let state: BehaviorRelay<SpeechState>
    
    var preferredLanguage: String?
    var speechRateModifier: Float
    var isSpeaking: Bool {
        return false
    }
    var isPaused: Bool {
        return false
    }
    var speechVoice: SpeechVoice? {
        return nil
    }

    init(language: String?, speechRateModifier: Float, state: BehaviorRelay<SpeechState>) {
        preferredLanguage = language
        self.speechRateModifier = speechRateModifier
        self.state = state
    }
    
    func set(voice: RemoteVoice, preferredLanguage: String?) {
        self.preferredLanguage = preferredLanguage
    }

    func speak(text: String, shouldDetectVoice: Bool) {
    }

    func pause() {
    }

    func resume() {
    }

    func stop() {
    }
}
